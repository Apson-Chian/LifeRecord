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
    case deepSeek = "DeepSeek"
    case dots = "Dots"
    case glm = "智谱 GLM"
    case custom = "自定义"

    var id: String { rawValue }

    var keychainID: String {
        switch self {
        case .deepSeek: "deepseek"
        case .dots: "dots"
        case .glm: "glm"
        case .custom: "custom"
        }
    }

    var endpoint: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com/chat/completions"
        case .dots: "https://note3-prev-api.askdiandian.com/v1/chat/completions"
        case .glm: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .custom: "https://example.com/v1/chat/completions"
        }
    }

    var model: String {
        switch self {
        case .deepSeek: "deepseek-v4-flash"
        case .dots: "dots3-note-prev"
        case .glm: "glm-4.5v"
        case .custom: "vision-model-name"
        }
    }

    var authStyle: AIAuthStyle { self == .dots ? .apiKey : .bearer }
    var supportsVisionByDefault: Bool { self == .dots || self == .glm || self == .custom }
}

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let calorieGoal = "calorieGoal"
        static let proteinGoal = "proteinGoal"
        static let carbsGoal = "carbsGoal"
        static let fatGoal = "fatGoal"
        static let waterGoal = "waterGoal"
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
    }

    var calorieGoal: Double { didSet { save(calorieGoal, Key.calorieGoal); publishSharedProfile() } }
    var proteinGoal: Double { didSet { save(proteinGoal, Key.proteinGoal); publishSharedProfile() } }
    var carbsGoal: Double { didSet { save(carbsGoal, Key.carbsGoal); publishSharedProfile() } }
    var fatGoal: Double { didSet { save(fatGoal, Key.fatGoal); publishSharedProfile() } }
    var waterGoal: Double { didSet { save(waterGoal, Key.waterGoal); publishSharedProfile() } }
    var targetWeight: Double { didSet { save(targetWeight, Key.targetWeight); publishSharedProfile() } }
    var height: Double { didSet { save(height, Key.height); publishSharedProfile() } }
    var baselineWeight: Double { didSet { save(baselineWeight, Key.baselineWeight); publishSharedProfile() } }
    var weeklyWeightTarget: Double { didSet { save(weeklyWeightTarget, Key.weeklyWeightTarget) } }
    var fitnessGoal: FitnessGoal { didSet { save(fitnessGoal.rawValue, Key.fitnessGoal); publishSharedProfile() } }
    var displayName: String { didSet { save(displayName, Key.displayName) } }
    var provider: AIProvider {
        didSet {
            save(provider.rawValue, Key.provider)
            guard provider != oldValue else { return }
            endpoint = provider.endpoint
            model = provider.model
            authStyle = provider.authStyle
            supportsVision = provider.supportsVisionByDefault
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

    init(defaults: UserDefaults = .standard) {
        // 181 cm / 64 kg 的增肌起始模板；每一项都可以在设置中修改。
        calorieGoal = defaults.object(forKey: Key.calorieGoal) as? Double ?? 2600
        proteinGoal = defaults.object(forKey: Key.proteinGoal) as? Double ?? 130
        carbsGoal = defaults.object(forKey: Key.carbsGoal) as? Double ?? 340
        fatGoal = defaults.object(forKey: Key.fatGoal) as? Double ?? 70
        waterGoal = defaults.object(forKey: Key.waterGoal) as? Double ?? 2800
        targetWeight = defaults.object(forKey: Key.targetWeight) as? Double ?? 72
        height = defaults.object(forKey: Key.height) as? Double ?? 181
        baselineWeight = defaults.object(forKey: Key.baselineWeight) as? Double ?? 64
        weeklyWeightTarget = defaults.object(forKey: Key.weeklyWeightTarget) as? Double ?? 0.25
        fitnessGoal = FitnessGoal(rawValue: defaults.string(forKey: Key.fitnessGoal) ?? "") ?? .gainMuscle
        displayName = defaults.string(forKey: Key.displayName) ?? ""

        let savedProvider = AIProvider(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .glm
        let savedModel = defaults.string(forKey: Key.model)
        provider = savedProvider
        endpoint = defaults.string(forKey: Key.endpoint) ?? savedProvider.endpoint
        if savedProvider == .dots && savedModel == "dots.llm1.inst" {
            // 修复旧版 Dots 预设：开源权重名并不是开放平台的托管模型名。
            model = savedProvider.model
        } else {
            model = savedModel ?? savedProvider.model
        }
        authStyle = AIAuthStyle(rawValue: defaults.string(forKey: Key.authStyle) ?? "") ?? savedProvider.authStyle
        customHeaderName = defaults.string(forKey: Key.customHeaderName) ?? "Authorization"
        supportsVision = defaults.object(forKey: Key.supportsVision) as? Bool ?? savedProvider.supportsVisionByDefault
        maxPhotos = defaults.object(forKey: Key.maxPhotos) as? Int ?? 6
        temperature = defaults.object(forKey: Key.temperature) as? Double ?? 0.2
        maxTokens = defaults.object(forKey: Key.maxTokens) as? Int ?? 1600
        customInstructions = defaults.string(forKey: Key.customInstructions) ?? ""
        aiCanWrite = defaults.object(forKey: Key.aiCanWrite) as? Bool ?? true
        publishSharedProfile()
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
        SharedProfileStore.publish(self)
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
