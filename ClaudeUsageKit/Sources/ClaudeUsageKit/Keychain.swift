import Foundation
import Security

// accounts (incl. session cookies) live in the keychain, one blob for the whole list.
// keeping it in one item keeps ordering stable and add/remove trivial.
//
// `accessGroup` is the iOS app↔widget sharing hook: set it once at launch and both
// processes read the same item. leave it nil on macOS — an access group there must match
// the signing identity, and build.sh only ad-hoc signs.
public enum KeychainStore {
    private static let service = "com.laszlo.ClaudeUsage.accounts"
    private static let key = "accounts.v1"

    public nonisolated(unsafe) static var accessGroup: String?

    // shared base query. the access group is only attached when one is configured —
    // passing a group you aren't entitled to makes every call fail with errSecMissingEntitlement.
    private static func baseQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let g = accessGroup, !g.isEmpty { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    public static func load() -> [Account] {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let accounts = try? JSONDecoder().decode([Account].self, from: data)
        else { return [] }
        return accounts
    }

    @discardableResult
    public static func save(_ accounts: [Account]) -> Bool {
        guard let data = try? JSONEncoder().encode(accounts) else { return false }
        let base = baseQuery()
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
