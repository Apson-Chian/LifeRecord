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
    var revisionAt: Double? = nil
    var revisionID: String? = nil
    private enum CodingKeys: String, CodingKey { case id, effectiveDate, updatedAt, revisionAt, revisionID }
    init(id: String = UUID().uuidString.lowercased(), effectiveDate: String, updatedAt: Double, values: GoalValues) {
        self.id=id; self.effectiveDate=effectiveDate; self.updatedAt=updatedAt; self.values=values
    }
    init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy: CodingKeys.self)
        id=try c.decode(String.self,forKey:.id)
        effectiveDate=try c.decode(String.self,forKey:.effectiveDate)
        updatedAt=try c.decode(Double.self,forKey:.updatedAt)
        revisionAt=try c.decodeIfPresent(Double.self,forKey:.revisionAt)
        revisionID=try c.decodeIfPresent(String.self,forKey:.revisionID)
        values=try GoalValues(from:decoder)
        let numbers=[updatedAt,values.baselineWeight,values.targetWeight,values.weeklyWeightTarget,values.calorieGoal,values.proteinGoal,values.carbsGoal,values.fatGoal]
        guard !id.isEmpty, revisionAt.map({$0.isFinite && (0...4_102_444_800).contains($0)}) ?? true, revisionID.map({!$0.isEmpty}) ?? true, GoalHistory.validDay(effectiveDate), numbers.allSatisfy(\.isFinite), (0...4_102_444_800).contains(updatedAt) else {
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"目标历史格式无效"))
        }
    }
    func encode(to encoder: Encoder) throws {
        try values.encode(to:encoder)
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id);try c.encode(effectiveDate,forKey:.effectiveDate);try c.encode(updatedAt,forKey:.updatedAt)
        try c.encodeIfPresent(revisionAt,forKey:.revisionAt);try c.encodeIfPresent(revisionID,forKey:.revisionID)
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
    static func rank(_ v:GoalVersion)->Double {max(v.updatedAt,v.revisionAt ?? 0)}
    private static func ordered(_ a:GoalVersion,_ b:GoalVersion)->Bool {
        if rank(a) != rank(b) {return rank(a)<rank(b)}
        if (a.revisionID ?? a.id) != (b.revisionID ?? b.id) {return (a.revisionID ?? a.id)<(b.revisionID ?? b.id)}
        return a.id<b.id
    }
    private static func winner(_ items:[GoalVersion])->GoalVersion {
        if items.allSatisfy({$0.effectiveDate==baselineDay}) {
            let revisions=items.filter {$0.revisionAt != nil}
            if !revisions.isEmpty {return revisions.sorted(by:ordered).last!}
            return items.sorted {a,b in a.updatedAt==b.updatedAt ? a.id<b.id : a.updatedAt<b.updatedAt}.first!
        }
        return items.sorted(by:ordered).last!
    }
    static func merge(_ arrays:[GoalVersion]...)->[GoalVersion] {
        Dictionary(grouping:arrays.flatMap {$0},by: \.id).values.map(winner).sorted {a,b in
            a.effectiveDate==b.effectiveDate ? ordered(a,b) : a.effectiveDate<b.effectiveDate
        }
    }
    static func active(_ history:[GoalVersion])->[GoalVersion] {
        Dictionary(grouping:merge(history),by: \.effectiveDate).values.map(winner).sorted {$0.effectiveDate<$1.effectiveDate}
    }
    static func values(on date:Date,current:GoalValues,history:[GoalVersion],calendar:Calendar = .current)->GoalValues {
        let key=dayKey(date,calendar:calendar)
        return (active(history).last {$0.effectiveDate<=key} ?? active(history).first)?.values ?? current
    }
    static func weightStageStart(history:[GoalVersion],on day:Date,calendar:Calendar = .current)->Date? {
        let key=dayKey(day,calendar:calendar)
        var previous:GoalValues?
        var start:String?
        for version in active(history) where version.effectiveDate<=key {
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
        let key=dayKey(date,calendar:calendar)
        let stamp=max(date.timeIntervalSince1970,previousUpdatedAt+0.001,(result.map(rank).max() ?? 0)+0.001)
        let id=active(result).first {$0.effectiveDate==key}?.id ?? UUID().uuidString.lowercased()
        result.append(.init(id:id,effectiveDate:key,updatedAt:stamp,values:next))
        return merge(result)
    }

    static func revised(history:[GoalVersion],expected:GoalVersion,values:GoalValues,day:String,at date:Date = .now,calendar:Calendar = .current)throws->[GoalVersion] {
        guard let actual=active(history).first(where:{$0.id==expected.id}),actual==expected else {
            throw NSError(domain:"GoalHistory",code:1,userInfo:[NSLocalizedDescriptionKey:"该目标记录已更新，请重新打开"])
        }
        guard validDay(day), actual.effectiveDate==baselineDay ? day==baselineDay : day>baselineDay && day<=dayKey(date,calendar:calendar) else {
            throw NSError(domain:"GoalHistory",code:2,userInfo:[NSLocalizedDescriptionKey:"请选择今天或更早的生效日期"])
        }
        guard !active(history).contains(where:{$0.id != actual.id && $0.effectiveDate==day}) else {
            throw NSError(domain:"GoalHistory",code:3,userInfo:[NSLocalizedDescriptionKey:"该日期已有目标记录，请编辑那条记录或选择其他日期"])
        }
        var correction=actual
        correction.values=values;correction.effectiveDate=day
        correction.revisionAt=max(date.timeIntervalSince1970,(history.map(rank).max() ?? 0)+0.001)
        correction.revisionID=UUID().uuidString.lowercased()
        return merge(history,[correction])
    }
}
