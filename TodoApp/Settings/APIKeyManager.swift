import Foundation
import Security

/// Manages secure storage of API keys in macOS Keychain
class APIKeyManager {
    static let shared = APIKeyManager()

    private let serviceName = "com.todoapp.anthropic"
    private let accountName = "claude-api-key"

    private init() {}

    // MARK: - Public Methods

    /// Saves the API key to the Keychain
    /// - Parameter key: The API key to store
    /// - Throws: KeychainError if the operation fails
    func saveAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // First try to delete any existing key
        try? deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieves the API key from the Keychain
    /// - Returns: The stored API key, or nil if not found
    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Deletes the API key from the Keychain
    /// - Throws: KeychainError if the operation fails
    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Checks if an API key is stored
    /// - Returns: true if an API key exists in the Keychain
    var hasAPIKey: Bool {
        return getAPIKey() != nil
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode API key"
        case .saveFailed(let status):
            return "Failed to save API key: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete API key: \(status)"
        }
    }
}
