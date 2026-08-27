import Foundation

enum SharedProfileStore {
    static let appGroupID = "group.com.aotelei.liferecord"
    static let suite = UserDefaults(suiteName: appGroupID)

    struct LifeTrackActivitySnapshot: Equatable {
        let date: Date
        let distance: Double
        let duration: TimeInterval
        let sessionCount: Int
        let updatedAt: Date
    }

    private enum Key {
        static let dailyDate = "daily.date"
        static let dailyCalories = "daily.calories"
        static let dailyProtein = "daily.protein"
        static let dailyCarbs = "daily.carbs"
        static let dailyFat = "daily.fat"
        static let dailyWater = "daily.water"
        static let dailyUpdatedAt = "daily.updatedAt"
        static let activityDate = "activity.date"
        static let activityDistance = "activity.distance"
        static let activityDuration = "activity.duration"
        static let activitySessions = "activity.sessions"
        static let activityUpdatedAt = "activity.updatedAt"
        static let height = "profile.height"
        static let weight = "profile.weight"
        static let targetWeight = "profile.targetWeight"
        static let fitnessGoal = "profile.fitnessGoal"
        static let calorieGoal = "profile.calorieGoal"
        static let proteinGoal = "profile.proteinGoal"
        static let carbsGoal = "profile.carbsGoal"
        static let fatGoal = "profile.fatGoal"
        static let waterGoal = "profile.waterGoal"
        static let updatedAt = "profile.updatedAt"
    }

    static var isAvailable: Bool { suite != nil }

    @MainActor
    static func publish(_ settings: AppSettings) {
        guard let suite else { return }
        suite.set(settings.height, forKey: Key.height)
        suite.set(settings.baselineWeight, forKey: Key.weight)
        suite.set(settings.targetWeight, forKey: Key.targetWeight)
        suite.set(settings.fitnessGoal.rawValue, forKey: Key.fitnessGoal)
        suite.set(settings.calorieGoal, forKey: Key.calorieGoal)
        suite.set(settings.proteinGoal, forKey: Key.proteinGoal)
        suite.set(settings.carbsGoal, forKey: Key.carbsGoal)
        suite.set(settings.fatGoal, forKey: Key.fatGoal)
        suite.set(settings.waterGoal, forKey: Key.waterGoal)
        suite.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
    }

    static var lastPublishedAt: Date? {
        guard let suite, suite.object(forKey: Key.updatedAt) != nil else { return nil }
        return Date(timeIntervalSince1970: suite.double(forKey: Key.updatedAt))
    }

    @MainActor
    static func publishDailySummary(date: Date, nutrition: DailyNutrition, water: Double) {
        guard let suite else { return }
        suite.set(date.timeIntervalSince1970, forKey: Key.dailyDate)
        suite.set(nutrition.calories, forKey: Key.dailyCalories)
        suite.set(nutrition.protein, forKey: Key.dailyProtein)
        suite.set(nutrition.carbs, forKey: Key.dailyCarbs)
        suite.set(nutrition.fat, forKey: Key.dailyFat)
        suite.set(water, forKey: Key.dailyWater)
        suite.set(Date().timeIntervalSince1970, forKey: Key.dailyUpdatedAt)
    }

    static func lifeTrackActivity() -> LifeTrackActivitySnapshot? {
        guard let suite,
              suite.object(forKey: Key.activityUpdatedAt) != nil,
              suite.object(forKey: Key.activityDate) != nil else { return nil }
        return LifeTrackActivitySnapshot(
            date: Date(timeIntervalSince1970: suite.double(forKey: Key.activityDate)),
            distance: suite.double(forKey: Key.activityDistance),
            duration: suite.double(forKey: Key.activityDuration),
            sessionCount: suite.integer(forKey: Key.activitySessions),
            updatedAt: Date(timeIntervalSince1970: suite.double(forKey: Key.activityUpdatedAt))
        )
    }
}
