import Foundation
import Security

// MARK: - Keychain Helper
//
// Thin wrapper around the macOS Keychain Services API.
// Stores and retrieves API keys as generic passwords scoped
// to ChatHarbor's app sandbox. Sandboxed apps automatically
// get their own keychain partition — no extra entitlements needed.

enum KeychainHelper {

    /// Save a string value to the keychain under the given key.
    /// Overwrites any existing value for that key.
    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        // Delete any existing item first (update = delete + add)
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: bundleService,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a string value from the keychain for the given key.
    /// Returns nil if not found or on error.
    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: bundleService,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Delete a value from the keychain for the given key.
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: bundleService,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Migration

    /// Migrate a key from UserDefaults to Keychain.
    /// Reads from UserDefaults, writes to Keychain, then removes from UserDefaults.
    /// No-op if UserDefaults has no value or Keychain already has one.
    static func migrateFromUserDefaults(userDefaultsKey: String, keychainKey: String) {
        // Skip if keychain already has a value
        if load(forKey: keychainKey) != nil { return }

        // Read from UserDefaults
        guard let value = UserDefaults.standard.string(forKey: userDefaultsKey),
              !value.isEmpty else { return }

        // Write to keychain
        if save(value, forKey: keychainKey) {
            // Remove the plaintext value from UserDefaults
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    // MARK: - Private

    /// Service identifier — scopes all keychain items to this app.
    private static let bundleService = Bundle.main.bundleIdentifier ?? "com.dedgar.ChatHarbor"
}
