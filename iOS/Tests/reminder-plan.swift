import Foundation

@main
struct ReminderTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 18))! // Monday
        var config = ReminderPreferences()
        assert(ReminderPlan.items(preferences: config, records: .init(), now: now, calendar: calendar).isEmpty)
        config.enabled = true; config.body = true; config.workout = true
        var records = ReminderPlan.Records()
        var plan = ReminderPlan.items(preferences: config, records: records, now: now, calendar: calendar)
        assert(plan.count == 30 && Set(plan.map(\.id)).count == 30)
        assert(plan[0].missing == ["餐食", "身体数据", "训练"])
        assert(!plan[1].missing.contains("训练")) // Tuesday rest day
        records.meals = [now]; records.body = [now]; records.workouts = [now]
        plan = ReminderPlan.items(preferences: config, records: records, now: now, calendar: calendar)
        assert(plan.count == 29) // complete today cancels today only
        records.workouts = []
        plan = ReminderPlan.items(preferences: config, records: records, now: now, calendar: calendar)
        assert(plan[0].missing == ["训练"])
        let afterTime = now.addingTimeInterval(4 * 3600)
        assert(ReminderPlan.items(preferences: config, records: .init(), now: afterTime, calendar: calendar).count == 29)
        let tomorrow = now.addingTimeInterval(86400)
        let next = ReminderPlan.items(preferences: config, records: records, now: tomorrow, calendar: calendar)
        assert(next[0].missing == ["餐食", "身体数据"])
        assert(ReminderPreferences.decode(config.encoded) == config)
        // A future-dated record must not suppress a reminder before it was recorded.
        records.meals = [now.addingTimeInterval(3600)]
        assert(ReminderPlan.items(preferences: config, records: records, now: now, calendar: calendar)[0].missing.contains("餐食"))
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dst = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 18))!
        let dstPlan = ReminderPlan.items(preferences: config, records: .init(), now: dst, calendar: calendar)
        assert(dstPlan.count == 30 && dstPlan.allSatisfy { calendar.component(.hour, from: $0.date) == 21 })
        print("PASS: opt-in, category cancellation, training weekdays, midnight, elapsed time, future dates and DST")
    }
}
