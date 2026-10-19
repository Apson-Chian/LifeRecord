import Foundation

@main struct DailyChartScaleChecks {
    static func main() {
        var calendar=Calendar(identifier:.gregorian)
        let iso=ISO8601DateFormatter()
        func date(_ s:String)->Date {iso.date(from:s)!}
        calendar.timeZone=TimeZone(identifier:"Asia/Shanghai")!
        let one=date("2026-10-19T00:00:00+08:00")
        let single=DailyChartScale(dates:[one],calendar:calendar)
        precondition(single.ticks.count==1 && single.center(of:one)==date("2026-10-19T12:00:00+08:00"))
        precondition(single.domain.upperBound==date("2026-10-20T00:00:00+08:00"))
        let sparse=DailyChartScale(dates:[date("2026-10-01T00:00:00+08:00"),one],end:one,calendar:calendar)
        precondition(sparse.ticks.count==4 && Set(sparse.ticks).count==4)
        precondition(calendar.isDate(sparse.ticks.last!,inSameDayAs:one))
        for tick in sparse.ticks {precondition(calendar.component(.hour,from:tick)==12)}
        let cross=DailyChartScale(dates:[date("2026-12-30T00:00:00+08:00"),date("2027-01-02T00:00:00+08:00")],calendar:calendar)
        precondition(cross.crossesYear)
        calendar.timeZone=TimeZone(identifier:"America/New_York")!
        for day in [date("2026-03-08T00:00:00-05:00"),date("2026-11-01T00:00:00-04:00")] {
            let scale=DailyChartScale(dates:[day],calendar:calendar)
            precondition(calendar.isDate(scale.center(of:day),inSameDayAs:day))
            precondition(scale.barRange(for:day).lowerBound>scale.domain.lowerBound && scale.barRange(for:day).upperBound<scale.domain.upperBound)
            precondition(scale.domain.upperBound.timeIntervalSince(scale.domain.lowerBound) != 86400)
        }
        print("PASS: daily chart slots, sparse days, final day, unique ticks, year boundaries and DST")
    }
}
