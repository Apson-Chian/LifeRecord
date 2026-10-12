import Foundation

/// Value snapshots keep analysis independent of SwiftData and never mutate records.
enum InsightRecords {
    struct Meal {
        var id = UUID()
        var date: Date
        var name: String
        var kind = "午餐"
        var calories: Double
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var fiber: Double = 0
        var note = ""
        var isAI = false
        var isDemo = false
        var updatedAt = Date.distantPast
        var validNutrition: Bool {
            [calories, protein, carbs, fat, fiber].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1_000_000 }
        }
    }
    struct Body {
        var id = UUID()
        var date: Date
        var weight: Double
        var bodyFat: Double?
        var isDemo = false
        var updatedAt = Date.distantPast
        var validWeight: Bool { weight.isFinite && (20...400).contains(weight) }
    }
    struct Workout {
        var id = UUID()
        var date: Date
        var endDate: Date?
        var updatedAt = Date.distantPast
    }
}

enum RecordQuality {
    enum Kind: String { case duplicateMeal, nutrition, uncertainAI, bodyValue, weightJump, workoutTime, futureDate }
    enum Category: String { case meal = "餐食", body = "身体", workout = "训练" }
    struct Issue: Identifiable {
        let id: String
        let kind: Kind
        let category: Category
        let recordIDs: [UUID]
        let date: Date
        let title: String
        let detail: String
    }

    static func issues(meals: [InsightRecords.Meal], body: [InsightRecords.Body], workouts: [InsightRecords.Workout], now: Date) -> [Issue] {
        var result: [Issue] = []
        func add(_ kind: Kind, _ category: Category, _ ids: [UUID], _ dates: [Date], _ date: Date, _ title: String, _ detail: String) {
            let signature = zip(ids, dates).map { "\($0.uuidString):\($1.timeIntervalSince1970)" }.sorted().joined(separator: "|")
            result.append(Issue(id: "\(kind.rawValue):\(signature)", kind: kind, category: category, recordIDs: ids, date: date, title: title, detail: detail))
        }
        let realMeals = meals.filter { !$0.isDemo }
        for meal in realMeals {
            if meal.date > now.addingTimeInterval(300) {
                add(.futureDate, .meal, [meal.id], [meal.updatedAt], meal.date, "餐食时间在未来", "核对这餐的日期和时间，未来记录不会计入目标反馈。")
            }
            let energy = meal.protein * 4 + meal.carbs * 4 + meal.fat * 9
            if !meal.validNutrition || meal.calories > 5000 || meal.protein > 500 || meal.carbs > 1500 || meal.fat > 500 || meal.fiber > 200 {
                add(.nutrition, .meal, [meal.id], [meal.updatedAt], meal.date, "营养数值需要核对", "\(meal.name)：检查份量、单位和小数点。单餐较大数值也可能正确，请自行确认。")
            } else if energy > 0 && abs(meal.calories - energy) > max(150, meal.calories * 0.4) {
                add(.nutrition, .meal, [meal.id], [meal.updatedAt], meal.date, "热量与宏量营养差异较大", "\(meal.name)：按蛋白质、碳水和脂肪粗略换算的热量与记录差异较大。纤维、酒精和标签算法可能带来差异，请核对原始信息。")
            }
            let name = normalized(meal.name)
            let vagueName = ["食物", "餐食", "一餐", "午餐", "晚餐", "早餐", "加餐", "未知"].contains(name)
            let uncertain = ["份量不详", "份量不明", "无法确定", "待确认", "不确定"].contains { meal.note.contains($0) }
            if meal.isAI && (name.isEmpty || vagueName || uncertain) {
                add(.uncertainAI, .meal, [meal.id], [meal.updatedAt], meal.date, "AI 估算信息不足", "\(meal.name)：补充食物名称、重量或实际吃下的份量，再核对营养数值。")
            }
        }
        // Group by name and meal kind; only nearby, nutritionally identical entries are candidates.
        let groups = Dictionary(grouping: realMeals.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.validNutrition }) { "\($0.kind)|\(normalized($0.name))" }
        for group in groups.values {
            var clusters: [[InsightRecords.Meal]] = []
            for meal in group.sorted(by: { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }) {
                var matching: Int?
                for index in clusters.indices.reversed() {
                    let first = clusters[index][0]
                    if meal.date.timeIntervalSince(first.date) > 600 { break }
                    if sameNutrition(first, meal) { matching = index; break }
                }
                if let matching { clusters[matching].append(meal) }
                else { clusters.append([meal]) }
            }
            for cluster in clusters where cluster.count > 1 {
                let first = cluster[0]
                add(.duplicateMeal, .meal, cluster.map(\.id), cluster.map(\.updatedAt), first.date, "疑似重复餐食 · \(cluster.count) 条", "\(first.name)：10 分钟内名称、餐次和营养数值相同。可能是重复录入，也可能是多份，请逐条核对。")
            }
        }
        let realBody = body.filter { !$0.isDemo }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        var previous: InsightRecords.Body?
        for metric in realBody {
            if metric.date > now.addingTimeInterval(300) {
                add(.futureDate, .body, [metric.id], [metric.updatedAt], metric.date, "测量时间在未来", "核对测量日期，未来测量不会计入目标反馈。")
            }
            if !metric.validWeight || metric.bodyFat.map({ !$0.isFinite || !(1...80).contains($0) }) == true {
                add(.bodyValue, .body, [metric.id], [metric.updatedAt], metric.date, "身体数值需要核对", "检查体重是否为 20–400 kg、体脂率是否为 1–80%，以及单位和小数点。范围与录入表单一致。")
            }
            if metric.validWeight && metric.date <= now {
                if let previous, metric.date.timeIntervalSince(previous.date) <= 3 * 86400,
                   abs(metric.weight - previous.weight) >= max(3, previous.weight * 0.05) {
                    add(.weightJump, .body, [previous.id, metric.id], [previous.updatedAt, metric.updatedAt], metric.date, "短期体重变化较大", "3 天内相邻测量相差至少 3 kg 且达到前次体重的 5%。核对时间、单位和测量条件；这不代表脂肪变化。")
                }
                previous = metric
            }
        }
        for workout in workouts {
            if workout.date > now.addingTimeInterval(300) || workout.endDate.map({ $0 > now.addingTimeInterval(300) }) == true {
                add(.futureDate, .workout, [workout.id], [workout.updatedAt], workout.date, "训练时间在未来", "核对训练起止时间，未来训练不会计入目标反馈。")
            }
            if let end = workout.endDate {
                let duration = end.timeIntervalSince(workout.date)
                if duration < 0 || duration > 6 * 3600 {
                    add(.workoutTime, .workout, [workout.id], [workout.updatedAt], workout.date, "训练时长需要核对", "结束时间早于开始，或单次训练超过 6 小时。检查是否忘记结束计时；长时间活动也可能正确。")
                }
            } else if now.timeIntervalSince(workout.date) > 6 * 3600 {
                add(.workoutTime, .workout, [workout.id], [workout.updatedAt], workout.date, "训练可能忘记结束", "这次训练已计时超过 6 小时，请填写实际结束时间。")
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace }
    }
    private static func sameNutrition(_ a: InsightRecords.Meal, _ b: InsightRecords.Meal) -> Bool {
        zip([a.calories, a.protein, a.carbs, a.fat, a.fiber], [b.calories, b.protein, b.carbs, b.fat, b.fiber]).allSatisfy { abs($0 - $1) < 0.01 }
    }
}
