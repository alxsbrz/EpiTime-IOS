import Foundation
import SwiftUI
import WebKit

/// Auriga sits behind a Keycloak realm, separate from the Microsoft account used for
/// Zeus. Its redirect URI is an https page rather than a custom scheme, so the code is
/// captured from inside a web view instead of `ASWebAuthenticationSession`.
enum Auriga {
    static let api = "https://auriga.epita.fr/api"
    static let realm = "https://ionisepita-auth.np-auriga.nfrance.net/auth/realms/npionisepita"
    static let authorizeURL = "\(realm)/protocol/openid-connect/auth"
    static let tokenURL = "\(realm)/protocol/openid-connect/token"
    static let clientID = "np-front"
    static let redirectURI = "https://auriga.epita.fr/#/mainContent/welcome"
    static let scopes = "openid profile email"
}

struct AurigaTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var refreshExpiresAt: Date?
}

struct AurigaError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    static let loginRequired = AurigaError(message: "Connecte-toi à Auriga pour voir tes notes.")
}

/// Holds the Auriga token set and keeps it fresh.
@MainActor
final class AurigaSession {
    static let shared = AurigaSession()

    private static let storageKey = "auriga.tokens"
    private var tokens: AurigaTokens?
    private var refreshTask: Task<AurigaTokens, Error>?

    private init() {
        tokens = Keychain.json(AurigaTokens.self, for: Self.storageKey)
    }

    var hasStoredCredentials: Bool {
        guard let tokens, tokens.refreshToken != nil else { return false }
        if let expiry = tokens.refreshExpiresAt, expiry <= Date() { return false }
        return true
    }

    func store(_ tokens: AurigaTokens) {
        self.tokens = tokens
        Keychain.setJSON(tokens, for: Self.storageKey)
    }

    func clear() {
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        Keychain.remove(Self.storageKey)
    }

    /// A valid access token, refreshing once if the current one is within its margin.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw AurigaError.loginRequired }
        if !forceRefresh, current.expiresAt.addingTimeInterval(-10) > Date() {
            return current.accessToken
        }
        return try await refresh().accessToken
    }

    private func refresh() async throws -> AurigaTokens {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { () throws -> AurigaTokens in
            guard let refreshToken = tokens?.refreshToken else { throw AurigaError.loginRequired }
            return try await AurigaAuthFlow.exchange(parameters: [
                "client_id": Auriga.clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ], fallbackRefreshToken: refreshToken)
        }
        refreshTask = task
        do {
            let fresh = try await task.value
            refreshTask = nil
            store(fresh)
            return fresh
        } catch {
            refreshTask = nil
            clear()
            throw AurigaError.loginRequired
        }
    }
}

enum AurigaAuthFlow {
    /// One authorisation attempt: the URL to load plus the PKCE material to finish it.
    struct Attempt {
        let url: URL
        let verifier: String
        let state: String
    }

    static func start() -> Attempt {
        let verifier = PKCE.verifier()
        let state = PKCE.verifier().prefix(24).description
        var components = URLComponents(string: Auriga.authorizeURL)!
        components.queryItems = [
            .init(name: "client_id", value: Auriga.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "response_mode", value: "query"),
            .init(name: "redirect_uri", value: Auriga.redirectURI),
            .init(name: "scope", value: Auriga.scopes),
            .init(name: "prompt", value: "login"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return Attempt(url: components.url!, verifier: verifier, state: state)
    }

    /// Keycloak returns the code either in the query or inside the fragment's query part.
    static func code(in url: URL) -> (code: String, state: String?)? {
        func parse(_ query: String) -> (String, String?)? {
            let items = URLComponents(string: "?\(query)")?.queryItems ?? []
            guard let code = items.first(where: { $0.name == "code" })?.value else { return nil }
            return (code, items.first(where: { $0.name == "state" })?.value)
        }
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query, let found = parse(query) { return found }
        if let fragment = url.fragment, let index = fragment.firstIndex(of: "?"), let found = parse(String(fragment[fragment.index(after: index)...])) { return found }
        return nil
    }

    static func finish(code: String, attempt: Attempt) async throws -> AurigaTokens {
        try await exchange(parameters: [
            "client_id": Auriga.clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Auriga.redirectURI,
            "code_verifier": attempt.verifier,
        ], fallbackRefreshToken: nil)
    }

    static func exchange(parameters: [String: String], fallbackRefreshToken: String?) async throws -> AurigaTokens {
        var request = URLRequest(url: URL(string: Auriga.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = PKCE.formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_description"] as? String
            throw AurigaError(message: detail ?? "Connexion Auriga refusée.")
        }

        struct Payload: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
            let refresh_expires_in: Double?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return AurigaTokens(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token ?? fallbackRefreshToken,
            expiresAt: Date().addingTimeInterval(max(30, payload.expires_in ?? 60)),
            refreshExpiresAt: payload.refresh_expires_in.map { Date().addingTimeInterval($0) }
        )
    }
}

// MARK: - Login web view

/// Loads the Keycloak page and reports the authorisation code as soon as the browser
/// is redirected back to Auriga.
struct AurigaLoginWebView {
    let attempt: AurigaAuthFlow.Attempt
    var onCode: (String) -> Void
    var onFailure: (String) -> Void

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AurigaLoginWebView
        private var finished = false

        init(parent: AurigaLoginWebView) { self.parent = parent }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard !finished, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if let found = AurigaAuthFlow.code(in: url) {
                finished = true
                decisionHandler(.cancel)
                if let state = found.state, state != parent.attempt.state {
                    parent.onFailure("État OAuth invalide.")
                } else {
                    parent.onCode(found.code)
                }
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !finished else { return }
            parent.onFailure(error.localizedDescription)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    fileprivate func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.load(URLRequest(url: attempt.url))
        return webView
    }
}

#if os(iOS)
extension AurigaLoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#else
extension AurigaLoginWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif
