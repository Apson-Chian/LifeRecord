import Foundation
import SwiftData

@main
struct MealProvenanceTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meal-provenance-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("records.store")
        let input = "午餐一碗牛肉面，少油\n加一个蛋"
        let photoID = String(repeating: "a", count: 32)
        let conversationID = UUID().uuidString.lowercased()
        let recordID = UUID()
        do {
            let container = try ModelContainer(for: MealEntry.self, configurations: ModelConfiguration(url: database))
            let context = container.mainContext
            let meal = MealEntry(id: recordID, kind: .lunch, name: "牛肉面", calories: 650,
                                 protein: 30, carbs: 70, fat: 20, note: "AI 估算份量",
                                 source: .ai, photoIDs: [photoID], inputText: input,
                                 sourceConversationID: conversationID)
            context.insert(meal)
            context.insert(MealEntry(kind: .snack, name: "旧餐", calories: 100, protein: 5, carbs: 10, fat: 4))
            try context.save()
            // Editing the AI result must preserve the original user message and photos.
            meal.name = "牛肉面加蛋"
            meal.calories = 700
            meal.note = "复核后更正"
            meal.updatedAt = .now
            try context.save()
        }
        do {
            let reopened = try ModelContainer(for: MealEntry.self, configurations: ModelConfiguration(url: database))
            let meals = try reopened.mainContext.fetch(FetchDescriptor<MealEntry>())
            let meal = meals.first { $0.id == recordID }!
            assert(meals.count == 2 && meal.calories == 700 && meal.note == "复核后更正")
            assert(meal.inputText == input && meal.photoIDs == [photoID])
            assert(meal.sourceConversationID == conversationID)
            let legacy = meals.first { $0.name == "旧餐" }!
            assert(legacy.inputText.isEmpty && legacy.sourceConversationID.isEmpty)
        }
        print("PASS: original input and conversation persist across edits and store reopen; empty defaults remain compatible")
    }
}
