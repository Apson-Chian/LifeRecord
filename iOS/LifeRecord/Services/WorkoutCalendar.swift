import Foundation

enum WorkoutCalendar {
    struct Session: Identifiable {
        let id: UUID
        let date: Date
        let endDate: Date?
        let bodyParts: [String]
        let note: String
        let exercises: [WorkoutExercise]

        var title: String {
            if !bodyParts.isEmpty { return bodyParts.joined(separator: "+") }
            let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
            let names = exercises.map(\.name).filter { !$0.isEmpty }
            return names.isEmpty ? "未填写训练内容" : names.joined(separator: "+")
        }

        func isCompleted(at now: Date) -> Bool {
            guard let endDate else { return false }
            return date <= now && endDate >= date && endDate <= now
        }

        /// Missing load/reps and bodyweight-only sets are never turned into guessed volume.
        var volume: Double? {
            let loads = exercises.flatMap(\.sets).compactMap { set -> Double? in
                guard let weight = set.weight, weight.isFinite, weight > 0,
                      let reps = set.reps, reps > 0 else { return nil }
                let load = weight * Double(reps)
                return load.isFinite ? load : nil
            }
            guard !loads.isEmpty else { return nil }
            let total = loads.reduce(0, +)
            return total.isFinite ? total : nil
        }
    }

    struct Day: Identifiable {
        let date: Date
        let isInMonth: Bool
        let sessions: [Session]
        let completedCount: Int
        let minutes: Double
        let volume: Double?
        var id: Date { date }
    }

    struct Month {
        let start: Date
        let days: [Day]
        var recordedDays: Int { days.filter { $0.isInMonth && $0.completedCount > 0 }.count }
        var completedCount: Int { days.filter(\.isInMonth).reduce(0) { $0 + $1.completedCount } }
        var minutes: Double { days.filter(\.isInMonth).reduce(0) { $0 + $1.minutes } }
    }

    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    static func startOfMonth(containing date: Date, calendar: Calendar = WorkoutCalendar.calendar()) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func month(containing date: Date, sessions: [Session], now: Date = .now,
                      calendar: Calendar = WorkoutCalendar.calendar()) -> Month {
        let start = startOfMonth(containing: date, calendar: calendar)
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        let leading = (calendar.component(.weekday, from: start) + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: start) ?? start
        let cellCount = ((leading + count + 6) / 7) * 7
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        let days = (0..<cellCount).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let entries = (grouped[day] ?? []).sorted {
                $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
            }
            let completed = entries.filter { $0.isCompleted(at: now) }
            let volumes = completed.compactMap(\.volume)
            return Day(date: day, isInMonth: calendar.isDate(day, equalTo: start, toGranularity: .month),
                       sessions: entries, completedCount: completed.count,
                       minutes: completed.reduce(0) { $0 + ($1.endDate!.timeIntervalSince($1.date) / 60) },
                       volume: volumes.isEmpty ? nil : volumes.reduce(0, +))
        }
        return Month(start: start, days: days)
    }
}
