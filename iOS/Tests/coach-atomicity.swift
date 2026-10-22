import Foundation
import SwiftData

// Network and shared-profile effects are forbidden in this writer regression.
enum SharedProfileStore { @MainActor static func publish(_ settings: AppSettings) {}; static func clear() {} }
struct SyncedProfile: Codable {
    var id = "profile"
    var updatedAt: Double
    var displayName: String
    var fitnessGoal: String
    var height: Double
    var baselineWeight: Double
    var targetWeight: Double
    var weeklyWeightTarget: Double
    var calorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double
    var goalHistory: [GoalVersion]? = nil
    var goalTimeZone: String? = nil
}
@MainActor final class SyncCoordinator {
    func uploadMealPhotos(_ images:[Data],mealID:UUID) async throws->[String] { preconditionFailure("test network is forbidden") }
    func sync(context:ModelContext,settings:AppSettings) async {}
    func reportPhotoUploadFailure(_ error:Error) {}
}
@MainActor enum SyncDeletion {
    static func delete(_ meal:MealEntry,context:ModelContext) {context.insert(SyncTombstone(recordID:meal.id,recordType:"meal"));context.delete(meal)}
    static func delete(_ body:BodyMetric,context:ModelContext) {context.insert(SyncTombstone(recordID:body.id,recordType:"body"));context.delete(body)}
}
@main struct CoachAtomicityChecks {
    @MainActor static func main() async throws {
        let container=try ModelContainer(for:MealEntry.self,BodyMetric.self,WorkoutEntry.self,SyncTombstone.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let context=ModelContext(container);context.autosaveEnabled=false
        let suite="liferecord-coach-atomic-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let settings=AppSettings(defaults:defaults)
        let writer=CoachWriterProbe(context:context,settings:settings,defaults:defaults)
        let draft=MealEntry(kind:.lunch,name:"draft",calories:600,protein:30,carbs:70,fat:20)
        context.insert(draft);try context.save();draft.note="unrelated unsaved draft"
        let actions=try JSONDecoder().decode([AIAgentAction].self,from:Data(#"[{"type":"update_goals","calorieGoal":2300},{"type":"add_exercise_template","name":"synthetic curl","bodyPart":"二头"},{"type":"add_meal","name":"synthetic meal","calories":500,"protein":20,"carbs":60,"fat":15,"fiber":5}]"#.utf8))
        let before=defaults.dictionaryRepresentation() as NSDictionary
        do {try await writer.run(actions);preconditionFailure("injected save failure did not fail")} catch {}
        precondition(before==defaults.dictionaryRepresentation() as NSDictionary,"failed AI batch changed profile/library preferences")
        precondition(settings.calorieGoal==2000)
        let callerRecords = try context.fetch(FetchDescriptor<MealEntry>())
        precondition(callerRecords.count==1,"AI batch leaked changes to caller context")
        precondition(draft.note=="unrelated unsaved draft" && context.hasChanges)
        writer.shouldFail=false
        try await writer.run(actions)
        let verified=try ModelContext(container).fetch(FetchDescriptor<MealEntry>())
        precondition(verified.count==2 && settings.calorieGoal==2300)
        precondition(ExerciseLibrary.decode(defaults.string(forKey:ExerciseLibrary.key) ?? "[]").contains {$0.name=="synthetic curl"})
        precondition(verified.first {$0.id==draft.id}!.note != "unrelated unsaved draft")
        precondition(draft.note=="unrelated unsaved draft" && context.hasChanges)
        print("PASS: actual AI writer save failure preserves models, profile, library and unrelated draft; success commits staged changes")
    }
}
