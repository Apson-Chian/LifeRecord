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
    enum CodingKeys: String, CodingKey { case name, sets }

    var summary: String {
        guard !sets.isEmpty else { return name }
        let rows = sets.enumerated().map { index, set in
            var values: [String] = []
            if let reps = set.reps { values.append("\(reps) 次") }
            if let weight = set.weight { values.append("\(weight.formatted()) kg") }
            if let seconds = set.durationSeconds { values.append("\(seconds) 秒") }
            return "第 \(index + 1) 组：" + (values.isEmpty ? "未填写数值" : values.joined(separator: " · "))
        }
        return "\(name)（\(sets.count) 组）\n" + rows.joined(separator: "\n")
    }

    static func validate(_ exercises: [Self]) throws {
        guard exercises.count <= 50 else { throw WorkoutDetailError.invalid }
        for exercise in exercises {
            guard !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  exercise.name.count <= 100, (0...100).contains(exercise.sets.count) else { throw WorkoutDetailError.invalid }
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
