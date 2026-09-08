import Foundation

/// Pure daily aggregation, shared by charts and reports. Never changes stored measurements.
enum BodyTrend {
    struct Sample {
        let date: Date
        let value: Double
    }
    struct Point: Identifiable {
        let date: Date
        let value: Double
        let trend: Double
        let count: Int
        var id: Date { date }
    }

    static func series(_ samples: [Sample], calendar: Calendar = .current) -> [Point] {
        let groups = Dictionary(grouping: samples.filter { $0.value.isFinite && $0.value > 0 }) {
            calendar.startOfDay(for: $0.date)
        }
        var result: [Point] = []
        for day in groups.keys.sorted() {
            let values = groups[day]!.map(\.value).sorted()
            let middle = values.count / 2
            let median = values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
            var trend = median
            if let previous = result.last {
                let days = max(1, calendar.dateComponents([.day], from: previous.date, to: day).day ?? 1)
                let alpha = 1 - pow(0.9, Double(days))
                trend = previous.trend + alpha * (median - previous.trend)
            }
            result.append(Point(date: day, value: median, trend: trend, count: values.count))
        }
        return result
    }
}
