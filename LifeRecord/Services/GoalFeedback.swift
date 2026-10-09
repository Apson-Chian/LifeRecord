import Foundation

/// Feedback compares records with the user's own goals, without prescribing new targets.
enum GoalFeedback {
    enum Mode { case gain, lose, maintain }
    struct Goals {
        var mode: Mode
        var baselineWeight: Double
        var targetWeight: Double
        var weeklyWeightChange: Double
        var calories: Double
        var protein: Double
    }
    struct Summary {
        var start: Date
        var end: Date
        var days: Int
        var mealDays: Int
        var calorieGoalDays: Int
        var proteinGoalDays: Int
        var averageCalories: Double?
        var averageProtein: Double?
        var measurementDays: Int
        var latestMeasurement: Date?
        var trendWeight: Double?
        var progress: Double?
        var distance: Double?
        var weeklyChange: Double?
        var completedWorkouts: Int
        var qualityIssueCount: Int
        var headline: String
        var actions: [String]

        var context: String {
            let calories = averageCalories.map { String(format: "%.0f", $0) } ?? "无记录"
            let protein = averageProtein.map { String(format: "%.0f", $0) } ?? "无记录"
            let weight = trendWeight.map { String(format: "%.1f", $0) } ?? "无记录"
            let rate = weeklyChange.map { String(format: "%.2f", $0) } ?? "数据不足"
            return "统计 \(days) 天；饮食记录 \(mealDays) 天，热量在设定目标 ±10% 内 \(calorieGoalDays) 天，蛋白质达到设定目标 \(proteinGoalDays) 天；已记录日均热量 \(calories) kcal、蛋白质 \(protein) g；测量 \(measurementDays) 天，最近趋势体重 \(weight) kg，区间变化折算 \(rate) kg/周；完成训练 \(completedWorkouts) 次；区间内待核对 \(qualityIssueCount) 项。反馈：\(headline)。下一步：\(actions.joined(separator: "；"))。"
        }
    }

    static func summarize(goals: Goals, meals: [InsightRecords.Meal], body: [InsightRecords.Body], workouts: [InsightRecords.Workout], days requestedDays: Int?, now: Date, calendar: Calendar = .current, acknowledgedIssueIDs: Set<String> = []) -> Summary {
        let today = calendar.startOfDay(for: now)
        let validMeals = meals.filter { !$0.isDemo && $0.date <= now && $0.validNutrition }
        let validBody = body.filter { !$0.isDemo && $0.date <= now && $0.validWeight }
        let validWorkouts = workouts.filter { entry in
            guard entry.date <= now, let end = entry.endDate else { return false }
            return end >= entry.date && end <= now
        }
        let dates = validMeals.map(\.date) + validBody.map(\.date) + validWorkouts.map(\.date)
        let start = requestedDays.map { calendar.date(byAdding: .day, value: -(max(1, $0) - 1), to: today)! }
            ?? calendar.startOfDay(for: dates.min() ?? now)
        let days = max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
        let grouped = Dictionary(grouping: validMeals.filter { $0.date >= start }) { calendar.startOfDay(for: $0.date) }
        let nutrition = grouped.values.map { entries in
            (calories: entries.reduce(0) { $0 + $1.calories }, protein: entries.reduce(0) { $0 + $1.protein })
        }
        let calorieValid = goals.calories.isFinite && goals.calories > 0
        let proteinValid = goals.protein.isFinite && goals.protein > 0
        let series = BodyTrend.series(validBody.map { .init(date: $0.date, value: $0.weight) }, calendar: calendar)
        let recent = series.filter { $0.date >= start }
        let current = series.last
        // A seven-day view needs a measurement one week ago as its rate anchor.
        let rateStart = requestedDays == 7 ? calendar.date(byAdding: .day, value: -7, to: today)! : start
        let ratePoints = series.filter { $0.date >= rateStart }
        let span = ratePoints.first.flatMap { first in ratePoints.last.map { calendar.dateComponents([.day], from: first.date, to: $0.date).day ?? 0 } } ?? 0
        let weekly = span >= 7 && ratePoints.count >= 3 ? (ratePoints.last!.trend - ratePoints.first!.trend) * 7 / Double(span) : nil
        let weightGoalsValid = goals.targetWeight.isFinite && (20...400).contains(goals.targetWeight) && goals.baselineWeight.isFinite && (20...400).contains(goals.baselineWeight)
        let distance = weightGoalsValid ? current.map { abs($0.trend - goals.targetWeight) } : nil
        let targetDelta = goals.targetWeight - goals.baselineWeight
        let directionValid = goals.mode == .maintain || (goals.mode == .gain && targetDelta > 0 && goals.weeklyWeightChange >= 0) || (goals.mode == .lose && targetDelta < 0 && goals.weeklyWeightChange <= 0)
        let weightConfigurationValid = weightGoalsValid && directionValid && goals.weeklyWeightChange.isFinite
        let progress: Double? = goals.mode != .maintain && weightConfigurationValid && abs(targetDelta) >= 0.2
            ? current.map { min(1, max(0, ($0.trend - goals.baselineWeight) / targetDelta)) } : nil
        let stale = current.map { (calendar.dateComponents([.day], from: $0.date, to: today).day ?? 0) > 7 } ?? true
        var headline = "先积累真实记录"
        if current != nil {
            if stale { headline = "最近测量已超过 7 天" }
            else if !weightConfigurationValid { headline = "请先核对身体目标" }
            else if goals.mode == .maintain { headline = distance! <= 0.5 ? "接近设定的维持体重" : "与维持目标仍有差距" }
            else if distance! <= 0.2 { headline = "趋势体重已接近目标" }
            else if let weekly, goals.weeklyWeightChange.isFinite {
                let expectedDirection = goals.targetWeight - current!.trend >= 0 ? 1.0 : -1.0
                if weekly * expectedDirection < -0.05 { headline = "近期变化与目标方向相反" }
                else if abs(weekly) < 0.05 { headline = "近期趋势变化较小" }
                else if abs(goals.weeklyWeightChange) > 0 && abs(weekly) > abs(goals.weeklyWeightChange) + 0.1 { headline = "变化快于设定的每周节奏" }
                else { headline = "正在向目标靠近" }
            } else { headline = "已有测量，继续观察趋势" }
        }
        let qualityIssues = RecordQuality.issues(meals: meals, body: body, workouts: workouts, now: now)
            .filter { $0.date >= start && $0.date <= now && !acknowledgedIssueIDs.contains($0.id) }
        if !stale && weightConfigurationValid && qualityIssues.contains(where: { $0.kind == .bodyValue || $0.kind == .weightJump }) {
            headline = "身体记录待核对，先确认趋势"
        }
        var actions: [String] = []
        if !qualityIssues.isEmpty { actions.append("先到记录质量检查核对这段时间的 \(qualityIssues.count) 项疑点，再解读目标反馈。") }
        if stale { actions.append("补充一次身体测量，再判断当前与目标的距离。") }
        else if weekly == nil { actions.append("在相近条件下继续测量；至少 3 个测量日、跨度 7 天后再比较每周节奏。") }
        if Double(grouped.count) / Double(days) < 0.7 { actions.append("接下来优先连续记录每日餐食；缺失日期不会按零摄入计算。") }
        else if calorieValid && nutrition.contains(where: { abs($0.calories - goals.calories) > goals.calories * 0.1 }) {
            actions.append("回看未落在热量目标 ±10% 内的日期，先确认餐食是否记全，再对照自己设定的份量计划。")
        }
        if proteinValid && !nutrition.isEmpty && nutrition.filter({ $0.protein >= goals.protein }).count < nutrition.count {
            actions.append("回看蛋白质未达到设定目标的日期，核对份量与漏记情况。")
        }
        if !weightConfigurationValid || (goals.mode != .maintain && abs(targetDelta) < 0.2) {
            actions.insert("核对起始体重、目标体重与增肌/减脂方向是否一致。", at: 0)
        }
        if !calorieValid || !proteinValid {
            actions.insert("核对每日热量和蛋白质目标，目标应为有效的正数。", at: 0)
        }
        if actions.isEmpty { actions.append("继续按当前目标记录和执行，下周再比较趋势；不根据单日波动调整目标。") }
        let completed = workouts.filter { entry in
            guard entry.date >= start && entry.date <= now, let end = entry.endDate else { return false }
            return end >= entry.date && end <= now
        }.count
        return Summary(start: start, end: now, days: days, mealDays: grouped.count,
                       calorieGoalDays: calorieValid ? nutrition.filter { abs($0.calories - goals.calories) <= goals.calories * 0.1 }.count : 0,
                       proteinGoalDays: proteinValid ? nutrition.filter { $0.protein >= goals.protein }.count : 0,
                       averageCalories: nutrition.isEmpty ? nil : nutrition.reduce(0) { $0 + $1.calories } / Double(nutrition.count),
                       averageProtein: nutrition.isEmpty ? nil : nutrition.reduce(0) { $0 + $1.protein } / Double(nutrition.count),
                       measurementDays: recent.count, latestMeasurement: current?.date, trendWeight: current?.trend, progress: progress,
                       distance: distance, weeklyChange: weekly, completedWorkouts: completed, qualityIssueCount: qualityIssues.count, headline: headline, actions: Array(actions.prefix(3)))
    }
}
