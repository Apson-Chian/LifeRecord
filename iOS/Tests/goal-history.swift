import Foundation

@main struct GoalHistoryChecks {
    static func main() throws {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Asia/Shanghai")!
        let today=GoalHistory.date(for:"2026-10-22",calendar:calendar)!.addingTimeInterval(12*3600)
        let yesterday=calendar.date(byAdding:.day,value:-1,to:today)!
        let original=GoalValues(fitnessGoal:"维持",baselineWeight:70,targetWeight:70,weeklyWeightTarget:0,calorieGoal:2000,proteinGoal:100,carbsGoal:250,fatGoal:60)
        var next=original;next.proteinGoal=150;next.calorieGoal=2400
        let history=GoalHistory.changed(from:original,to:next,history:[],previousUpdatedAt:1,at:today,calendar:calendar)
        precondition(history.count==2)
        precondition(GoalHistory.weightStageStart(history:history,on:today,calendar:calendar)==nil)
        precondition(GoalHistory.values(on:yesterday,current:next,history:history,calendar:calendar)==original)
        precondition(GoalHistory.values(on:today,current:next,history:history,calendar:calendar)==next)
        precondition(GoalHistory.values(on:today.addingTimeInterval(86400),current:next,history:history,calendar:calendar)==next)
        var second=next;second.proteinGoal=180
        let revised=GoalHistory.changed(from:next,to:second,history:history,previousUpdatedAt:today.timeIntervalSince1970,at:today.addingTimeInterval(10),calendar:calendar)
        precondition(revised.count==2 && revised.last!.values.proteinGoal==180)
        precondition(GoalHistory.values(on:yesterday,current:second,history:revised,calendar:calendar).proteinGoal==100)
        let early=GoalHistory.changed(from:original,to:next,history:[],previousUpdatedAt:1,at:yesterday,calendar:calendar)
        precondition(GoalHistory.merge(revised,early)==GoalHistory.merge(early,revised))
        precondition(GoalHistory.merge(revised,early).count==3)
        let goals=GoalFeedback.Goals(mode:.maintain,baselineWeight:70,targetWeight:70,weeklyWeightChange:0,calories:2400,protein:150,history:history)
        let meals=[today,yesterday].map {InsightRecords.Meal(date:$0,name:"当天记录",calories:2000,protein:100)}
        let summary=GoalFeedback.summarize(goals:goals,meals:meals,body:[],workouts:[],days:7,now:today,calendar:calendar)
        precondition(summary.mealDays==2 && summary.calorieGoalDays==1 && summary.proteinGoalDays==1)
        let decoded=try JSONDecoder().decode([GoalVersion].self,from:JSONEncoder().encode(history))
        precondition(decoded==history)
        let fixture=URL(fileURLWithPath:"../Android/app/build/outputs/tests/goal-history.json")
        if FileManager.default.fileExists(atPath:fixture.path) {
            let profile=try JSONDecoder().decode(SyncedProfile.self,from:Data(contentsOf:fixture))
            precondition(profile.goalHistory?.count==2 && profile.goalHistory?.last?.values.proteinGoal==150)
            if CommandLine.arguments.count>1 {try JSONEncoder().encode(profile).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}
        }
        print("PASS: dated goals preserve closed historical rings, same-day edits, offline unions, daily feedback and Kotlin/Swift wire compatibility")
    }
}
