import Foundation

enum AppConfig {
    static let apiBase = URL(string: "https://epitime.epita.it")!
    static let microsoftClientID = "e1fe2b8e-1bb4-455d-85fa-5cbbb409143b"
    static let microsoftTenant = "epita.fr"
    static let microsoftRedirectURI = "epitime://auth"
    static let microsoftCallbackScheme = "epitime"
    static let microsoftScopes = ["openid", "profile", "User.Read", "offline_access"]
}

enum APIError: LocalizedError, Sendable {
    case unauthorized
    case offline
    case timedOut
    case server(status: Int, message: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Session expirée, reconnecte-toi pour continuer."
        case .offline: "Pas de connexion. Affichage des données en cache."
        case .timedOut: "Le serveur met trop de temps à répondre."
        case let .server(status, message): message?.trimmed.nilIfEmpty ?? "Erreur serveur (\(status))."
        case let .decoding(detail): "Réponse inattendue du serveur. (\(detail))"
        }
    }

    var isRecoverableByRetry: Bool {
        switch self {
        case .offline, .timedOut: true
        case let .server(status, _): status >= 500
        default: false
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Thin async wrapper over the EpiTime proxy. Token refresh is delegated upwards so
/// the client itself stays free of auth state.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Set by `AuthStore`; returns a fresh Zeus token or throws when reconnection is required.
    private var tokenProvider: (@Sendable (_ forceRefresh: Bool) async throws -> String)?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder()
    }

    func setTokenProvider(_ provider: @escaping @Sendable (_ forceRefresh: Bool) async throws -> String) {
        tokenProvider = provider
    }

    // MARK: Requests

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> T {
        try await perform(path: path, method: "GET", query: query, body: nil, authenticated: authenticated)
    }

    func post<T: Decodable & Sendable>(_ path: String, body: Encodable & Sendable, authenticated: Bool = true) async throws -> T {
        let data = try JSONEncoder().encode(AnyEncodable(body))
        return try await perform(path: path, method: "POST", query: [], body: data, authenticated: authenticated)
    }

    private func perform<T: Decodable & Sendable>(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        authenticated: Bool,
        isRetry: Bool = false
    ) async throws -> T {
        var components = URLComponents(url: AppConfig.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.decoding("URL invalide") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let tokenProvider else { throw APIError.unauthorized }
            let token = try await tokenProvider(isRetry)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw APIError.offline
            case .timedOut: throw APIError.timedOut
            default: throw APIError.server(status: error.errorCode, message: error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.decoding("Réponse non HTTP") }

        if http.statusCode == 401 {
            // One shot at a refreshed token before giving up on the session.
            if authenticated, !isRetry {
                return try await perform(path: path, method: method, query: query, body: body, authenticated: true, isRetry: true)
            }
            throw APIError.unauthorized
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }

        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T { return empty }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error).prefix(160).description)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["error"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8)?.trimmed.nilIfEmpty
    }
}

struct EmptyResponse: Codable, Sendable {}

/// Type-erasing box so `post` can take any `Encodable` without generics leaking outwards.
private struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeTo = wrapped.encode(to:) }
    func encode(to encoder: Encoder) throws { try encodeTo(encoder) }
}
