import Foundation

@main
struct WorkoutDetailTests {
    static func main() throws {
        let json = #"[{"name":"卧推","sets":[{"reps":8,"weight":40},{"reps":6,"weight":45}]},{"name":"平板支撑","sets":[{"durationSeconds":60}]}]"#
        let values = try JSONDecoder().decode([WorkoutExercise].self, from: Data(json.utf8))
        try WorkoutExercise.validate(values)
        assert(values[0].sets.count == 2 && values[0].sets[1].weight == 45)
        assert(values[1].sets[0].reps == nil && values[1].sets[0].durationSeconds == 60)
        let roundtrip = try JSONDecoder().decode([WorkoutExercise].self, from: JSONEncoder().encode(values))
        assert(roundtrip.map(\.summary) == values.map(\.summary))
        assert(roundtrip[0].summary.contains("第 2 组：6 次"))
        for invalid in [WorkoutExercise(name: "", sets: [WorkoutSet()]), .init(name: "蹲", sets: Array(repeating: WorkoutSet(), count: 101)), .init(name: "蹲", sets: [.init(reps: -1)]), .init(name: "蹲", sets: [.init(weight: .infinity)]), .init(name: "蹲", sets: [.init(durationSeconds: 0)])] {
            do { try WorkoutExercise.validate([invalid]); assertionFailure("Invalid workout accepted") } catch {}
        }
        try WorkoutExercise.validate([.init(name: "俯卧撑", sets: [.init(reps: 10, weight: 0)])])
        let selected = WorkoutExercise(name: "深蹲", sets: [])
        try WorkoutExercise.validate([selected])
        assert(selected.summary == "深蹲")
        let selectedRoundtrip = try JSONDecoder().decode(WorkoutExercise.self, from: JSONEncoder().encode(selected))
        assert(selectedRoundtrip.name == "深蹲" && selectedRoundtrip.sets.isEmpty)
        let library = [ExerciseTemplate(name: "我的动作", sets: 4)]
        assert(ExerciseLibrary.decode(ExerciseLibrary.encode(library))[0].sets == 4)
        assert(WorkoutBodyParts.normalized(["背部", "胸部", "背部", "未分类", "未知"]) == ["胸部", "背部"])
        assert(WorkoutBodyParts.fromExercises([.init(name: "卧推", sets: [], bodyPart: "胸部")]) == ["胸部"])
        print("PASS: per-set values, AI JSON decoding, round-trip, optional fields, validation and custom library")
    }
}
