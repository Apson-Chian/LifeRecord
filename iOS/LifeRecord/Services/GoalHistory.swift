import Foundation

struct GoalValues: Codable, Equatable {
    var fitnessGoal: String
    var baselineWeight: Double
    var targetWeight: Double
    var weeklyWeightTarget: Double
    var calorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double
}

struct GoalVersion: Codable, Identifiable, Equatable {
    var id: String
    var effectiveDate: String
    var updatedAt: Double
    var values: GoalValues
    private enum CodingKeys: String, CodingKey { case id, effectiveDate, updatedAt }
    init(id: String = UUID().uuidString.lowercased(), effectiveDate: String, updatedAt: Double, values: GoalValues) {
        self.id=id; self.effectiveDate=effectiveDate; self.updatedAt=updatedAt; self.values=values
    }
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy: CodingKeys.self)
        id=try c.decode(String.self,forKey:.id)
        effectiveDate=try c.decode(String.self,forKey:.effectiveDate)
        updatedAt=try c.decode(Double.self,forKey:.updatedAt)
        values=try GoalValues(from:decoder)
        let numbers=[updatedAt,values.baselineWeight,values.targetWeight,values.weeklyWeightTarget,values.calorieGoal,values.proteinGoal,values.carbsGoal,values.fatGoal]
        guard !id.isEmpty, GoalHistory.validDay(effectiveDate), numbers.allSatisfy(\.isFinite), (0...4_102_444_800).contains(updatedAt) else {
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"目标历史格式无效"))
        }
    }
    func encode(to encoder: Encoder) throws {
        try values.encode(to:encoder)
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id);try c.encode(effectiveDate,forKey:.effectiveDate);try c.encode(updatedAt,forKey:.updatedAt)
    }
}

enum GoalHistory {
    static let baselineDay="1970-01-01"
    static func dayKey(_ date:Date,calendar:Calendar = .current)->String {
        // Use a Gregorian civil day regardless of the user's display calendar.
        var c=Calendar(identifier:.gregorian);c.timeZone=calendar.timeZone
        let parts=c.dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",parts.year!,parts.month!,parts.day!)
    }
    static func validDay(_ day:String)->Bool {
        guard day.count==10,day>=baselineDay else {return false}
        let parts=day.split(separator:"-").compactMap {Int($0)}
        guard parts.count==3 else {return false}
        var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(secondsFromGMT:0)!
        guard let date=c.date(from:DateComponents(year:parts[0],month:parts[1],day:parts[2])) else {return false}
        return dayKey(date,calendar:c)==day
    }
    static func date(for day:String,calendar:Calendar = .current)->Date? {
        guard validDay(day) else {return nil}
        let parts=day.split(separator:"-").compactMap {Int($0)}
        var c=Calendar(identifier:.gregorian);c.timeZone=calendar.timeZone
        return c.date(from:DateComponents(year:parts[0],month:parts[1],day:parts[2]))
    }
    static func merge(_ arrays:[GoalVersion]...)->[GoalVersion] {
        Dictionary(grouping:arrays.flatMap {$0},by: \.effectiveDate).compactMap {day,items in
            let sorted=items.sorted {a,b in a.updatedAt==b.updatedAt ? a.id<b.id : a.updatedAt<b.updatedAt}
            return day==baselineDay ? sorted.first : sorted.last
        }.sorted {$0.effectiveDate<$1.effectiveDate}
    }
    static func values(on date:Date,current:GoalValues,history:[GoalVersion],calendar:Calendar = .current)->GoalValues {
        let key=dayKey(date,calendar:calendar)
        return (history.filter {$0.effectiveDate<=key}.max {$0.effectiveDate<$1.effectiveDate} ?? history.min {$0.effectiveDate<$1.effectiveDate})?.values ?? current
    }
    static func weightStageStart(history:[GoalVersion],on day:Date,calendar:Calendar = .current)->Date? {
        let key=dayKey(day,calendar:calendar)
        var previous:GoalValues?
        var start:String?
        for version in history.sorted(by:{$0.effectiveDate<$1.effectiveDate}) where version.effectiveDate<=key {
            let v=version.values
            if previous?.fitnessGoal != v.fitnessGoal || previous?.baselineWeight != v.baselineWeight || previous?.targetWeight != v.targetWeight || previous?.weeklyWeightTarget != v.weeklyWeightTarget {start=version.effectiveDate==baselineDay ? nil : version.effectiveDate}
            previous=v
        }
        return start.flatMap {date(for:$0,calendar:calendar)}
    }
    static func changed(from previous:GoalValues,to next:GoalValues,history:[GoalVersion],previousUpdatedAt:Double,at date:Date = .now,calendar:Calendar = .current)->[GoalVersion] {
        guard previous != next else {return history}
        var result=history
        if result.isEmpty {result.append(.init(id:"baseline",effectiveDate:baselineDay,updatedAt:previousUpdatedAt,values:previous))}
        result.append(.init(effectiveDate:dayKey(date,calendar:calendar),updatedAt:date.timeIntervalSince1970,values:next))
        return merge(result)
    }
}
