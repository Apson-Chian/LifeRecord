import Foundation
import SwiftData

@main
struct CoachMealActionChecks {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coach-actions-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("records.store")
        let input = "午餐吃了一碗牛肉面和一个鸡蛋，帮我添加到餐食里"
        let conversationID = UUID()
        let date = ISO8601DateFormatter().date(from: "2026-10-15T12:30:00+08:00")!
        // Simulate the model's structured reply, then use the app's meal conversion and storage path.
        let data = Data(#"{"answer":"按一碗牛肉面和一个鸡蛋估算营养。","actions":[{"type":"add_meal","mealKind":"午餐","name":"牛肉面加鸡蛋","calories":720,"protein":35,"carbs":80,"fat":28,"fiber":4,"date":"2026-10-15T12:30:00+08:00","source":"AI 估算","note":"按常见一碗估算，实际份量和用油存在差异"}]}"#.utf8)
        let reply = try JSONDecoder().decode(AIAgentReply.self, from: data)
        precondition(reply.actions.count == 1)
        let recordID: UUID
        do {
            let container = try ModelContainer(for: MealEntry.self, configurations: ModelConfiguration(url: database))
            let context = container.mainContext
            let blocked = CoachActionPolicy.blockedMessage(for: reply, writesAllowed: false, request: input)
            precondition(blocked?.hasPrefix("未保存") == true)
            if blocked == nil { preconditionFailure("Read-only requests must not reach the writer") }
            let emptyCount = try context.fetchCount(FetchDescriptor<MealEntry>())
            precondition(emptyCount == 0)
            precondition(CoachActionPolicy.blockedMessage(for: reply, writesAllowed: true, request: input) == nil)
            let meal = CoachMealRecorder.makeMeal(from: reply.actions[0], date: date,
                                                  inputText: input, conversationID: conversationID)!
            recordID = meal.id
            context.insert(meal)
            try context.save()
        }
        do {
            let reopened = try ModelContainer(for: MealEntry.self, configurations: ModelConfiguration(url: database))
            let meals = try reopened.mainContext.fetch(FetchDescriptor<MealEntry>())
            precondition(meals.count == 1)
            let meal = meals[0]
            precondition(meal.id == recordID && meal.kind == .lunch && meal.date == date)
            precondition(meal.name == "牛肉面加鸡蛋" && meal.calories == 720)
            precondition(meal.protein == 35 && meal.carbs == 80 && meal.fat == 28 && meal.fiber == 4)
            precondition(meal.source == .ai && meal.note.contains("估算"))
            precondition(meal.inputText == input && meal.sourceConversationID == conversationID.uuidString.lowercased())
        }
        // A natural-language success claim with no action can never bypass the permission gate.
        let empty = try JSONDecoder().decode(AIAgentReply.self, from: Data(#"{"answer":"已添加到餐食"}"#.utf8))
        precondition(empty.actions.isEmpty)
        precondition(CoachActionPolicy.blockedMessage(for: empty, writesAllowed: false, request: input) != nil)
        for request in ["帮我添加到餐食", "记录一下", "帮我记到今天午餐", "请保存这餐"] {
            precondition(CoachActionPolicy.isMutationRequest(request))
        }
        let question = AIAgentReply(answer: "一个鸡蛋约有 70 kcal")
        precondition(CoachActionPolicy.blockedMessage(for: question, writesAllowed: false, request: "鸡蛋有多少热量？") == nil)
        var invalid = reply.actions[0]
        invalid.calories = nil
        precondition(CoachMealRecorder.makeMeal(from: invalid, date: date, inputText: input, conversationID: conversationID) == nil)
        invalid = reply.actions[0]; invalid.protein = -1
        precondition(CoachMealRecorder.makeMeal(from: invalid, date: date, inputText: input, conversationID: conversationID) == nil)
        invalid = reply.actions[0]; invalid.mealKind = "未知餐次"
        precondition(CoachMealRecorder.makeMeal(from: invalid, date: date, inputText: input, conversationID: conversationID) == nil)
        print("PASS: coach meal action persists across reopen; read-only and invalid actions never reach storage")
    }
}
