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
    var goalHistory: [GoalVersion]? = nil
    var goalTimeZone: String? = nil
}


@main struct SettingsPrivacyChecks {
    @MainActor static func main() throws {
        let suite="liferecord-settings-test-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer {defaults.removePersistentDomain(forName:suite)}
        let settings=AppSettings(defaults:defaults)
        precondition(settings.provider == .builtin)
        precondition(settings.height==170 && settings.baselineWeight==70 && settings.targetWeight==70)
        precondition(settings.fitnessGoal == .maintain && !settings.aiCanWrite && !settings.shareWithLifeTrack)
        precondition(settings.profileUpdatedAt.timeIntervalSince1970==1)
        precondition(settings.coachName == AppSettings.defaultCoachName && settings.coachAvatarData == nil)
        let avatar = Data([0x01, 0x02, 0x03])
        try settings.updateCoachIdentity(name: "  小满教练  ", avatarData: avatar)
        let coachRestored = AppSettings(defaults: defaults)
        precondition(coachRestored.coachName == "小满教练" && coachRestored.coachAvatarData == avatar)
        for (invalidName, invalidAvatar) in [("  ", avatar), (String(repeating: "长", count: 31), avatar), ("错误\n名称", avatar), ("新名称", Data(repeating: 0, count: 512_001))] {
            do {
                try settings.updateCoachIdentity(name: invalidName, avatarData: invalidAvatar)
                preconditionFailure("Invalid coach identity should not save")
            } catch { }
            precondition(settings.coachName == "小满教练" && settings.coachAvatarData == avatar)
        }
        // Invalid goal drafts must leave the entire preference domain untouched.
        let beforeDraft = defaults.dictionaryRepresentation() as NSDictionary
        var profileDraft = settings.profileDraft()
        profileDraft.calorieGoal = 100
        do { try settings.saveProfileDraft(profileDraft); preconditionFailure("invalid goal saved") } catch { }
        precondition(beforeDraft == defaults.dictionaryRepresentation() as NSDictionary)
        profileDraft = settings.profileDraft(); profileDraft.height = 70; profileDraft.weeklyWeightTarget = -3
        try settings.saveProfileDraft(profileDraft)
        precondition(settings.height == 70 && settings.weeklyWeightTarget == -3)
        let staleDraft = settings.profileDraft()
        settings.targetWeight = 71
        do { try settings.saveProfileDraft(staleDraft); preconditionFailure("stale draft saved") } catch { }
        precondition(settings.targetWeight == 71)
        let historyBefore=settings.goalHistory
        let yesterday=Calendar.current.date(byAdding:.day,value:-1,to:Date.now)!
        let yesterdayGoal=settings.goals(on:yesterday)
        var changedGoals=settings.profileDraft();changedGoals.proteinGoal=175
        try settings.saveProfileDraft(changedGoals)
        precondition(settings.goals(on:yesterday)==yesterdayGoal)
        precondition(settings.goals(on:Date.now).proteinGoal==175)
        precondition(AppSettings(defaults:defaults).goalHistory==settings.goalHistory)
        precondition(settings.goalHistory.count==historyBefore.count)
        // Draft editing happens in the view; only an explicit save changes the persisted identity.
        try settings.updateCoachIdentity(name: "小满教练", avatarData: nil)
        precondition(AppSettings(defaults: defaults).coachAvatarData == nil)
        settings.provider = .custom
        settings.endpoint="https://gateway.test/v1/chat/completions";settings.model="private-model"
        settings.extraBody="{\"top_p\":0.8}";settings.tokenParameter="max_completion_tokens";settings.jsonMode=false;settings.sendTemperature=false
        settings.provider = .glm;settings.provider = .custom
        precondition(settings.endpoint=="https://gateway.test/v1/chat/completions" && settings.model=="private-model")
        precondition(settings.tokenParameter=="max_completion_tokens" && !settings.jsonMode && !settings.sendTemperature)
        precondition(!AIProvider.allCases.contains(.dots))
        let first=try! settings.saveAPIProfile(name:"接口 A")
        settings.endpoint="https://second.test/v1/chat/completions";settings.model="second-model";settings.imageDetail="medium"
        let second=try! settings.saveAPIProfile(name:"接口 B")
        settings.loadAPIProfile(first);precondition(settings.model=="private-model" && settings.savedAPIProfiles.count==2)
        settings.model="updated-model";_ = try! settings.saveAPIProfile(name:"接口 A 更新",updating:first)
        let reopened=AppSettings(defaults:defaults);reopened.loadAPIProfile(first);precondition(reopened.model=="updated-model")
        reopened.loadAPIProfile(second);precondition(reopened.imageDetail=="medium" && reopened.model=="second-model")
        precondition(reopened.coachName == "小满教练")
        settings.deleteAPIProfile(second);precondition(settings.savedAPIProfiles.count==1)
        settings.displayName="private name";settings.customInstructions="private preference";settings.height=188
        defaults.set("https://legacy.test/v1/chat/completions",forKey:"ai.migratedLegacyEndpoint")
        precondition(defaults.string(forKey:"displayName")=="private name")
        try settings.updateCoachIdentity(name: "私人教练", avatarData: avatar)
        settings.resetAfterLocalDeletion()
        precondition(settings.displayName.isEmpty && settings.customInstructions.isEmpty && settings.height==170)
        precondition(settings.profileUpdatedAt.timeIntervalSince1970==1 && !settings.aiCanWrite && !settings.shareWithLifeTrack)
        precondition(!defaults.dictionaryRepresentation().keys.contains(where:{$0.hasPrefix("ai.profile.")}))
        precondition(settings.savedAPIProfiles.isEmpty)
        precondition(defaults.string(forKey:"ai.migratedLegacyEndpoint")==nil)
        precondition(settings.coachName == AppSettings.defaultCoachName && settings.coachAvatarData == nil)
        let resetCoach = AppSettings(defaults: defaults)
        precondition(resetCoach.coachName == AppSettings.defaultCoachName && resetCoach.coachAvatarData == nil)
        let imported=SyncedProfile(updatedAt:Date.now.addingTimeInterval(-86400).timeIntervalSince1970,
            displayName:"同步测试",fitnessGoal:"维持",height:170,baselineWeight:70,targetWeight:70,
            weeklyWeightTarget:0,calorieGoal:2000,proteinGoal:180,carbsGoal:250,fatGoal:60)
        settings.applySyncedProfile(imported,updatedAt:Date(timeIntervalSince1970:imported.updatedAt))
        precondition(settings.goalHistory.isEmpty, "First sync must not invent history from neutral install defaults")
        precondition(settings.goals(on:yesterday).proteinGoal==180)
        var importedDraft=settings.profileDraft();importedDraft.proteinGoal=200
        try settings.saveProfileDraft(importedDraft)
        precondition(settings.goalHistory.first?.values.proteinGoal==180)
        precondition(settings.goals(on:yesterday).proteinGoal==180)
        let currentVersion=GoalHistory.active(settings.goalHistory).last!
        var revisedValues=currentVersion.values;revisedValues.proteinGoal=190
        try settings.reviseGoal(currentVersion,values:revisedValues,day:GoalHistory.dayKey(Date.now))
        precondition(settings.proteinGoal==190 && settings.goals(on:yesterday).proteinGoal==180)
        precondition(AppSettings(defaults:defaults).goalHistory==settings.goalHistory)
        do {try settings.reviseGoal(currentVersion,values:revisedValues,day:GoalHistory.dayKey(Date.now));preconditionFailure("stale target edit accepted")} catch {}
        var afterCorrection=settings.profileDraft();afterCorrection.displayName="纠错后立即保存"
        try settings.saveProfileDraft(afterCorrection)
        precondition(settings.displayName=="纠错后立即保存" && settings.proteinGoal==190)
        let currentAfter=GoalHistory.active(settings.goalHistory).last!
        revisedValues.proteinGoal=0
        let beforeInvalid=defaults.dictionaryRepresentation() as NSDictionary
        do {try settings.reviseGoal(currentAfter,values:revisedValues,day:currentAfter.effectiveDate);preconditionFailure("invalid target edit accepted")} catch {}
        precondition(beforeInvalid==defaults.dictionaryRepresentation() as NSDictionary)
        defaults.set("Dots",forKey:"provider");defaults.set("https://legacy.test/v1/chat/completions",forKey:"endpoint");defaults.set("dots3-note-prev",forKey:"model")
        let migrated=AppSettings(defaults:defaults);precondition(migrated.provider == .custom && migrated.authStyle == .apiKey && !migrated.jsonMode && migrated.imageDetail=="medium")
        print("PASS: neutral defaults, opt-in sharing/writes, provider settings restore, isolated preferences, private settings reset")
    }
}
