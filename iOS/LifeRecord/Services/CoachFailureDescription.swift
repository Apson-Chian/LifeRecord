import Foundation

enum CoachFailureDescription {
    static func message(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet: return "网络暂不可用，连接网络后可重新生成。"
            case .networkConnectionLost, .cannotConnectToHost: return "网络连接中断，问题和已附图片已保留。"
            case .timedOut: return "等待回答超时，可稍后重新生成。"
            case .cancelled: return "请求被中断，问题和已附图片已保留。"
            default: return "网络请求失败，可检查网络后重新生成。"
            }
        }
        return error.localizedDescription
    }
}
