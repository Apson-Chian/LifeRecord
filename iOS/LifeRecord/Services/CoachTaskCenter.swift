import Foundation
import SwiftUI

/// 由 RootView 持有，用户离开教练页后，AI 请求仍继续执行。
@MainActor
final class CoachTaskCenter: ObservableObject {
    @Published private(set) var generatingConversationIDs: Set<UUID> = []
    @Published private(set) var activeQuestions: [UUID: String] = [:]
    @Published private(set) var statusMessages: [ID: String] = [:]

    typealias ID = UUID

    private var workTasks: [ID: Task<Void, Never>] = [:]
    private var expiredConversationIDs: Set<ID> = []
    private let background: any CoachBackgroundExecuting

    init(background: (any CoachBackgroundExecuting)? = nil) {
        self.background = background ?? CoachBackgroundExecution()
    }

    func wasBackgroundInterrupted(_ id: ID) -> Bool { expiredConversationIDs.contains(id) }

    private func expire(_ id: ID) {
        expiredConversationIDs.insert(id)
        workTasks[id]?.cancel()
        background.end(id)
    }

    var isGenerating: Bool {
        !generatingConversationIDs.isEmpty
    }

    func isGenerating(_ conversationID: ID) -> Bool {
        generatingConversationIDs.contains(conversationID)
    }

    func activeQuestion(for conversationID: ID) -> String? {
        activeQuestions[conversationID]
    }

    func statusMessage(for conversationID: ID) -> String? {
        statusMessages[conversationID]
    }

    @discardableResult
    func submit(
        conversationID: ID,
        question: String,
        operation: @escaping @MainActor () async throws -> Void
    ) -> Bool {
        guard workTasks[conversationID] == nil else { return false }

        expiredConversationIDs.remove(conversationID)
        generatingConversationIDs.insert(conversationID)
        activeQuestions[conversationID] = question
        statusMessages[conversationID] = nil

        workTasks[conversationID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
                try Task.checkCancellation()
                if statusMessages[conversationID] == nil {
                    statusMessages[conversationID] = "回答已完成"
                }
                AIAnswerNotificationCenter.shared.notifyAnswerReady(conversationID: conversationID)
            } catch {
                if expiredConversationIDs.contains(conversationID) {
                    statusMessages[conversationID] = "后台运行已中断，可重新生成"
                } else if Task.isCancelled || error is CancellationError {
                    statusMessages[conversationID] = "已停止生成"
                } else {
                    statusMessages[conversationID] = "回答失败：\(error.localizedDescription)"
                }
            }
            background.end(conversationID)

            generatingConversationIDs.remove(conversationID)
            activeQuestions[conversationID] = nil
            workTasks[conversationID] = nil
        }
        background.begin(conversationID) { [weak self] in self?.expire(conversationID) }
        return true
    }

    func cancel(_ conversationID: ID) {
        workTasks[conversationID]?.cancel()
    }
}
