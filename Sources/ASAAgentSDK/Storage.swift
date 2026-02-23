import Foundation
import Security

/// Manages persistent storage: device ID (Keychain) and attribution state (UserDefaults).
final class Storage {

    /// Persistent anonymous device ID. Stored in Keychain so it survives app reinstalls.
    let deviceId: String

    init() {
        if let existing = Self.readKeychain(key: SDKConstants.keychainDeviceIdKey) {
            self.deviceId = existing
        } else {
            let newId = UUID().uuidString.lowercased()
            Self.writeKeychain(key: SDKConstants.keychainDeviceIdKey, value: newId)
            // Verify write succeeded, fall back to in-memory if not
            if let written = Self.readKeychain(key: SDKConstants.keychainDeviceIdKey) {
                self.deviceId = written
            } else {
                self.deviceId = newId
            }
        }
    }

    // MARK: - Attribution State

    /// Whether the attribution token has already been sent to the backend.
    var attributionSent: Bool {
        get { UserDefaults.standard.bool(forKey: SDKConstants.attributionSentKey) }
        set { UserDefaults.standard.set(newValue, forKey: SDKConstants.attributionSentKey) }
    }

    // MARK: - Keychain Helpers

    private static func readKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SDKConstants.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SDKConstants.keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SDKConstants.keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        #if os(iOS) || os(tvOS) || os(watchOS)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif

        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
