import AuthenticationServices
import CryptoKit
import Foundation

struct MicrosoftTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

struct MicrosoftProfile: Codable, Sendable, Hashable {
    var id: String?
    var displayName: String?
    var mail: String?
    var userPrincipalName: String?

    var initials: String {
        let source = displayName ?? userPrincipalName ?? mail ?? "?"
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? String(source.prefix(1)).uppercased() : letters.uppercased()
    }

    var shortName: String {
        displayName?.split(separator: " ").first.map(String.init) ?? "Étudiant"
    }
}

enum AuthError: LocalizedError {
    case cancelled
    case missingToken
    case reconnectRequired
    case message(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Connexion annulée."
        case .missingToken: "Microsoft n'a pas renvoyé de jeton."
        case .reconnectRequired: "Session expirée, reconnecte-toi pour continuer."
        case let .message(text): text
        }
    }
}

/// Microsoft Entra authorisation-code + PKCE flow, driven by `ASWebAuthenticationSession`
/// so the system browser (and therefore the existing EPITA SSO cookie) is reused.
@MainActor
final class MicrosoftAuth: NSObject {
    static let shared = MicrosoftAuth()

    private var authorizeURL: URL {
        var components = URLComponents(string: "https://login.microsoftonline.com/\(AppConfig.microsoftTenant)/oauth2/v2.0/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: AppConfig.microsoftClientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: AppConfig.microsoftRedirectURI),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: AppConfig.microsoftScopes.joined(separator: " ")),
            .init(name: "prompt", value: "select_account"),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return components.url!
    }

    private var tokenURL: URL {
        URL(string: "https://login.microsoftonline.com/\(AppConfig.microsoftTenant)/oauth2/v2.0/token")!
    }

    private var codeVerifier = ""
    private var codeChallenge = ""
    private var state = ""
    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> (MicrosoftTokens, MicrosoftProfile?) {
        codeVerifier = PKCE.verifier()
        codeChallenge = PKCE.challenge(for: codeVerifier)
        state = PKCE.verifier().prefix(24).description

        let callback = try await authorize()
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { throw AuthError.missingToken }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error_description" })?.value ?? items.first(where: { $0.name == "error" })?.value {
            throw AuthError.message(error)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.cancelled }
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthError.message("État OAuth invalide.") }

        let tokens = try await exchange(parameters: [
            "client_id": AppConfig.microsoftClientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AppConfig.microsoftRedirectURI,
            "code_verifier": codeVerifier,
            "scope": AppConfig.microsoftScopes.joined(separator: " "),
        ])
        let profile = await fetchProfile(accessToken: tokens.accessToken)
        return (tokens, profile)
    }

    func refresh(using refreshToken: String) async throws -> MicrosoftTokens {
        var tokens = try await exchange(parameters: [
            "client_id": AppConfig.microsoftClientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": AppConfig.microsoftScopes.joined(separator: " "),
        ])
        if tokens.refreshToken == nil { tokens.refreshToken = refreshToken }
        return tokens
    }

    // MARK: Plumbing

    private func authorize() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: AppConfig.microsoftCallbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AuthError.message("Impossible d'ouvrir la fenêtre de connexion."))
            }
        }
    }

    private func exchange(parameters: [String: String]) async throws -> MicrosoftTokens {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = PKCE.formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_description"] as? String
            throw AuthError.message(detail ?? "Échec de l'authentification Microsoft.")
        }

        struct Payload: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        // Renew five minutes early so a request never races the expiry.
        let lifetime = max(60, (payload.expires_in ?? 3600) - 300)
        return MicrosoftTokens(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date().addingTimeInterval(lifetime)
        )
    }

    private func fetchProfile(accessToken: String) async -> MicrosoftProfile? {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(MicrosoftProfile.self, from: data)
    }
}

extension MicrosoftAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { PresentationAnchor.current() }
    }
}

enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formBody(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = parameters.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}
