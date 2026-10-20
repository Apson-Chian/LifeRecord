import Foundation

/// Validation for explicit writes. Never use this to discard historical records.
enum RecordInput {
    struct Invalid: LocalizedError {
        let field: String
        let reason: String
        var errorDescription: String? { "\(field)：\(reason)" }
    }
    static let mealLimits: [(String, Double)] = [("calories", 20000), ("protein", 2000), ("carbs", 3000), ("fat", 2000), ("fiber", 500)]
    static let profileLimits: [(String, Double, Double)] = [
        ("height", 50, 300), ("baselineWeight", 20, 400), ("targetWeight", 20, 400),
        ("weeklyWeightTarget", -5, 5), ("calorieGoal", 500, 10000),
        ("proteinGoal", 1, 600), ("carbsGoal", 1, 1200), ("fatGoal", 1, 500)
    ]
    static func number(_ value: Double, field: String, low: Double, high: Double) throws {
        guard value.isFinite, (low...high).contains(value) else {
            throw Invalid(field: field, reason: "请输入 \(low.formatted())–\(high.formatted()) 之间的有限数值")
        }
    }
    static func meal(name: String, calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, note: String = "") throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 10000 else {
            throw Invalid(field: "name", reason: "请填写 1–10000 字符的餐名")
        }
        guard note.count <= 10000 else { throw Invalid(field: "note", reason: "最多 10000 字符") }
        for ((field, high), value) in zip(mealLimits, [calories, protein, carbs, fat, fiber]) {
            try number(value, field: field, low: 0, high: high)
        }
    }
}
