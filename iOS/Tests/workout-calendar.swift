import Foundation

@main
struct WorkoutCalendarChecks {
    static func main() {
        let shanghai = WorkoutCalendar.calendar(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        func month(_ value: String, _ records: [WorkoutCalendar.Session] = []) -> WorkoutCalendar.Month {
            WorkoutCalendar.month(containing: date(value), sessions: records,
                                  now: date("2026-10-15T18:00:00+08:00"), calendar: shanghai)
        }
        let july = month("2026-07-15T12:00:00+08:00")
        precondition(july.days.count == 35)
        precondition(july.days.first!.date == date("2026-06-29T00:00:00+08:00"))
        precondition(july.days.last!.date == date("2026-08-02T00:00:00+08:00"))
        precondition(july.days.filter(\.isInMonth).count == 31)
        precondition(shanghai.component(.weekday, from: july.days[0].date) == 2)
        precondition(month("2024-02-15T12:00:00+08:00").days.filter(\.isInMonth).count == 29)
        precondition(month("2026-08-15T12:00:00+08:00").days.count == 42)
        precondition(month("2021-02-15T12:00:00+08:00").days.count == 28)
        let december = month("2026-12-31T23:00:00+08:00")
        let january = shanghai.date(byAdding: .month, value: 1, to: december.start)!
        precondition(january == date("2027-01-01T00:00:00+08:00"))

        let lifts: [WorkoutExercise] = [.init(name: "卧推", sets: [.init(reps: 10, weight: 40), .init(reps: 8, weight: 42.5), .init(reps: nil, weight: 50), .init(reps: 15, weight: nil)])]
        func session(_ start: String, _ end: String?, parts: [String] = ["胸部", "三头"], note: String = "", exercises: [WorkoutExercise] = []) -> WorkoutCalendar.Session {
            .init(id: UUID(), date: date(start), endDate: end.map(date), bodyParts: parts, note: note, exercises: exercises)
        }
        let crossMidnight = session("2026-10-14T23:30:00+08:00", "2026-10-15T00:30:00+08:00", exercises: lifts)
        let sameDay = session("2026-10-14T10:00:00+08:00", "2026-10-14T10:30:00+08:00", parts: [], note: "慢跑")
        let ongoing = session("2026-10-15T17:00:00+08:00", nil)
        let future = session("2026-10-16T10:00:00+08:00", "2026-10-16T11:00:00+08:00", exercises: lifts)
        let futureEnd = session("2026-10-15T17:30:00+08:00", "2026-10-15T19:00:00+08:00", exercises: lifts)
        let invalid = session("2026-10-15T16:00:00+08:00", "2026-10-15T15:00:00+08:00", exercises: lifts)
        let adjacentMonth = session("2026-09-30T10:00:00+08:00", "2026-09-30T11:00:00+08:00", exercises: lifts)
        let october = month("2026-10-15T12:00:00+08:00", [ongoing, future, futureEnd, invalid, crossMidnight, sameDay, adjacentMonth])
        precondition(october.completedCount == 2 && october.recordedDays == 1 && october.minutes == 90)
        let fourteenth = october.days.first { shanghai.component(.day, from: $0.date) == 14 && $0.isInMonth }!
        precondition(fourteenth.sessions.map(\.id) == [sameDay.id, crossMidnight.id])
        precondition(fourteenth.completedCount == 2 && fourteenth.volume == 740)
        let fifteenth = october.days.first { shanghai.component(.day, from: $0.date) == 15 && $0.isInMonth }!
        precondition(fifteenth.completedCount == 0 && fifteenth.volume == nil)
        precondition(sameDay.volume == nil && sameDay.title == "慢跑" && crossMidnight.title == "胸部+三头")
        precondition(session("2026-10-01T00:00:00+08:00", nil, parts: [], exercises: lifts).title == "卧推")
        precondition(session("2026-10-01T00:00:00+08:00", nil, parts: [], note: "  ").title == "未填写训练内容")
        let partial = session("2026-10-14T23:30:00+08:00", "2026-10-15T00:30:00+08:00", exercises: [
            .init(name: "核对", sets: [.init(reps: 10, weight: .infinity), .init(reps: -1, weight: 40), .init(reps: 10, weight: 0)])
        ])
        precondition(partial.volume == nil)
        let empty = month("2026-01-15T12:00:00+08:00")
        precondition(empty.completedCount == 0 && empty.recordedDays == 0 && empty.days.allSatisfy { $0.sessions.isEmpty && $0.volume == nil })

        let timezoneEntry = session("2026-10-14T18:30:00Z", "2026-10-14T19:00:00Z")
        let localDay = month("2026-10-15T12:00:00+08:00", [timezoneEntry]).days.first { !$0.sessions.isEmpty }!
        precondition(shanghai.component(.day, from: localDay.date) == 15)
        let newYork = WorkoutCalendar.calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        let march = WorkoutCalendar.month(containing: date("2026-03-15T12:00:00-04:00"), sessions: [], calendar: newYork)
        precondition(march.days.count == 42 && Set(march.days.map(\.date)).count == 42)
        precondition(march.days.allSatisfy { newYork.component(.hour, from: $0.date) == 0 })
        print("PASS: Monday-first months, leap day, year rollover, same-day grouping, volume, missing values, midnight, future exclusion, time zones and DST")
    }
}
