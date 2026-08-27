import Foundation
import SwiftData

enum MealKind: String, Codable, CaseIterable, Identifiable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case snack = "加餐"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .breakfast: "sun.horizon.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "takeoutbag.and.cup.and.straw.fill"
        }
    }
}

enum EntrySource: String, Codable {
    case manual = "手动"
    case ai = "AI 估算"
}

@Model
final class MealEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kindRaw: String
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var note: String
    var sourceRaw: String
    var createdAt: Date
    // Declaration-site defaults make newly added fields lightweight-migratable.
    var isDemo: Bool = false

    init(
        id: UUID = UUID(),
        date: Date = .now,
        kind: MealKind,
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double = 0,
        note: String = "",
        source: EntrySource = .manual,
        isDemo: Bool = false
    ) {
        self.id = id
        self.date = date
        self.kindRaw = kind.rawValue
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.note = note
        self.sourceRaw = source.rawValue
        self.createdAt = .now
        self.isDemo = isDemo
    }

    var kind: MealKind { MealKind(rawValue: kindRaw) ?? .snack }
    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }
}

@Model
final class BodyMetric {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weight: Double
    var bodyFat: Double?
    var waist: Double?
    var note: String
    var isDemo: Bool = false

    init(
        id: UUID = UUID(),
        date: Date = .now,
        weight: Double,
        bodyFat: Double? = nil,
        waist: Double? = nil,
        note: String = "",
        isDemo: Bool = false
    ) {
        self.id = id
        self.date = date
        self.weight = weight
        self.bodyFat = bodyFat
        self.waist = waist
        self.note = note
        self.isDemo = isDemo
    }
}

@Model
final class WaterEntry {
    static let commonAmounts: [Double] = [200, 250, 330, 500, 750]

    @Attribute(.unique) var id: UUID
    var date: Date
    var milliliters: Double
    var isDemo: Bool = false

    init(id: UUID = UUID(), date: Date = .now, milliliters: Double, isDemo: Bool = false) {
        self.id = id
        self.date = date
        self.milliliters = milliliters
        self.isDemo = isDemo
    }
}

@Model
final class CoachConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isDemo: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \CoachMessage.conversation)
    var messages: [CoachMessage]

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [CoachMessage] = [],
        isDemo: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.isDemo = isDemo
    }
}

@Model
final class CoachMessage {
    @Attribute(.unique) var id: UUID
    var date: Date
    var role: String
    var content: String
    var conversation: CoachConversation?

    init(id: UUID = UUID(), date: Date = .now, role: String, content: String) {
        self.id = id
        self.date = date
        self.role = role
        self.content = content
    }
}

struct MealDraft: Codable {
    var name = ""
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var fiber = 0.0
    var note = ""
}

struct DailyNutrition {
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var fiber = 0.0

    mutating func add(_ meal: MealEntry) {
        calories += meal.calories
        protein += meal.protein
        carbs += meal.carbs
        fat += meal.fat
        fiber += meal.fiber
    }
}

extension Calendar {
    func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        isDate(lhs, inSameDayAs: rhs)
    }
}
