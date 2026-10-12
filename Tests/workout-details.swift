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
        assert(WorkoutBodyParts.normalized(["背部", "胸部", "背部", "未分类", "自定义部位"]) == ["胸部", "背部", "自定义部位"])
        assert(WorkoutBodyParts.isValid("自定义部位") && !WorkoutBodyParts.isValid(" 未分类 "))
        try WorkoutExercise.validate([.init(name: "弹力带", sets: [], bodyPart: "自定义部位")])
        assert(WorkoutBodyParts.fromExercises([.init(name: "卧推", sets: [], bodyPart: "胸部")]) == ["胸部"])
        assert(WorkoutBodyParts.defaults.contains("二头") && WorkoutBodyParts.defaults.contains("三头") && WorkoutBodyParts.defaults.contains("小臂"))
        assert(!WorkoutBodyParts.defaults.contains("手臂"))
        assert(WorkoutBodyParts.splittingArms(in: ["胸部", "手臂", "核心"]) == ["胸部", "二头", "三头", "小臂", "核心"])
        assert(WorkoutBodyParts.splittingArms(in: ["手臂", "二头", "胸部"]) == ["二头", "三头", "小臂", "胸部"])
        assert(WorkoutBodyParts.refineArms(["手臂"], describedBy: "三头、二头、小臂训练") == ["二头", "三头", "小臂"])
        assert(WorkoutBodyParts.refineArms(["胸部", "手臂"], describedBy: "卧推和三头") == ["胸部", "三头"])
        assert(WorkoutBodyParts.refineArms(["手臂"], describedBy: "上肢训练") == ["手臂"])
        for ambiguous in ["没练二头，只练三头", "二头没有练，练了三头", "三头、二头都没练", "今天三头，下次练二头",
                          "准备练二头和三头", "二头训练？", "二头或三头", "上次二头，这次三头", "跳过二头，只练小臂"] {
            assert(WorkoutBodyParts.refineArms(["胸部", "手臂"], describedBy: ambiguous) == ["胸部", "手臂"])
        }
        assert(WorkoutBodyParts.refineArms(["二头"], describedBy: "三头训练") == ["二头"])
        print("PASS: per-set values, AI JSON decoding, round-trip, optional fields, validation and custom library")
    }
}
