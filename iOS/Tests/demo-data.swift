import Foundation
import SwiftData

@main
struct DemoDataTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: MealEntry.self, BodyMetric.self, WorkoutEntry.self, CoachConversation.self, CoachMessage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let suite = "LifeRecord.DemoTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 0, minute: 5))!
        let realMeal = MealEntry(kind: .lunch, name: "自己的午餐", calories: 400, protein: 20, carbs: 50, fat: 13)
        let realBody = BodyMetric(weight: 70)
        let realWorkout = WorkoutEntry(date: now.addingTimeInterval(-3600), endDate: now)
        let realChat = CoachConversation(title: "自己的对话")
        context.insert(realMeal); context.insert(realBody); context.insert(realWorkout); context.insert(realChat)
        try context.save()
        realMeal.note = "未保存的备注"
        assert(!DemoDataService.reinstall(context: context, now: now, preferences: preferences))
        assert(!DemoDataService.clear(context: context, preferences: preferences))
        assert(context.hasChanges && realMeal.note == "未保存的备注")
        try context.save()
        for _ in 0..<2 {
            assert(DemoDataService.reinstall(context: context, now: now, preferences: preferences))
            let meals = try context.fetch(FetchDescriptor<MealEntry>()).filter(\.isDemo)
            let body = try context.fetch(FetchDescriptor<BodyMetric>()).filter(\.isDemo)
            let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>()).filter(\.isDemo)
            let chats = try context.fetch(FetchDescriptor<CoachConversation>()).filter(\.isDemo)
            assert(meals.count == 106 && body.count == 28 && workouts.count == 20 && chats.count == 2)
            assert(Set(meals.map(\.kindRaw)).count == 4)
            assert(meals.allSatisfy { $0.date <= now && abs($0.calories - ($0.protein * 4 + $0.carbs * 4 + $0.fat * 9)) < 0.01 })
            assert(body.allSatisfy { $0.date <= now } && body.contains { $0.waist != nil } && body.contains { $0.bodyFat == nil })
            assert(workouts.allSatisfy { $0.date <= now && $0.endDate! <= now && $0.endDate! > $0.date && !$0.exercises.isEmpty })
            for workout in workouts { try WorkoutExercise.validate(workout.exercises) }
            let messageCount = try context.fetchCount(FetchDescriptor<CoachMessage>())
            assert(messageCount == 4)
            let snapshots = workouts.map { InsightRecords.Workout(id: $0.id, date: $0.date, endDate: $0.endDate, isDemo: $0.isDemo) }
            assert(RecordQuality.issues(meals: [], body: [], workouts: snapshots, now: now).isEmpty)
            let feedback = GoalFeedback.summarize(goals: .init(mode: .maintain, baselineWeight: 70, targetWeight: 70, weeklyWeightChange: 0, calories: 2000, protein: 100), meals: [], body: [], workouts: snapshots, days: 30, now: now)
            assert(feedback.completedWorkouts == 0)
        }
        assert(DemoDataService.clear(context: context, preferences: preferences))
        let remainingMealEntry = try context.fetch(FetchDescriptor<MealEntry>()).map(\.id)
        assert(remainingMealEntry == [realMeal.id])
        let remainingBodyMetric = try context.fetch(FetchDescriptor<BodyMetric>()).map(\.id)
        assert(remainingBodyMetric == [realBody.id])
        let remainingWorkoutEntry = try context.fetch(FetchDescriptor<WorkoutEntry>()).map(\.id)
        assert(remainingWorkoutEntry == [realWorkout.id])
        let remainingCoachConversation = try context.fetch(FetchDescriptor<CoachConversation>()).map(\.id)
        assert(remainingCoachConversation == [realChat.id])
        let remainingMessages = try context.fetchCount(FetchDescriptor<CoachMessage>())
        assert(remainingMessages == 0)
        assert(DemoDataService.clear(context: context, preferences: preferences))
        print("PASS: comprehensive examples, repeat install, no future data, real-data isolation and safe clear")
    }
}
