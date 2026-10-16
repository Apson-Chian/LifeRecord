import Foundation

@MainActor final class AIAnswerNotificationCenter {
    static let shared = AIAnswerNotificationCenter()
    var completed: [UUID] = []
    func notifyAnswerReady(conversationID: UUID) { completed.append(conversationID) }
}

@MainActor final class BackgroundProbe: CoachBackgroundExecuting {
    var live: [UUID: @MainActor () -> Void] = [:]
    var starts = 0
    var finishes = 0
    var expireImmediately = false
    func begin(_ id: UUID, expiration: @escaping @MainActor () -> Void) {
        starts += 1; live[id] = expiration
        if expireImmediately { expiration() }
    }
    func end(_ id: UUID) { if live.removeValue(forKey: id) != nil { finishes += 1 } }
    func expire(_ id: UUID) { live[id]?() }
}

@main struct CoachTaskChecks {
    @MainActor static func drained(_ center: CoachTaskCenter) async throws {
        for _ in 0..<500 {
            if !center.isGenerating { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        preconditionFailure("A finished/cancelled request must release its task")
    }
    @MainActor static func main() async throws {
        let background = BackgroundProbe()
        let center = CoachTaskCenter(background: background)
        let first = UUID(), second = UUID()
        assert(center.submit(conversationID: first, question: "第一问") { try await Task.sleep(for: .milliseconds(20)) })
        assert(!center.submit(conversationID: first, question: "不能重复提交") {})
        assert(center.submit(conversationID: second, question: "另一个对话") { try await Task.sleep(for: .milliseconds(10)) })
        assert(center.isGenerating(first) && center.isGenerating(second) && background.live.count == 2)
        try await drained(center)
        assert(AIAnswerNotificationCenter.shared.completed.count == 2 && background.live.isEmpty)
        assert(background.starts == background.finishes)

        assert(center.submit(conversationID: first, question: "网络失败") { throw URLError(.networkConnectionLost) })
        try await drained(center)
        assert(center.statusMessage(for: first)?.hasPrefix("回答失败") == true)
        assert(AIAnswerNotificationCenter.shared.completed.count == 2)
        assert(center.submit(conversationID: first, question: "重新生成") {})
        try await drained(center)
        assert(center.statusMessage(for: first) == "回答已完成")

        assert(center.submit(conversationID: first, question: "主动停止") {
            do { try await Task.sleep(for: .seconds(10)) }
            catch { throw URLError(.cancelled) }
        })
        center.cancel(first)
        try await drained(center)
        assert(center.statusMessage(for: first) == "已停止生成" && !center.wasBackgroundInterrupted(first))

        assert(center.submit(conversationID: first, question: "后台时间用尽") { try await Task.sleep(for: .seconds(10)) })
        background.expire(first)
        try await drained(center)
        assert(center.wasBackgroundInterrupted(first))
        assert(center.statusMessage(for: first)?.contains("后台运行已中断") == true)
        assert(background.live.isEmpty)
        assert(center.submit(conversationID: first, question: "返回后重新生成") {})
        assert(!center.wasBackgroundInterrupted(first))
        try await drained(center)

        background.expireImmediately = true
        assert(center.submit(conversationID: second, question: "系统立即拒绝后台时间") {})
        try await drained(center)
        assert(center.wasBackgroundInterrupted(second))
        background.expireImmediately = false

        let completions = AIAnswerNotificationCenter.shared.completed.count
        assert(center.submit(conversationID: first, question: "底层忽略取消也不能通知成功") {
            try? await Task.sleep(for: .seconds(10))
        })
        center.cancel(first)
        try await drained(center)
        assert(AIAnswerNotificationCenter.shared.completed.count == completions)
        assert(background.starts == background.finishes && background.live.isEmpty)
        print("PASS: parallel conversations, duplicate guard, network retry, explicit stop, expiration, immediate expiration and balanced background assertions")
    }
}
