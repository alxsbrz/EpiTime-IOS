import Foundation
import Observation

struct AppSession: Codable, Sendable {
    var microsoft: MicrosoftTokens
    var zeusToken: String
    var zeusRefreshedAt: Date
    var profile: MicrosoftProfile?
}

/// Owns the signed-in state and hands `APIClient` a always-valid Zeus token.
@MainActor
@Observable
final class AuthStore {
    enum Phase: Equatable {
        case booting
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .booting
    private(set) var profile: MicrosoftProfile?
    private(set) var isWorking = false
    var lastError: String?

    private var session: AppSession? {
        didSet {
            profile = session?.profile
            if let session {
                Keychain.setJSON(session, for: Self.sessionKey)
            } else {
                Keychain.remove(Self.sessionKey)
            }
        }
    }

    private static let sessionKey = "session.v2"
    private var refreshTask: Task<AppSession, Error>?

    init() {}

    func bootstrap() async {
        await APIClient.shared.setTokenProvider { [weak self] force in
            guard let self else { throw AuthError.reconnectRequired }
            return try await self.token(forceRefresh: force)
        }
        session = Keychain.json(AppSession.self, for: Self.sessionKey)
        phase = session == nil ? .signedOut : .signedIn
        if Screenshots.isActive, phase == .signedOut { signInDemo() }
    }

    /// Opens the app on made-up data, no account needed (App Review, curious visitors).
    func signInDemo() {
        DemoMode.setActive(true)
        Preferences.shared.selectedGroupIDs = [DemoMode.defaultGroup.id]
        Preferences.shared.selectedGroupNames = [DemoMode.defaultGroup.id: DemoMode.defaultGroup.name]
        lastError = nil
        session = AppSession(
            microsoft: MicrosoftTokens(accessToken: "demo", refreshToken: nil, expiresAt: .distantFuture),
            zeusToken: "demo",
            zeusRefreshedAt: .now,
            profile: DemoMode.profile
        )
        phase = .signedIn
    }

    func signIn() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let (tokens, profile) = try await MicrosoftAuth.shared.signIn()
            let zeus = try await Self.exchangeZeusToken(microsoftAccessToken: tokens.accessToken)
            session = AppSession(microsoft: tokens, zeusToken: zeus, zeusRefreshedAt: .now, profile: profile)
            phase = .signedIn
        } catch AuthError.cancelled {
            // Silent: the user closed the sheet on purpose.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        if DemoMode.isActive {
            DemoMode.setActive(false)
            Preferences.shared.clearGroups()
            Task { await DiskCache.shared.clear() }
        }
        session = nil
        phase = .signedOut
    }

    // MARK: Token plumbing

    private func token(forceRefresh: Bool) async throws -> String {
        guard let current = session else { throw AuthError.reconnectRequired }
        let microsoftExpired = current.microsoft.expiresAt <= Date()
        guard forceRefresh || microsoftExpired else { return current.zeusToken }
        let refreshed = try await renew()
        return refreshed.zeusToken
    }

    /// Coalesces concurrent refreshes so a burst of 401s triggers a single round trip.
    private func renew() async throws -> AppSession {
        if let refreshTask { return try await refreshTask.value }

        let task = Task { () throws -> AppSession in
            guard let current = session, let refreshToken = current.microsoft.refreshToken else {
                throw AuthError.reconnectRequired
            }
            let tokens = try await MicrosoftAuth.shared.refresh(using: refreshToken)
            let zeus = try await Self.exchangeZeusToken(microsoftAccessToken: tokens.accessToken)
            var next = current
            next.microsoft = tokens
            next.zeusToken = zeus
            next.zeusRefreshedAt = .now
            return next
        }
        refreshTask = task

        do {
            let next = try await task.value
            refreshTask = nil
            session = next
            return next
        } catch {
            refreshTask = nil
            session = nil
            phase = .signedOut
            throw AuthError.reconnectRequired
        }
    }

    private static func exchangeZeusToken(microsoftAccessToken: String) async throws -> String {
        struct Body: Encodable, Sendable { let accessToken: String }
        struct Payload: Decodable, Sendable { let token: String }
        let payload: Payload = try await APIClient.shared.post("/api/auth", body: Body(accessToken: microsoftAccessToken), authenticated: false)
        return payload.token
    }
}
