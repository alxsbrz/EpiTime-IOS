import Foundation
import Observation

/// Talks to Auriga's search API and turns the raw rows into displayable periods.
@MainActor
@Observable
final class GradesStore {
    enum State: Equatable {
        case signedOut
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .signedOut
    private(set) var periods: [GradesPeriod] = []
    private(set) var lastSyncedAt: Date?
    private(set) var servedFromCache = false

    private static let cacheKey = "auriga.grades"
    private static let syncedKey = "auriga.syncedAt"

    func bootstrap() async {
        if DemoMode.isActive {
            loadDemo()
            return
        }
        if let cached = await DiskCache.shared.load([AurigaGrade].self, for: Self.cacheKey), !cached.value.isEmpty {
            periods = GradesEngine.build(from: cached.value)
            lastSyncedAt = cached.storedAt
            servedFromCache = true
            state = .ready
        }
        guard AurigaSession.shared.hasStoredCredentials else {
            if periods.isEmpty { state = .signedOut }
            return
        }
        await sync()
    }

    func sync(force: Bool = false) async {
        if DemoMode.isActive {
            loadDemo()
            return
        }
        guard AurigaSession.shared.hasStoredCredentials else {
            state = .signedOut
            return
        }
        if periods.isEmpty { state = .loading }
        do {
            let grades = try await AurigaClient.fetchGrades()
            periods = GradesEngine.build(from: grades)
            lastSyncedAt = .now
            servedFromCache = false
            state = .ready
            await DiskCache.shared.save(grades, for: Self.cacheKey)
        } catch is AurigaError {
            state = periods.isEmpty ? .signedOut : .ready
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = periods.isEmpty ? .failed(message) : .ready
        }
    }

    private func loadDemo() {
        periods = GradesEngine.build(from: DemoData.grades)
        lastSyncedAt = .now
        servedFromCache = false
        state = .ready
    }

    func didSignIn() async {
        state = .loading
        await sync(force: true)
    }

    func signOut() {
        AurigaSession.shared.clear()
        periods = []
        lastSyncedAt = nil
        state = .signedOut
        Task { await DiskCache.shared.remove(Self.cacheKey) }
    }
}

enum AurigaClient {
    /// Auriga paginates its grade search; 100 rows a page, stop on the last one.
    static func fetchGrades() async throws -> [AurigaGrade] {
        guard let payload = searchPayload() else {
            throw AurigaError(message: "Requête Auriga indisponible dans l'app.")
        }

        var rows: [[Any]] = []
        var page = 1
        while page < 30 {
            let response = try await post(
                path: "/menuEntries/1036/searchResult?size=100&page=\(page)&sort=id&disableWarnings=true",
                body: payload
            )
            let content = (response["content"] as? [String: Any]) ?? response
            let lines = (content["lines"] as? [[Any]]) ?? []
            rows.append(contentsOf: lines)

            let isLast = (content["last"] as? Bool) ?? false
            let totalPages = content["totalPages"] as? Int
            if isLast || lines.count < 100 || (totalPages.map { page >= $0 } ?? false) { break }
            page += 1
        }
        return rows.compactMap(parse(row:))
    }

    /// Row layout: [code, grade, coefficient, itemName, typeName].
    static func parse(row: [Any]) -> AurigaGrade? {
        guard row.count >= 5 else { return nil }

        func text(_ value: Any?) -> String {
            switch value {
            case let string as String: string
            case let number as NSNumber: number.stringValue
            default: ""
            }
        }

        let raw = text(row[1]).trimmed
        guard !raw.isEmpty else { return nil }

        let name = text(row[3])
        var semester = 0
        if let range = name.range(of: #"_S(\d+)_"#, options: .regularExpression) {
            semester = Int(name[range].replacingOccurrences(of: "_S", with: "").replacingOccurrences(of: "_", with: "")) ?? 0
        }

        var value = 0.0
        var alphaMark: String?
        switch raw.uppercased() {
        case "VA", "VALIDE", "VALIDÉ": alphaMark = "VA"
        case "NV", "NON VALIDE", "NON VALIDÉ": alphaMark = "NV"
        default:
            guard let parsed = Double(raw.replacingOccurrences(of: ",", with: ".")) else { return nil }
            value = parsed
        }

        let coefficient = Double(text(row[2]).replacingOccurrences(of: ",", with: ".")) ?? 100

        return AurigaGrade(
            code: text(row[0]),
            type: text(row[4]),
            name: name,
            semester: semester,
            value: value,
            coefficient: coefficient > 0 ? coefficient / 100 : 1,
            alphaMark: alphaMark
        )
    }

    private static func searchPayload() -> Data? {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "grades", withExtension: "json")
            ?? bundle.url(forResource: "grades", withExtension: "json", subdirectory: "AurigaPayloads")
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    private static func post(path: String, body: Data, isRetry: Bool = false) async throws -> [String: Any] {
        let token = try await AurigaSession.shared.accessToken(forceRefresh: isRetry)
        var request = URLRequest(url: URL(string: Auriga.api + path)!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AurigaError(message: "Réponse Auriga invalide.")
        }
        if http.statusCode == 401 {
            guard !isRetry else { throw AurigaError.loginRequired }
            return try await post(path: path, body: body, isRetry: true)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AurigaError(message: "Auriga a répondu \(http.statusCode).")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
