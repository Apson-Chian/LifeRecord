import Foundation

/// Calendar-day slots shared by marks, tick labels and inspection.
struct DailyChartScale {
    let calendar: Calendar
    let first: Date
    let last: Date
    let domain: ClosedRange<Date>

    init(dates: [Date], start: Date? = nil, end: Date? = nil, now: Date = .now, calendar: Calendar = .current) {
        self.calendar = calendar
        let lower = calendar.startOfDay(for: start ?? dates.min() ?? now)
        let upper = calendar.startOfDay(for: end ?? dates.max() ?? now)
        first = min(lower, upper)
        last = max(lower, upper)
        domain = first...(calendar.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86400))
    }

    func center(of date: Date) -> Date {
        let interval = calendar.dateInterval(of: .day, for: date)!
        return interval.start.addingTimeInterval(interval.duration / 2)
    }

    func barRange(for date: Date) -> ClosedRange<Date> {
        let interval = calendar.dateInterval(of: .day, for: date)!
        return interval.start.addingTimeInterval(interval.duration * 0.18)...interval.start.addingTimeInterval(interval.duration * 0.82)
    }

    var ticks: [Date] {
        let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        let count = min(4, days + 1)
        return (0..<count).map { index in
            center(of: calendar.date(byAdding: .day, value: count == 1 ? 0 : days * index / (count - 1), to: first)!)
        }
    }
    var crossesYear: Bool { calendar.component(.year, from: first) != calendar.component(.year, from: last) }
}
