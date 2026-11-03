import Foundation
import Security

enum KeychainStore {
    private static let service = "com.bat.minivoice"
    private static let legacyService = "com.bat.mac-voice"
    private static let account = "siliconflow_api_key"

    static func loadAPIKey() -> String {
        if let value = readKey(service: service), !value.isEmpty {
            return value
        }
        // 兼容旧版 Mac Voice 钥匙串
        if let legacy = readKey(service: legacyService), !legacy.isEmpty {
            saveAPIKey(legacy)
            return legacy
        }
        return ""
    }

    private static func readKey(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteAPIKey()
        guard !trimmed.isEmpty else { return }

        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteAPIKey() {
        for svc in [service, legacyService] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: svc,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
