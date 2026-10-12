import Foundation
import SwiftData

@main
struct WorkoutStorageTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: WorkoutEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let entry = WorkoutEntry(note: "旧版训练")
        context.insert(entry)
        try context.save()
        assert(entry.exercises.isEmpty)
        entry.exercises = [.init(name: "自定义划船", sets: [.init(reps: 10, weight: 35), .init(reps: 8, weight: 40)])]
        try context.save()
        let reader = ModelContext(container)
        let loaded = try reader.fetch(FetchDescriptor<WorkoutEntry>()).first!
        assert(loaded.exercises[0].sets[1].weight == 40)
        assert(loaded.contentSummary.contains("旧版训练") && loaded.contentSummary.contains("自定义划船"))
        loaded.bodyParts = ["背部", "核心"]
        try reader.save()
        let repairContext = ModelContext(container)
        let reread = try repairContext.fetch(FetchDescriptor<WorkoutEntry>()).first!
        assert(reread.bodyParts == ["背部", "核心"])
        assert(reread.overviewSummary.contains("背部 · 核心"))
        reread.bodyParts = ["胸部", "手臂"]
        reread.note = "卧推、二头和三头"
        try repairContext.save()
        let originalID = reread.id, originalDate = reread.date, originalEnd = reread.endDate
        let originalExercises = reread.exercisesRaw, originalNote = reread.note
        reread.bodyParts = WorkoutBodyParts.refineArms(reread.bodyParts, describedBy: reread.note)
        reread.updatedAt = .now
        try repairContext.save()
        let repaired = try ModelContext(container).fetch(FetchDescriptor<WorkoutEntry>()).first!
        assert(repaired.bodyParts == ["胸部", "二头", "三头"])
        assert(repaired.id == originalID && repaired.date == originalDate && repaired.endDate == originalEnd)
        assert(repaired.note == originalNote && repaired.exercisesRaw == originalExercises)
        let count = try reader.fetchCount(FetchDescriptor<WorkoutEntry>())
        assert(count == 1)
        print("PASS: SwiftData default, save and independent-context structured workout read")
    }
}
