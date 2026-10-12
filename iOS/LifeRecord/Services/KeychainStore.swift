import Foundation
import Security

enum KeychainStore {
    private static let service = "com.aotelei.LifeRecord"
    private static let legacyAccount = "ai-api-key"
    private static let syncAccount = "liferecord-sync-key"

    static func saveSyncKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptySyncKey }
        try upsert(Data(trimmed.utf8), account: syncAccount)
    }

    static func loadSyncKey() -> String {
        load(account: syncAccount) ?? ""
    }

    static var hasSyncKey: Bool { !loadSyncKey().isEmpty }

    static func deleteSyncKey() throws {
        try delete(account: syncAccount)
    }

    static func saveAPIKey(_ key: String, for provider: AIProvider) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyKey }
        try upsert(Data(trimmed.utf8), account: account(for: provider))
    }

    static func loadAPIKey(for provider: AIProvider) -> String {
        if let key = load(account: account(for: provider)) { return key }
        // 旧版本只有一个密钥槽，默认服务商是 GLM；仅在 GLM 下兼容读取，
        // 防止切换到 Dots/DeepSeek 时误发其他服务商的密钥。
        if provider == .glm, let legacy = load(account: legacyAccount) { return legacy }
        return ""
    }

    static func hasAPIKey(for provider: AIProvider) -> Bool {
        !loadAPIKey(for: provider).isEmpty
    }

    static func deleteAPIKey(for provider: AIProvider) throws {
        try delete(account: account(for: provider))
        if provider == .glm { try delete(account: legacyAccount) }
    }

    private static func account(for provider: AIProvider) -> String {
        "ai-api-key.\(provider.keychainID)"
    }

    private static func upsert(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    enum KeychainError: LocalizedError {
        case emptyKey
        case emptySyncKey
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyKey:
                return "API Key 不能为空。"
            case .emptySyncKey:
                return "同步密钥不能为空。"
            case .status(let status):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "未知系统错误"
                return "API Key 保存失败：\(detail)（\(status)）"
            }
        }
    }
}
