import Foundation

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

struct SyncedMeal: Codable {
    var id: String
    var date: Double
    var kind: String
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var note: String
    var source: String
    var createdAt: Double
    var updatedAt: Double
    var photoIDs: [String]?
    var inputText: String?
    var sourceConversationID: String?
}

extension SyncedMeal {
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        id = try v.decode(String.self, forKey: .id)
        date = try v.decode(Double.self, forKey: .date)
        updatedAt = try v.decode(Double.self, forKey: .updatedAt)
        name = try v.decode(String.self, forKey: .name)
        // Defaults apply only to absent legacy fields, never to explicit null or
        // a wrong type. Original wire data remains available on the server.
        kind = v.contains(.kind) ? try v.decode(String.self, forKey: .kind) : "加餐"
        source = v.contains(.source) ? try v.decode(String.self, forKey: .source) : "手动"
        note = v.contains(.note) ? try v.decode(String.self, forKey: .note) : ""
        createdAt = v.contains(.createdAt) ? try v.decode(Double.self, forKey: .createdAt) : date
        calories = v.contains(.calories) ? try v.decode(Double.self, forKey: .calories) : 0
        protein = v.contains(.protein) ? try v.decode(Double.self, forKey: .protein) : 0
        carbs = v.contains(.carbs) ? try v.decode(Double.self, forKey: .carbs) : 0
        fat = v.contains(.fat) ? try v.decode(Double.self, forKey: .fat) : 0
        fiber = v.contains(.fiber) ? try v.decode(Double.self, forKey: .fiber) : 0
        photoIDs = try v.decodeIfPresent([String].self, forKey: .photoIDs)
        inputText = try v.decodeIfPresent(String.self, forKey: .inputText)
        sourceConversationID = try v.decodeIfPresent(String.self, forKey: .sourceConversationID)
    }
}

struct SyncedBodyMetric: Codable {
    var id: String
    var date: Double
    var weight: Double
    var bodyFat: Double?
    var waist: Double?
    var note: String
    var updatedAt: Double
}

extension SyncedBodyMetric {
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        id = try v.decode(String.self, forKey: .id)
        date = try v.decode(Double.self, forKey: .date)
        updatedAt = try v.decode(Double.self, forKey: .updatedAt)
        weight = try v.decode(Double.self, forKey: .weight)
        bodyFat = try v.decodeIfPresent(Double.self, forKey: .bodyFat)
        waist = try v.decodeIfPresent(Double.self, forKey: .waist)
        note = v.contains(.note) ? try v.decode(String.self, forKey: .note) : ""
    }
}

struct SyncedWorkout: Codable {
    var exercises: [WorkoutExercise]? = nil
    var bodyParts: [String]? = nil
    var id: String
    var date: Double
    var endDate: Double?
    var note: String
    var updatedAt: Double
}

extension SyncedWorkout {
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        id = try v.decode(String.self, forKey: .id)
        date = try v.decode(Double.self, forKey: .date)
        updatedAt = try v.decode(Double.self, forKey: .updatedAt)
        endDate = try v.decodeIfPresent(Double.self, forKey: .endDate)
        note = v.contains(.note) ? try v.decode(String.self, forKey: .note) : ""
        exercises = try v.decodeIfPresent([WorkoutExercise].self, forKey: .exercises)
        bodyParts = try v.decodeIfPresent([String].self, forKey: .bodyParts)
    }
}

struct SyncedDeletion: Codable {
    var id: String
    var recordType: String
    var deletedAt: Double
}

struct SyncSnapshot: Codable {
    var meals: [SyncedMeal]
    var bodyMetrics: [SyncedBodyMetric]
    var workoutEntries: [SyncedWorkout]? = nil
    var settings: SyncedProfile?
    var deletions: [SyncedDeletion]
    var serverTime: Double?
}
