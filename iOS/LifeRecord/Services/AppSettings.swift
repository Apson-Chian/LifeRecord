import Foundation
import Observation

enum FitnessGoal: String, CaseIterable, Identifiable {
    case gainMuscle = "增肌"
    case loseFat = "减脂"
    case maintain = "维持"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .gainMuscle: "figure.strengthtraining.traditional"
        case .loseFat: "flame"
        case .maintain: "equal.circle"
        }
    }
    var headline: String {
        switch self {
        case .gainMuscle: "稳定盈余，长肌肉而不是追体重"
        case .loseFat: "保住力量，温和降低体脂"
        case .maintain: "让训练、饮食与恢复保持平衡"
        }
    }
}

enum AIAuthStyle: String, CaseIterable, Identifiable {
    case bearer = "Bearer Token"
    case apiKey = "api-key 请求头"
    case custom = "自定义请求头"
    var id: String { rawValue }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case builtin = "默认 AI 服务"
    case deepSeek = "DeepSeek"
    case dots = "Dots"
    case glm = "智谱 GLM"
    case custom = "自定义"

    static var allCases: [AIProvider] { [.builtin, .deepSeek, .glm, .custom] }
    var id: String { rawValue }

    var keychainID: String {
        switch self {
        case .builtin: "default"
        case .deepSeek: "deepseek"
        case .dots: "dots"
        case .glm: "glm"
        case .custom: "custom"
        }
    }

    var endpoint: String {
        switch self {
        case .builtin: ""
        case .deepSeek: "https://api.deepseek.com/chat/completions"
        case .dots: ""
        case .glm: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .custom: "https://example.com/v1/chat/completions"
        }
    }

    var model: String {
        switch self {
        case .builtin: ""
        case .deepSeek: "deepseek-flash"
        case .dots: ""
        case .glm: "glm-4.6v-flash"
        case .custom: "vision-model-name"
        }
    }

    var authStyle: AIAuthStyle { self == .dots ? .apiKey : .bearer }
    var supportsVisionByDefault: Bool { true }
}

struct SavedAPIProfile: Codable, Identifiable {
    var id: String
    var name: String
    var values: [String: String]
}

@MainActor
@Observable
final class AppSettings {
    static let defaultCoachName = "AI 助手"
    private let defaults: UserDefaults
    private enum Key {
        static let calorieGoal = "calorieGoal"
        static let proteinGoal = "proteinGoal"
        static let carbsGoal = "carbsGoal"
        static let fatGoal = "fatGoal"
        static let targetWeight = "targetWeight"
        static let height = "height"
        static let baselineWeight = "baselineWeight"
        static let weeklyWeightTarget = "weeklyWeightTarget"
        static let fitnessGoal = "fitnessGoal"
        static let displayName = "displayName"
        static let provider = "provider"
        static let endpoint = "endpoint"
        static let model = "model"
        static let authStyle = "authStyle"
        static let customHeaderName = "customHeaderName"
        static let supportsVision = "supportsVision"
        static let maxPhotos = "maxPhotos"
        static let temperature = "temperature"
        static let maxTokens = "maxTokens"
        static let customInstructions = "customInstructions"
        static let aiCanWrite = "aiCanWrite"
        static let coachName = "coach.name"
        static let coachAvatar = "coach.avatar"
        static let profileUpdatedAt = "sync.profileUpdatedAt"
    }

    var calorieGoal: Double { didSet { save(calorieGoal, Key.calorieGoal); publishSharedProfile(); markProfileChanged() } }
    var proteinGoal: Double { didSet { save(proteinGoal, Key.proteinGoal); publishSharedProfile(); markProfileChanged() } }
    var carbsGoal: Double { didSet { save(carbsGoal, Key.carbsGoal); publishSharedProfile(); markProfileChanged() } }
    var fatGoal: Double { didSet { save(fatGoal, Key.fatGoal); publishSharedProfile(); markProfileChanged() } }
    var targetWeight: Double { didSet { save(targetWeight, Key.targetWeight); publishSharedProfile(); markProfileChanged() } }
    var height: Double { didSet { save(height, Key.height); publishSharedProfile(); markProfileChanged() } }
    var baselineWeight: Double { didSet { save(baselineWeight, Key.baselineWeight); publishSharedProfile(); markProfileChanged() } }
    var weeklyWeightTarget: Double { didSet { save(weeklyWeightTarget, Key.weeklyWeightTarget); markProfileChanged() } }
    var fitnessGoal: FitnessGoal { didSet { save(fitnessGoal.rawValue, Key.fitnessGoal); publishSharedProfile(); markProfileChanged() } }
    var displayName: String { didSet { save(displayName, Key.displayName); markProfileChanged() } }
    private(set) var profileUpdatedAt: Date
    private var isApplyingSyncedProfile = false
    var provider: AIProvider {
        didSet {
            save(provider.rawValue, Key.provider)
            guard provider != oldValue else { return }
            let previous: [String: Any] = ["endpoint":endpoint,"model":model,"auth":authStyle.rawValue,"header":customHeaderName,"vision":supportsVision,"extra":extraBody,"tokens":maxTokens,"parameter":tokenParameter,"json":jsonMode,"temperatureEnabled":sendTemperature,"imageDetail":imageDetail,"temperature":temperature]
            defaults.set(previous, forKey: "ai.profile.\(oldValue.keychainID)")
            let saved = defaults.dictionary(forKey: "ai.profile.\(provider.keychainID)") ?? [:]
            endpoint = saved["endpoint"] as? String ?? provider.endpoint
            model = saved["model"] as? String ?? provider.model
            authStyle = AIAuthStyle(rawValue: saved["auth"] as? String ?? "") ?? provider.authStyle
            customHeaderName = saved["header"] as? String ?? "Authorization"
            supportsVision = saved["vision"] as? Bool ?? provider.supportsVisionByDefault
            extraBody = saved["extra"] as? String ?? "{}"
            maxTokens = saved["tokens"] as? Int ?? 4096
            tokenParameter = saved["parameter"] as? String ?? "max_tokens"
            jsonMode = saved["json"] as? Bool ?? true
            sendTemperature = saved["temperatureEnabled"] as? Bool ?? true
            imageDetail = saved["imageDetail"] as? String ?? ""
            temperature = saved["temperature"] as? Double ?? 0.2
        }
    }
    var endpoint: String { didSet { save(endpoint, Key.endpoint) } }
    var model: String { didSet { save(model, Key.model) } }
    var authStyle: AIAuthStyle { didSet { save(authStyle.rawValue, Key.authStyle) } }
    var customHeaderName: String { didSet { save(customHeaderName, Key.customHeaderName) } }
    var supportsVision: Bool { didSet { save(supportsVision, Key.supportsVision) } }
    var maxPhotos: Int { didSet { save(maxPhotos, Key.maxPhotos) } }
    var temperature: Double { didSet { save(temperature, Key.temperature) } }
    var maxTokens: Int { didSet { save(maxTokens, Key.maxTokens) } }
    var customInstructions: String { didSet { save(customInstructions, Key.customInstructions) } }
    var aiCanWrite: Bool { didSet { save(aiCanWrite, Key.aiCanWrite) } }
    private(set) var coachName: String { didSet { save(coachName, Key.coachName) } }
    private(set) var coachAvatarData: Data? { didSet { defaults.set(coachAvatarData, forKey: Key.coachAvatar) } }

    func updateCoachIdentity(name: String, avatarData: Data?) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 30,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw NSError(domain: "CoachSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "请填写 1–30 个字的教练名称，不包含换行。"])
        }
        guard (avatarData?.count ?? 0) <= 512_000 else {
            throw NSError(domain: "CoachSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "头像过大，请重新选择照片。"])
        }
        coachName = trimmed
        coachAvatarData = avatarData
    }

    var appearance: String { didSet { save(appearance, "appearance") } }
    var accentColor: String { didSet { save(accentColor, "accentColor") } }
    var syncBaseURL: String { didSet { save(syncBaseURL, "sync.base") } }
    var shareWithLifeTrack: Bool { didSet { save(shareWithLifeTrack, "shareWithLifeTrack"); if !shareWithLifeTrack { SharedProfileStore.clear() } else { publishSharedProfile() } } }
    var tokenParameter: String { didSet { save(tokenParameter, "ai.tokenParameter") } }
    var jsonMode: Bool { didSet { save(jsonMode, "ai.jsonMode") } }
    var sendTemperature: Bool { didSet { save(sendTemperature, "ai.sendTemperature") } }
    var extraBody: String { didSet { save(extraBody, "ai.extraBody") } }
    var imageDetail: String { didSet { save(imageDetail, "ai.imageDetail") } }
    var savedAPIProfiles: [SavedAPIProfile] {
        didSet { if let data = try? JSONEncoder().encode(savedAPIProfiles) { defaults.set(data, forKey: "ai.savedProfiles") } }
    }

    func saveAPIProfile(name: String, updating id: String? = nil) throws -> String {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty && title.count <= 60 else { throw NSError(domain: "APISettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "请填写 1–60 字的配置名称"]) }
        guard id != nil || savedAPIProfiles.count < 30 else { throw NSError(domain: "APISettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "最多保存 30 个接口配置"]) }
        let profile = SavedAPIProfile(id: id ?? UUID().uuidString, name: title, values: [
            "provider": provider.rawValue, "endpoint": endpoint, "model": model, "auth": authStyle.rawValue,
            "header": customHeaderName, "vision": String(supportsVision), "photos": String(maxPhotos),
            "tokens": String(maxTokens), "temperature": String(temperature), "parameter": tokenParameter,
            "json": String(jsonMode), "temperatureEnabled": String(sendTemperature), "extra": extraBody, "imageDetail": imageDetail
        ])
        if let id, let index = savedAPIProfiles.firstIndex(where: { $0.id == id }) { savedAPIProfiles[index] = profile }
        else { savedAPIProfiles.append(profile) }
        return profile.id
    }

    func loadAPIProfile(_ id: String) {
        guard let p = savedAPIProfiles.first(where: { $0.id == id })?.values else { return }
        provider = AIProvider(rawValue: p["provider"] ?? "") ?? .custom
        endpoint=p["endpoint"] ?? ""; model=p["model"] ?? ""
        authStyle=AIAuthStyle(rawValue:p["auth"] ?? "") ?? .bearer; customHeaderName=p["header"] ?? "Authorization"
        supportsVision=p["vision"] == "true"; maxPhotos=Int(p["photos"] ?? "") ?? 6
        maxTokens=Int(p["tokens"] ?? "") ?? 4096; temperature=Double(p["temperature"] ?? "") ?? 0.2
        tokenParameter=p["parameter"] ?? "max_tokens"; jsonMode=p["json"] == "true"
        sendTemperature=p["temperatureEnabled"] == "true"; extraBody=p["extra"] ?? "{}"; imageDetail=p["imageDetail"] ?? ""
    }

    func deleteAPIProfile(_ id: String) { savedAPIProfiles.removeAll { $0.id == id } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedCoachName = defaults.string(forKey: Key.coachName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        coachName = savedCoachName.isEmpty ? Self.defaultCoachName : savedCoachName
        coachAvatarData = defaults.data(forKey: Key.coachAvatar)
        savedAPIProfiles = defaults.data(forKey:"ai.savedProfiles").flatMap { try? JSONDecoder().decode([SavedAPIProfile].self, from:$0) } ?? []
        imageDetail = defaults.string(forKey:"ai.imageDetail") ?? ""
        appearance = defaults.string(forKey: "appearance") ?? "system"
        accentColor = defaults.string(forKey: "accentColor") ?? "purple"
        syncBaseURL = defaults.string(forKey: "sync.base") ?? "https://apsonchian.ltd/liferecord-api"
        shareWithLifeTrack = defaults.bool(forKey: "shareWithLifeTrack")
        tokenParameter = defaults.string(forKey: "ai.tokenParameter") ?? "max_tokens"
        jsonMode = defaults.object(forKey: "ai.jsonMode") as? Bool ?? true
        sendTemperature = defaults.object(forKey: "ai.sendTemperature") as? Bool ?? true
        extraBody = defaults.string(forKey: "ai.extraBody") ?? "{}"
        // Neutral placeholders; users should fill their own measurements and goals.
        calorieGoal = defaults.object(forKey: Key.calorieGoal) as? Double ?? 2000
        proteinGoal = defaults.object(forKey: Key.proteinGoal) as? Double ?? 100
        carbsGoal = defaults.object(forKey: Key.carbsGoal) as? Double ?? 250
        fatGoal = defaults.object(forKey: Key.fatGoal) as? Double ?? 60
        targetWeight = defaults.object(forKey: Key.targetWeight) as? Double ?? 70
        height = defaults.object(forKey: Key.height) as? Double ?? 170
        baselineWeight = defaults.object(forKey: Key.baselineWeight) as? Double ?? 70
        weeklyWeightTarget = defaults.object(forKey: Key.weeklyWeightTarget) as? Double ?? 0
        fitnessGoal = FitnessGoal(rawValue: defaults.string(forKey: Key.fitnessGoal) ?? "") ?? .maintain
        displayName = defaults.string(forKey: Key.displayName) ?? ""
        let savedProfileTimestamp = defaults.double(forKey: Key.profileUpdatedAt)
        profileUpdatedAt = savedProfileTimestamp > 0 ? Date(timeIntervalSince1970: savedProfileTimestamp) : Date(timeIntervalSince1970:1)

        let savedProvider = AIProvider(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .builtin
        let savedModel = defaults.string(forKey: Key.model)
        let savedEndpoint = defaults.string(forKey: Key.endpoint) ?? savedProvider.endpoint
        provider = savedProvider == .dots ? .custom : savedProvider
        endpoint = savedEndpoint
        if savedProvider == .deepSeek && AIAuthentication.isOfficialDeepSeek(savedEndpoint) && savedModel == "deepseek-v4-flash" {
            model = savedProvider.model
        } else if savedProvider == .dots && savedModel == "dots.llm1.inst" {
            // 修复旧版 Dots 预设：开源权重名并不是开放平台的托管模型名。
            model = savedProvider.model
        } else if savedProvider == .glm && savedModel?.lowercased() == "glm-4.5v" {
            // GLM-4.5V 已不再是开放平台当前的视觉预设，自动迁移只有这个旧默认值。
            // 用户手动填写的其他模型名仍保持不变。
            model = savedProvider.model
        } else {
            model = savedModel ?? savedProvider.model
        }
        authStyle = AIAuthStyle(rawValue: defaults.string(forKey: Key.authStyle) ?? "") ?? savedProvider.authStyle
        if AIAuthentication.isOfficialDeepSeek(savedEndpoint) { authStyle = .bearer }
        customHeaderName = defaults.string(forKey: Key.customHeaderName) ?? "Authorization"
        supportsVision = defaults.object(forKey: Key.supportsVision) as? Bool ?? savedProvider.supportsVisionByDefault
        maxPhotos = defaults.object(forKey: Key.maxPhotos) as? Int ?? 6
        temperature = defaults.object(forKey: Key.temperature) as? Double ?? 0.2
        maxTokens = defaults.object(forKey: Key.maxTokens) as? Int ?? 1600
        customInstructions = defaults.string(forKey: Key.customInstructions) ?? ""
        aiCanWrite = defaults.object(forKey: Key.aiCanWrite) as? Bool ?? false
        if savedProvider == .dots {
            defaults.set(savedEndpoint,forKey:"ai.migratedLegacyEndpoint")
            defaults.set(AIProvider.custom.rawValue, forKey:Key.provider)
            jsonMode=false; imageDetail="medium";authStyle = .apiKey
            if extraBody == "{}" { extraBody="{\"chat_template_kwargs\":{\"enable_thinking\":false}}" }
        }
        if !shareWithLifeTrack { SharedProfileStore.clear() }
        publishSharedProfile()
    }

    func resetAfterLocalDeletion() {
        isApplyingSyncedProfile=true
        displayName="";fitnessGoal = .maintain
        height=170;baselineWeight=70;targetWeight=70;weeklyWeightTarget=0
        calorieGoal=2000;proteinGoal=100;carbsGoal=250;fatGoal=60
        provider = .builtin;endpoint=provider.endpoint;model=provider.model;authStyle = .bearer;customHeaderName="Authorization"
        customInstructions="";aiCanWrite=false;supportsVision=true;maxPhotos=6;maxTokens=4096;temperature=0.2
        coachName = Self.defaultCoachName; coachAvatarData = nil
        savedAPIProfiles=[];imageDetail=""
        extraBody="{}";tokenParameter="max_tokens";jsonMode=true;sendTemperature=true
        shareWithLifeTrack=false;appearance="system";accentColor="purple"
        syncBaseURL="https://apsonchian.ltd/liferecord-api"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("ai.profile.") { defaults.removeObject(forKey:key) }
        defaults.removeObject(forKey:"ai.migratedLegacyEndpoint")
        profileUpdatedAt=Date(timeIntervalSince1970:1);save(1.0,Key.profileUpdatedAt)
        isApplyingSyncedProfile=false
    }

    func applyGoalTemplate(_ goal: FitnessGoal) {
        fitnessGoal = goal
        switch goal {
        case .gainMuscle:
            calorieGoal = 2600; proteinGoal = 130; carbsGoal = 340; fatGoal = 70; weeklyWeightTarget = 0.25
        case .loseFat:
            calorieGoal = 2000; proteinGoal = 145; carbsGoal = 210; fatGoal = 65; weeklyWeightTarget = -0.35
        case .maintain:
            calorieGoal = 2300; proteinGoal = 125; carbsGoal = 285; fatGoal = 70; weeklyWeightTarget = 0
        }
    }

    private func publishSharedProfile() {
        if shareWithLifeTrack { SharedProfileStore.publish(self) }
    }

    func applySyncedProfile(_ profile: SyncedProfile, updatedAt: Date) {
        guard updatedAt > profileUpdatedAt else { return }
        isApplyingSyncedProfile = true
        displayName = profile.displayName
        fitnessGoal = FitnessGoal(rawValue: profile.fitnessGoal) ?? fitnessGoal
        height = profile.height
        baselineWeight = profile.baselineWeight
        targetWeight = profile.targetWeight
        weeklyWeightTarget = profile.weeklyWeightTarget
        calorieGoal = profile.calorieGoal
        proteinGoal = profile.proteinGoal
        carbsGoal = profile.carbsGoal
        fatGoal = profile.fatGoal
        isApplyingSyncedProfile = false
        profileUpdatedAt = updatedAt
        save(updatedAt.timeIntervalSince1970, Key.profileUpdatedAt)
        publishSharedProfile()
    }

    private func markProfileChanged() {
        guard !isApplyingSyncedProfile else { return }
        profileUpdatedAt = .now
        save(profileUpdatedAt.timeIntervalSince1970, Key.profileUpdatedAt)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
