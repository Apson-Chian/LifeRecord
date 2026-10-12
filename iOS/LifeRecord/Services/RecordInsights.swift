import Foundation

extension InsightRecords.Meal {
    init(_ entry: MealEntry) {
        self.init(id: entry.id, date: entry.date, name: entry.name, kind: entry.kindRaw,
                  calories: entry.calories, protein: entry.protein, carbs: entry.carbs, fat: entry.fat, fiber: entry.fiber,
                  note: entry.note, isAI: entry.source == .ai, isDemo: entry.isDemo, updatedAt: entry.updatedAt)
    }
}
extension InsightRecords.Body {
    init(_ entry: BodyMetric) {
        self.init(id: entry.id, date: entry.date, weight: entry.weight, bodyFat: entry.bodyFat,
                  isDemo: entry.isDemo, updatedAt: entry.updatedAt)
    }
}
extension InsightRecords.Workout {
    init(_ entry: WorkoutEntry) {
        self.init(id: entry.id, date: entry.date, endDate: entry.endDate, updatedAt: entry.updatedAt)
    }
}
extension GoalFeedback.Goals {
    init(_ settings: AppSettings) {
        let mode: GoalFeedback.Mode = switch settings.fitnessGoal {
        case .gainMuscle: .gain
        case .loseFat: .lose
        case .maintain: .maintain
        }
        self.init(mode: mode, baselineWeight: settings.baselineWeight, targetWeight: settings.targetWeight,
                  weeklyWeightChange: settings.weeklyWeightTarget, calories: settings.calorieGoal, protein: settings.proteinGoal)
    }
}
