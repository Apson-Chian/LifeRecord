import Foundation

struct ReminderPreferences: Codable, Equatable {
    static let key = "reminders.preferences"
    var enabled = false
    var meals = true
    var water = false
    var body = false
    var workout = false
    var hour = 21
    var minute = 0
    // Calendar weekday: Sunday = 1.
    var workoutDays = [2, 4, 6]

    static func decode(_ raw: String) -> Self {
        guard let value = try? JSONDecoder().decode(Self.self, from: Data(raw.utf8)),
              (0...23).contains(value.hour), (0...59).contains(value.minute),
              value.workoutDays.allSatisfy({ (1...7).contains($0) }) else { return Self() }
        return value
    }
    var encoded: String { String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }
}

struct ReminderPlan {
    struct Records {
        var meals: [Date] = []
        var water: [Date] = []
        var body: [Date] = []
        var workouts: [Date] = []
    }
    struct Item {
        let id: String
        let date: Date
        let missing: [String]
    }
    static let prefix = "missing-record-"
    static func items(preferences: ReminderPreferences, records: Records, now: Date, calendar: Calendar = .current) -> [Item] {
        guard preferences.enabled else { return [] }
        return (0..<30).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: day), fire > now else { return nil }
            func has(_ dates: [Date]) -> Bool { dates.contains { calendar.isDate($0, inSameDayAs: day) && $0 <= now } }
            var missing: [String] = []
            if preferences.meals && !has(records.meals) { missing.append("餐食") }
            if preferences.water && !has(records.water) { missing.append("饮水") }
            if preferences.body && !has(records.body) { missing.append("身体数据") }
            if preferences.workout && preferences.workoutDays.contains(calendar.component(.weekday, from: day)) && !has(records.workouts) { missing.append("训练") }
            guard !missing.isEmpty else { return nil }
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            let id = prefix + "\(components.year!)-\(components.month!)-\(components.day!)"
            return Item(id: id, date: fire, missing: missing)
        }
    }
}
