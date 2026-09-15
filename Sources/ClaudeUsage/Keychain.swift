import Foundation
import Security

// accounts (incl. session cookies) live in the login keychain, one blob for the whole list.
// keeping it in one item keeps ordering stable and add/remove trivial.
enum KeychainStore {
    private static let service = "com.laszlo.ClaudeUsage.accounts"
    private static let key = "accounts.v1"

    static func load() -> [Account] {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let accounts = try? JSONDecoder().decode([Account].self, from: data)
        else { return [] }
        return accounts
    }

    @discardableResult
    static func save(_ accounts: [Account]) -> Bool {
        guard let data = try? JSONEncoder().encode(accounts) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // upsert: try update, fall back to add
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
