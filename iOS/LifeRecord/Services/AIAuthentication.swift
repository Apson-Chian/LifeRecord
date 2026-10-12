import Foundation

/// Shared by key storage and request construction, including older saved credentials.
enum AIAuthentication {
    static func isOfficialDeepSeek(_ endpoint: String) -> Bool {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == "api.deepseek.com" && (url.port == nil || url.port == 443)
    }

    static func normalizedKey(_ raw: String, bearer: Bool) throws -> String {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if bearer {
            if key.lowercased().hasPrefix("authorization:") { key = String(key.dropFirst("authorization:".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            if key.lowercased().hasPrefix("bearer ") { key = String(key.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) }
            if key.count >= 2 && ((key.first == "\"" && key.last == "\"") || (key.first == "'" && key.last == "'")) { key = String(key.dropFirst().dropLast()) }
        }
        guard !key.isEmpty else { throw CredentialError.empty }
        guard key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw CredentialError.invalidCharacters }
        guard !key.contains("***") else { throw CredentialError.masked }
        return key
    }

    static func header(endpoint: String, style: String, customHeader: String, key raw: String) throws -> (name: String, value: String) {
        let bearer = isOfficialDeepSeek(endpoint) || style == "Bearer Token"
        let key = try normalizedKey(raw, bearer: bearer)
        if bearer { return ("Authorization", "Bearer \(key)") }
        if style == "api-key 请求头" { return ("api-key", key) }
        let name = customHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = "()<>@,;:\\\"/[]?={} \t"
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }), !name.contains(where: separators.contains) else { throw CredentialError.invalidHeader }
        return (name, key)
    }

    static func deepSeekFailure(status: Int) -> String? {
        switch status {
        case 401: return "DeepSeek 鉴权失败（HTTP 401）。已使用官方 Bearer 认证；请在 platform.deepseek.com 创建或重新复制完整 API Key，保存并测试。网页登录凭证、已删除密钥和其他平台的密钥不能用于官方接口。"
        case 402: return "DeepSeek 余额不足（HTTP 402）。请在 platform.deepseek.com 核对 API 账户余额。"
        default: return nil
        }
    }

    enum CredentialError: LocalizedError {
        case empty, invalidCharacters, masked, invalidHeader
        var errorDescription: String? {
            switch self {
            case .empty: "API Key 不能为空。"
            case .invalidCharacters: "API Key 含空格、换行或不可见字符，请重新粘贴完整密钥。"
            case .masked: "粘贴的是被隐藏的密钥，请重新复制完整 API Key。"
            case .invalidHeader: "自定义认证请求头名称无效。"
            }
        }
    }
}
