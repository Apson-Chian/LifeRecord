import Foundation

@main
struct RecordInsightChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
        func day(_ offset: Int, hour: Int = 8) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: offset, to: now)!)!
        }
        let goals = GoalFeedback.Goals(mode: .gain, baselineWeight: 60, targetWeight: 70, weeklyWeightChange: 0.25, calories: 2000, protein: 100)
        func summary(_ meals: [InsightRecords.Meal] = [], _ body: [InsightRecords.Body] = [], _ workouts: [InsightRecords.Workout] = [], goals: GoalFeedback.Goals = goals, days: Int? = 30) -> GoalFeedback.Summary {
            GoalFeedback.summarize(goals: goals, meals: meals, body: body, workouts: workouts, days: days, now: now, calendar: calendar)
        }
        let empty = summary(days: 7)
        assert(empty.days == 7 && empty.mealDays == 0 && empty.progress == nil && empty.averageCalories == nil)
        assert(empty.headline == "先积累真实记录" && !empty.actions.isEmpty)
        let meals: [InsightRecords.Meal] = [
            .init(date: day(-1), name: "正常餐食", calories: 2000, protein: 100),
            .init(date: day(-3), name: "另一餐", calories: 1800, protein: 90),
            .init(date: day(1), name: "未来", calories: 2000, protein: 100),
            .init(date: day(-2), name: "示例", calories: 9000, protein: 900, isDemo: true),
            .init(date: day(-4), name: "无效", calories: .nan)
        ]
        assert(summary([.init(date: day(-1), name: "极大值", calories: 1e308)]).mealDays == 0)
        let nutrition = summary(meals, days: 7)
        assert(nutrition.mealDays == 2 && nutrition.calorieGoalDays == 2 && nutrition.proteinGoalDays == 1)
        assert(nutrition.averageCalories == 1900 && nutrition.averageProtein == 95) // Missing days are not zero.
        assert(calendar.isDate(nutrition.start, inSameDayAs: day(-6)))
        let weights: [InsightRecords.Body] = [
            .init(date: day(-14), weight: 60), .init(date: day(-7), weight: 61), .init(date: day(0), weight: 62),
            .init(date: day(1), weight: 100), .init(date: day(-1), weight: 150, isDemo: true),
            .init(date: day(-2), weight: .infinity)
        ]
        let progress = summary([], weights)
        let expected = BodyTrend.series(weights.filter { !$0.isDemo && $0.validWeight && $0.date <= now }.map { .init(date: $0.date, value: $0.weight) }, calendar: calendar).last!.trend
        assert(progress.measurementDays == 3 && progress.trendWeight == expected && progress.weeklyChange! > 0)
        assert(abs(progress.progress! - (expected - 60) / 10) < 0.000001)
        assert(abs(progress.distance! - (70 - expected)) < 0.000001)
        let jumpBody: [InsightRecords.Body] = [.init(date: day(-1), weight: 60), .init(date: day(0), weight: 64)]
        let flagged = summary([], jumpBody)
        assert(flagged.headline == "身体记录待核对，先确认趋势" && flagged.qualityIssueCount == 1)
        let acceptedID = RecordQuality.issues(meals: [], body: jumpBody, workouts: [], now: now)[0].id
        let accepted = GoalFeedback.summarize(goals: goals, meals: [], body: jumpBody, workouts: [], days: 30, now: now, calendar: calendar, acknowledgedIssueIDs: [acceptedID])
        assert(accepted.qualityIssueCount == 0 && accepted.headline != flagged.headline)
        let stale = summary([], [.init(date: day(-8), weight: 61)])
        assert(stale.headline == "最近测量已超过 7 天" && stale.weeklyChange == nil)
        assert(summary([], [.init(date: day(-1), weight: 59)]).progress == 0)
        assert(summary([], [.init(date: day(-1), weight: 71)]).progress == 1)
        var lose = goals; lose.mode = .lose; lose.baselineWeight = 80; lose.targetWeight = 70; lose.weeklyWeightChange = -0.35
        assert(abs(summary([], [.init(date: day(-1), weight: 75)], goals: lose).progress! - 0.5) < 0.000001)
        var maintain = goals; maintain.mode = .maintain; maintain.targetWeight = 60; maintain.weeklyWeightChange = 0
        let maintained = summary([], [.init(date: day(-1), weight: 60.2)], goals: maintain)
        assert(maintained.progress == nil && maintained.headline == "接近设定的维持体重")
        var invalidGoals = goals; invalidGoals.targetWeight = .nan; invalidGoals.calories = 0
        let invalid = summary(meals, weights, goals: invalidGoals)
        assert(invalid.progress == nil && invalid.distance == nil && invalid.calorieGoalDays == 0)
        assert(invalid.actions.first!.contains("每日热量"))
        var reversedGoals = goals; reversedGoals.targetWeight = 50
        assert(summary([], weights, goals: reversedGoals).headline == "请先核对身体目标")
        assert(summary([], [.init(date: day(-1), weight: 60)], days: 7).weeklyChange == nil)
        let weeklyBody: [InsightRecords.Body] = [.init(date: day(-7), weight: 60), .init(date: day(-3), weight: 61), .init(date: day(0), weight: 62)]
        assert(summary([], weeklyBody, days: 7).weeklyChange != nil)
        assert(summary([], weeklyBody, days: 7).measurementDays == 2)
        // Count a completed cross-midnight workout by start date, but not active, future or reversed records.
        let workouts: [InsightRecords.Workout] = [
            .init(date: day(-1, hour: 23), endDate: day(0, hour: 1)),
            .init(date: day(0), endDate: nil), .init(date: day(-1), endDate: day(-2)),
            .init(date: day(0), endDate: day(1)), .init(date: day(1), endDate: day(1, hour: 9))
        ]
        assert(summary([], [], workouts, days: 7).completedWorkouts == 1)
        assert(summary(days: nil).days == 1)
        assert(summary([.init(date: day(-40), name: "历史", calories: 100)], days: nil).days == 41)

        func issues(_ meals: [InsightRecords.Meal] = [], _ body: [InsightRecords.Body] = [], _ workouts: [InsightRecords.Workout] = []) -> [RecordQuality.Issue] {
            RecordQuality.issues(meals: meals, body: body, workouts: workouts, now: now)
        }
        let a = InsightRecords.Meal(date: day(-1), name: " 牛 奶 ", calories: 120, protein: 6, carbs: 9, fat: 6)
        let b = InsightRecords.Meal(date: a.date.addingTimeInterval(120), name: "牛奶", calories: 120, protein: 6, carbs: 9, fat: 6)
        var c = b; c.id = UUID(); c.date = a.date.addingTimeInterval(300)
        let duplicates = issues([c, b, a]).filter { $0.kind == .duplicateMeal }
        assert(duplicates.count == 1 && duplicates[0].recordIDs.count == 3)
        assert(duplicates[0].id == issues([a, b, c]).first { $0.kind == .duplicateMeal }!.id)
        var later = b; later.date = a.date.addingTimeInterval(601)
        assert(!issues([a, later]).contains { $0.kind == .duplicateMeal })
        var different = b; different.protein = 8
        assert(!issues([a, different]).contains { $0.kind == .duplicateMeal })
        different = b; different.kind = "早餐"
        assert(!issues([a, different]).contains { $0.kind == .duplicateMeal })
        var demo = b; demo.isDemo = true
        assert(issues([a, demo]).isEmpty)
        var updated = b; updated.updatedAt = now
        assert(issues([a, updated]).first { $0.kind == .duplicateMeal }!.id != duplicates[0].id)
        assert(issues([.init(date: day(0), name: "无效", calories: -1)]).contains { $0.kind == .nutrition })
        assert(issues([.init(date: day(0), name: "无效", calories: .infinity)]).contains { $0.kind == .nutrition })
        assert(issues([.init(date: day(0), name: "差异", calories: 1000, protein: 10, carbs: 10)]).contains { $0.kind == .nutrition })
        assert(issues([.init(date: day(0), name: "黑咖啡", calories: 0)]).isEmpty)
        assert(issues([.init(date: day(0), name: "一餐", calories: 100, isAI: true)]).contains { $0.kind == .uncertainAI })
        assert(issues([.init(date: day(0), name: "牛奶", calories: 100, isAI: true)]).isEmpty)
        assert(issues([.init(date: day(0), name: "牛奶", calories: 100, note: "份量不明", isAI: true)]).contains { $0.kind == .uncertainAI })
        assert(issues([], [.init(date: day(0), weight: 0, bodyFat: .nan)]).contains { $0.kind == .bodyValue })
        assert(issues([], [.init(date: day(0), weight: 20, bodyFat: 1), .init(date: day(-10), weight: 400, bodyFat: 80)]).isEmpty)
        assert(issues([], [.init(date: day(-1), weight: 60), .init(date: day(0), weight: 64)]).contains { $0.kind == .weightJump })
        assert(!issues([], [.init(date: day(-4), weight: 60), .init(date: day(0), weight: 64)]).contains { $0.kind == .weightJump })
        assert(!issues([], [.init(date: day(-1), weight: 60), .init(date: day(0), weight: 61)]).contains { $0.kind == .weightJump })
        assert(issues([], [], [.init(date: day(-1), endDate: nil)]).contains { $0.kind == .workoutTime })
        assert(issues([], [], [.init(date: day(0), endDate: nil)]).isEmpty) // Four-hour active session is not flagged.
        assert(issues([], [], [.init(date: day(0), endDate: day(-1))]).contains { $0.kind == .workoutTime })
        assert(issues([], [], [.init(date: day(-1, hour: 23), endDate: day(0, hour: 1))]).isEmpty)
        assert(issues([.init(date: day(1), name: "未来", calories: 100)], [.init(date: day(1), weight: 60)], [.init(date: day(1), endDate: nil)]).filter { $0.kind == .futureDate }.count == 3)
        // Day boundaries use the supplied calendar, including DST.
        var dstCalendar = Calendar(identifier: .gregorian); dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstNow = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let dstSummary = GoalFeedback.summarize(goals: goals, meals: [], body: [], workouts: [], days: 7, now: dstNow, calendar: dstCalendar)
        assert(dstSummary.days == 7 && dstCalendar.component(.day, from: dstSummary.start) == 4)
        print("Record insights: all checks passed")
    }
}
