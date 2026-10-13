import Foundation
// Isolated collaborators prevent a settings test from publishing private App Group data.
enum SharedProfileStore {
    @MainActor static func publish(_ settings: AppSettings) {}
    static func clear() {}
}
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
}


@main struct SettingsPrivacyChecks {
    @MainActor static func main() {
        let suite="liferecord-settings-test-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let settings=AppSettings(defaults:defaults)
        precondition(settings.height==170 && settings.baselineWeight==70 && settings.targetWeight==70)
        precondition(settings.fitnessGoal == .maintain && !settings.aiCanWrite && !settings.shareWithLifeTrack)
        precondition(settings.profileUpdatedAt.timeIntervalSince1970==1)
        settings.provider = .custom
        settings.endpoint="https://gateway.test/v1/chat/completions";settings.model="private-model"
        settings.extraBody="{\"top_p\":0.8}";settings.tokenParameter="max_completion_tokens";settings.jsonMode=false;settings.sendTemperature=false
        settings.provider = .glm;settings.provider = .custom
        precondition(settings.endpoint=="https://gateway.test/v1/chat/completions" && settings.model=="private-model")
        precondition(settings.tokenParameter=="max_completion_tokens" && !settings.jsonMode && !settings.sendTemperature)
        settings.displayName="private name";settings.customInstructions="private preference";settings.height=188
        precondition(defaults.string(forKey:"displayName")=="private name")
        settings.resetAfterLocalDeletion()
        precondition(settings.displayName.isEmpty && settings.customInstructions.isEmpty && settings.height==170)
        precondition(settings.profileUpdatedAt.timeIntervalSince1970==1 && !settings.aiCanWrite && !settings.shareWithLifeTrack)
        precondition(!defaults.dictionaryRepresentation().keys.contains(where:{$0.hasPrefix("ai.profile.")}))
        print("PASS: neutral defaults, opt-in sharing/writes, provider settings restore, isolated preferences, private settings reset")
    }
}
