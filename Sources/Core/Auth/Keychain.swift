import Foundation
import Security

/// Minimal Keychain wrapper for the few secrets the app holds (Zeus + Microsoft +
/// Auriga tokens). Values are stored as generic passwords scoped to this app.
enum Keychain {
    private static let service = "fr.alexistb2904.epitime"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func setJSON<T: Encodable>(_ value: T, for key: String) {
        guard let data = try? JSONEncoder().encode(value), let string = String(data: data, encoding: .utf8) else { return }
        set(string, for: key)
    }

    static func json<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let string = get(key), let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
