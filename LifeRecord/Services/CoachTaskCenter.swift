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

        generatingConversationIDs.insert(conversationID)
        activeQuestions[conversationID] = question
        statusMessages[conversationID] = nil

        workTasks[conversationID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
                if statusMessages[conversationID] == nil {
                    statusMessages[conversationID] = "回答已完成"
                }
            } catch is CancellationError {
                statusMessages[conversationID] = "已停止生成"
            } catch {
                statusMessages[conversationID] = "回答失败：\(error.localizedDescription)"
            }

            generatingConversationIDs.remove(conversationID)
            activeQuestions[conversationID] = nil
            workTasks[conversationID] = nil
        }
        return true
    }

    func cancel(_ conversationID: ID) {
        workTasks[conversationID]?.cancel()
    }
}
