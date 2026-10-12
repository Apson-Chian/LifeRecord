import Foundation

@main
struct BodyTrendChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        func sample(_ day: Int, _ hour: Int, _ value: Double) -> BodyTrend.Sample {
            .init(date: calendar.date(byAdding: .hour, value: day * 24 + hour, to: start)!, value: value)
        }
        let samples = [sample(0, 8, 70), sample(0, 12, 71), sample(0, 20, 90), sample(1, 8, 72), sample(4, 8, 74)]
        let points = BodyTrend.series(samples.reversed(), calendar: calendar)
        assert(points.count == 3 && points[0].count == 3)
        assert(points[0].value == 71 && points[0].trend == 71)
        assert(abs(points[1].trend - 71.1) < 0.000001)
        assert(abs(points[2].trend - (71.1 + (1 - pow(0.9, 3)) * 2.9)) < 0.000001)
        assert(BodyTrend.series([], calendar: calendar).isEmpty)
        let even = BodyTrend.series([sample(0, 8, 20), sample(0, 9, 22)], calendar: calendar)
        assert(even[0].value == 21)
        let invalid = BodyTrend.series([sample(0, 8, .nan), sample(1, 8, 0), sample(2, 8, .infinity)], calendar: calendar)
        assert(invalid.isEmpty)
        // Missing body-fat days stay missing, rather than becoming zero or borrowing weight data.
        let fat = BodyTrend.series([sample(0, 8, 20), sample(4, 8, 21)], calendar: calendar)
        assert(fat.count == 2 && fat[1].value == 21)
        // A UTC date on the prior day still belongs to this local day.
        assert(points[0].date == start)
        for hour in 0..<24 {
            let date = sample(0, hour, 70).date
            let matching = BodyTrend.Period.allCases.filter { $0 != .all && $0.includes(date, calendar: calendar) }
            assert(matching.count == 1)
            assert(BodyTrend.Period.morning.includes(date, calendar: calendar) == (5..<12).contains(hour))
            assert(BodyTrend.Period.evening.includes(date, calendar: calendar) == (18..<24).contains(hour))
        }
        let morning = samples.filter { BodyTrend.Period.morning.includes($0.date, calendar: calendar) }
        assert(BodyTrend.series(morning, calendar: calendar)[0].value == 70)
        print("BodyTrend: all checks passed")
    }
}
