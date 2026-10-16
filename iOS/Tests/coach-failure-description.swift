import Foundation
@main struct FailureChecks {
    static func main() {
        assert(CoachFailureDescription.message(for: URLError(.networkConnectionLost)).contains("问题和已附图片已保留"))
        assert(CoachFailureDescription.message(for: URLError(.notConnectedToInternet)).contains("连接网络"))
        assert(CoachFailureDescription.message(for: URLError(.timedOut)).contains("超时"))
        assert(CoachFailureDescription.message(for: URLError(.cancelled)).contains("被中断"))
        print("PASS: disconnected, lost connection, timeout and interrupted request descriptions")
    }
}
