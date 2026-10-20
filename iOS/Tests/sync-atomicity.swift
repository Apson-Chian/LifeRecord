import Foundation
import SwiftData

// No user credentials, network calls, app group writes or standard defaults.
enum KeychainStore { static var hasSyncKey: Bool { false }; static func loadSyncKey() -> String { "" } }
enum PrivateHTTPSession { static let session = URLSession(configuration: .ephemeral) }
enum SharedProfileStore { @MainActor static func publish(_ settings: AppSettings) {}; static func clear() {} }

@main struct SyncAtomicityChecks {
    @MainActor static func main() async throws {
        let container = try ModelContainer(for: MealEntry.self, BodyMetric.self, WorkoutEntry.self, SyncTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context=ModelContext(container); context.autosaveEnabled=false
        let suite="liferecord-atomic-test-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let settings=AppSettings(defaults:defaults), sync=SyncCoordinator()
        let draft=MealEntry(kind:.lunch,name:"persisted",calories:500,protein:20,carbs:70,fat:15)
        context.insert(draft);try context.save()
        draft.name="unrelated unsaved draft"
        let meal:[String:Any]=["id":UUID().uuidString.lowercased(),"date":1000.0,"kind":"午餐","name":"remote", "calories":600.0,"protein":30.0,"carbs":70.0,"fat":20.0,"fiber":5.0,"note":"","source":"手动","createdAt":1000.0,"updatedAt":1200.0]
        let invalidWorkout:[String:Any]=["id":UUID().uuidString.lowercased(),"date":1000.0,"updatedAt":1200.0,"note":"","bodyParts":["胸部","胸部"]]
        let invalid:[String:Any]=["meals":[meal],"bodyMetrics":[],"workoutEntries":[invalidWorkout],"deletions":[]]
        let preferences=defaults.dictionaryRepresentation() as NSDictionary
        do {try sync.testApply(JSONSerialization.data(withJSONObject:invalid),context:context,settings:settings);preconditionFailure("invalid batch accepted")}
        catch { }
        let after=try context.fetch(FetchDescriptor<MealEntry>())
        precondition(after.count==1,"failed sync leaked a meal into the caller context")
        precondition(draft.name=="unrelated unsaved draft" && context.hasChanges,"failed sync discarded an unrelated draft")
        precondition(preferences == defaults.dictionaryRepresentation() as NSDictionary)
        try context.save()
        let verify=ModelContext(container)
        precondition(tryCount(verify)==1,"later normal save persisted a partial sync")
        var valid=invalid; valid["workoutEntries"] = [[String: Any]]()
        var profile = settings.profileDraft(); profile.calorieGoal=2300
        valid["settings"] = ["id":"profile","updatedAt":Date.now.timeIntervalSince1970+60,"displayName":"new", "fitnessGoal":"维持", "height":170,"baselineWeight":70,"targetWeight":70,"weeklyWeightTarget":0,"calorieGoal":2300,"proteinGoal":100,"carbsGoal":250,"fatGoal":60]
        let validData=try JSONSerialization.data(withJSONObject:valid)
        let beforeFailure=defaults.dictionaryRepresentation() as NSDictionary
        do { try sync.testApply(validData,context:context,settings:settings,failCommit:true); preconditionFailure("injected failure did not fail") } catch { }
        precondition(tryCount(ModelContext(container))==1)
        precondition(beforeFailure == defaults.dictionaryRepresentation() as NSDictionary)
        draft.note="second unrelated draft"
        let cancelled=Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try sync.testApply(validData,context:context,settings:settings)
        }
        do { try await cancelled.value; preconditionFailure("cancelled transaction committed") } catch { }
        precondition(tryCount(ModelContext(container))==1)
        precondition(draft.note=="second unrelated draft" && context.hasChanges)
        precondition(beforeFailure == defaults.dictionaryRepresentation() as NSDictionary)
        try sync.testApply(validData,context:context,settings:settings)
        precondition(tryCount(ModelContext(container))==2 && settings.calorieGoal==2300)
        precondition(draft.note=="second unrelated draft" && context.hasChanges)
        let persistedDraft=try ModelContext(container).fetch(FetchDescriptor<MealEntry>()).first {$0.id==draft.id}!
        precondition(persistedDraft.note != "second unrelated draft", "sync committed caller draft")
        let example = WorkoutEntry(date: .now.addingTimeInterval(-3600), endDate: .now, isDemo: true)
        context.insert(example)
        try context.save()
        let snapshot = try sync.testSnapshot(context: context, settings: settings)
        precondition(snapshot.workoutEntries?.contains { $0.id == example.id.uuidString.lowercased() } == false,
                     "example workout leaked into sync")
        print("PASS: example workouts stay out of actual sync snapshots")
        print("PASS: rejected sync changes neither records nor preferences and preserves unrelated drafts")
    }
    @MainActor static func tryCount(_ context:ModelContext)->Int { try! context.fetchCount(FetchDescriptor<MealEntry>()) }
}
