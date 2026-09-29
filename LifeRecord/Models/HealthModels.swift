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
    var updatedAt: Date = Date.now
    // Only compact server image identifiers are kept on device; image bytes live on the private server.
    var photoIDsRaw: String = "[]"

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
        isDemo: Bool = false,
        photoIDs: [String] = []
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
        self.updatedAt = .now
        self.photoIDs = photoIDs
    }

    var kind: MealKind { MealKind(rawValue: kindRaw) ?? .snack }
    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }
    var photoIDs: [String] {
        get {
            guard let data = photoIDsRaw.data(using: .utf8),
                  let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return values
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else { return }
            photoIDsRaw = value
        }
    }
}

@Model
final class FavoriteFood {
    @Attribute(.unique) var id: UUID
    var name: String
    var portion: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var note: String
    @Attribute(.externalStorage) var photoData: Data?
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, portion: String = "1份", calories: Double = 0, protein: Double = 0,
         carbs: Double = 0, fat: Double = 0, fiber: Double = 0, note: String = "",
         photoData: Data? = nil) {
        self.id = id
        self.name = name
        self.portion = portion
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.note = note
        self.photoData = photoData
        self.updatedAt = .now
    }

    var nutritionSummary: String {
        "\(name)（\(portion)）：\(calories.formatted()) kcal；蛋白质 \(protein.formatted()) g、碳水 \(carbs.formatted()) g、脂肪 \(fat.formatted()) g、膳食纤维 \(fiber.formatted()) g。"
    }
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
    var updatedAt: Date = Date.now

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
        self.updatedAt = .now
    }
}

// Keep the old entity in the SwiftData schema so installed stores can open after
// the drinking feature is removed. It is no longer queried or synchronized.
@Model
final class WaterEntry {
    static let commonAmounts: [Double] = [200, 250, 330, 500, 750]
    @Attribute(.unique) var id: UUID
    var date: Date
    var milliliters: Double
    var isDemo: Bool = false
    var note: String = ""
    var updatedAt: Date = Date.now
    init(id: UUID = UUID(), date: Date = .now, milliliters: Double, isDemo: Bool = false, note: String = "") {
        self.id = id; self.date = date; self.milliliters = milliliters; self.isDemo = isDemo; self.note = note; self.updatedAt = .now
    }
}

@Model
final class SyncTombstone {
    @Attribute(.unique) var key: String
    var recordID: UUID
    var recordType: String
    var deletedAt: Date

    init(recordID: UUID, recordType: String, deletedAt: Date = .now) {
        self.key = "\(recordType):\(recordID.uuidString.lowercased())"
        self.recordID = recordID
        self.recordType = recordType
        self.deletedAt = deletedAt
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

@Model
final class WorkoutEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var endDate: Date?
    var note: String
    var exercisesRaw: String = "[]"
    // Empty means a legacy record whose parts come from its exercises.
    var bodyPartsRaw: String = ""
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), date: Date = .now, endDate: Date? = nil, note: String = "") {
        self.id = id
        self.date = date
        self.endDate = endDate
        self.note = note
        self.updatedAt = .now
    }
    var minutes: Double { max(0, (endDate ?? .now).timeIntervalSince(date) / 60) }
}


extension WorkoutEntry {
    var bodyParts: [String] {
        get {
            guard !bodyPartsRaw.isEmpty else { return WorkoutBodyParts.fromExercises(exercises) }
            let values = (try? JSONDecoder().decode([String].self, from: Data(bodyPartsRaw.utf8))) ?? []
            return WorkoutBodyParts.normalized(values)
        }
        set {
            let values = WorkoutBodyParts.normalized(newValue)
            bodyPartsRaw = (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
    }
    var exercises: [WorkoutExercise] {
        get { (try? JSONDecoder().decode([WorkoutExercise].self, from: Data(exercisesRaw.utf8))) ?? [] }
        set { exercisesRaw = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }
    var contentSummary: String {
        ([bodyParts.joined(separator: "、"), note] + exercises.map(\.summary)).filter { !$0.isEmpty }.joined(separator: "\n")
    }
    var overviewSummary: String {
        let parts = bodyParts.joined(separator: " · ")
        let detail = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return [parts, detail].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
