import Foundation

@main
struct WorkoutSummaryTests {
    static func main() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let now = start.addingTimeInterval(7200)
        let completed = WorkoutSummary.Record(date: start, endDate: start.addingTimeInterval(3600), note: "深蹲 4×8\n卧推 3×10")
        let active = WorkoutSummary.Record(date: start.addingTimeInterval(5400), endDate: nil, note: "慢跑")
        let future = WorkoutSummary.Record(date: now.addingTimeInterval(100), endDate: nil, note: "future")
        let result = WorkoutSummary.context([completed, active, future], now: now)
        assert(result.contains("已完成 1 次，累计 60.0 分钟；进行中 1 次"))
        assert(result.contains("已用=30.0分钟"))
        assert(result.contains("深蹲 4×8") && result.contains("卧推 3×10"))
        assert(result.contains("尚未结束") && result.contains("结束="))
        assert(!result.contains("future"))
        assert(WorkoutSummary.context([], now: now).contains("不代表用户没有运动"))
        print("PASS: workout AI context includes content, times, duration, ongoing state and empty-state semantics")
    }
}
