import Foundation

struct WorkoutSet: Codable, Identifiable, Equatable {
    var id = UUID()
    var reps: Int?
    var weight: Double?
    var durationSeconds: Int?
    enum CodingKeys: String, CodingKey { case reps, weight, durationSeconds }
}

struct WorkoutExercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sets: [WorkoutSet]
    var bodyPart: String? = nil
    enum CodingKeys: String, CodingKey { case name, sets, bodyPart }

    static let bodyParts = ["胸部", "背部", "肩部", "二头", "三头", "小臂", "核心", "臀腿", "全身", "有氧", "其他", "未分类"]

    var summary: String {
        let labeledName = bodyPart.map { "\(name) · \($0)" } ?? name
        guard !sets.isEmpty else { return labeledName }
        let rows = sets.enumerated().map { index, set in
            var values: [String] = []
            if let reps = set.reps { values.append("\(reps) 次") }
            if let weight = set.weight { values.append("\(weight.formatted()) kg") }
            if let seconds = set.durationSeconds { values.append("\(seconds) 秒") }
            return "第 \(index + 1) 组：" + (values.isEmpty ? "未填写数值" : values.joined(separator: " · "))
        }
        return "\(labeledName)（\(sets.count) 组）\n" + rows.joined(separator: "\n")
    }

    static func validate(_ exercises: [Self]) throws {
        guard exercises.count <= 50 else { throw WorkoutDetailError.invalid }
        for exercise in exercises {
            guard !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  exercise.name.count <= 100, (0...100).contains(exercise.sets.count),
                  exercise.bodyPart.map({ $0 == "未分类" || WorkoutBodyParts.isValid($0) }) ?? true else { throw WorkoutDetailError.invalid }
            for set in exercise.sets {
                guard set.reps.map({ (1...10000).contains($0) }) ?? true,
                      set.weight.map({ $0.isFinite && (0...2000).contains($0) }) ?? true,
                      set.durationSeconds.map({ (1...86400).contains($0) }) ?? true else { throw WorkoutDetailError.invalid }
            }
        }
    }
}

enum WorkoutDetailError: LocalizedError {
    case invalid
    var errorDescription: String? { "请检查动作名称和组数。每次最多 50 个动作，组数可不填，每个动作最多 100 组；次数 1–10000，重量 0–2000 kg，时长 1–86400 秒。不适用的数值请留空。" }
}

struct ExerciseTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var sets: Int = 3
    var bodyPart: String? = nil
}

enum ExerciseLibrary {
    static let key = "workout.exerciseLibrary"
    static func decode(_ raw: String) -> [ExerciseTemplate] {
        (try? JSONDecoder().decode([ExerciseTemplate].self, from: Data(raw.utf8))) ?? []
    }
    static func encode(_ values: [ExerciseTemplate]) -> String {
        (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

enum WorkoutBodyParts {
    static let key = "workout.bodyPartCatalog"
    static let defaults = WorkoutExercise.bodyParts.filter { $0 != "未分类" }
    static let armParts = ["二头", "三头", "小臂"]
    static var choices: [String] {
        decodedChoices(UserDefaults.standard.string(forKey: key) ?? "")
    }

    static func decodedChoices(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let saved = try? JSONDecoder().decode([String].self, from: data) else { return defaults }
        return saved.filter { isValid($0) }
    }

    static func isValid(_ value: String) -> Bool {
        value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.isEmpty && value != "未分类" && value.count <= 30
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    static func saveChoices(_ values: [String]) {
        guard values.allSatisfy({ isValid($0) }), Set(values).count == values.count,
              let data = try? JSONEncoder().encode(values),
              let raw = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(raw, forKey: key)
    }

    static func splittingArms(in values: [String]) -> [String] {
        guard values.contains("手臂") else { return values + armParts.filter { !values.contains($0) } }
        let preceding = values.prefix { $0 != "手臂" }.filter { !armParts.contains($0) }
        let remaining = values.drop { $0 != "手臂" }.filter { $0 != "手臂" && !armParts.contains($0) }
        return Array(preceding) + armParts + Array(remaining)
    }

    static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        let valid = values.filter { isValid($0) && seen.insert($0).inserted }
        return choices.filter { valid.contains($0) } + valid.filter { !choices.contains($0) }
    }

    static func fromExercises(_ exercises: [WorkoutExercise]) -> [String] {
        normalized(exercises.compactMap(\.bodyPart))
    }
}
