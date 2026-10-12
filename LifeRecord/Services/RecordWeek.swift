import Foundation

enum RecordWeek {
    static func calendar(from calendar: Calendar = .current) -> Calendar {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar
    }

    static func start(containing date: Date, calendar: Calendar = .current) -> Date {
        let calendar = self.calendar(from: calendar)
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}
