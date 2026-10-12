import Foundation

/// Describes the failing stage without exposing health values or response bodies.
enum SyncFailureDescription {
    static func message(for error: Error) -> String {
        if let error = error as? DecodingError {
            switch error {
            case .keyNotFound(let key, let context):
                return "服务器返回的数据缺少字段：\(path(context.codingPath + [key]))。请检查 App 与后端版本是否兼容。"
            case .typeMismatch(_, let context), .valueNotFound(_, let context):
                return "服务器返回的字段格式不兼容：\(path(context.codingPath))。请检查后端数据格式。"
            case .dataCorrupted(let context):
                return "服务器返回的数据无法解析（\(path(context.codingPath))），请检查同步接口。"
            @unknown default:
                return "服务器返回的数据无法解析，请检查同步接口。"
            }
        }
        if error is EncodingError {
            return "本机记录无法转换为同步数据，请检查记录中是否存在无效数值。"
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet: return "手机当前没有网络，请连接网络后重试。"
            case .timedOut: return "同步请求超时，请稍后重试。"
            case .cannotFindHost, .dnsLookupFailed: return "手机无法解析同步服务器地址，请检查网络或 DNS。"
            case .cannotConnectToHost, .networkConnectionLost: return "手机与同步服务器的连接失败或中断，请检查网络后重试。"
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                return "无法建立安全连接，请检查手机日期与服务器证书。"
            default: return "网络请求失败（\(error.code.rawValue)）：\(error.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.isEmpty ? "响应根节点" : keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
}
