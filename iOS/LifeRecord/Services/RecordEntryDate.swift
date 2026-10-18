import Foundation

enum RecordEntryDate {
    /// Keep the selected recording day, but take the clock time when the form opens.
    static func initial(on day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let clock = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(
            bySettingHour: clock.hour ?? 0,
            minute: clock.minute ?? 0,
            second: clock.second ?? 0,
            of: day
        ) ?? day
    }
}
