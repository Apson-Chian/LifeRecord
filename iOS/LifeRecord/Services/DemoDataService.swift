import Foundation
import SwiftData

@MainActor
enum DemoDataService {
    private static let versionKey = "LifeRecordDemoDataVersion"
    private static let currentVersion = 3

    static var hasInstalledDemoData: Bool {
        UserDefaults.standard.integer(forKey: versionKey) >= currentVersion
    }

    static func installIfNeeded(context: ModelContext) {
        guard !hasInstalledDemoData else { return }
        reinstall(context: context)
    }

    /// Replace only marked examples, in one save. Never change the user's goals.
    @discardableResult
    static func reinstall(context: ModelContext, now: Date = .now, preferences: UserDefaults = .standard) -> Bool {
        guard !context.hasChanges else { return false }
        do {
            try deleteExamples(context: context)
            insertExamples(context: context, now: now)
            try context.save()
            preferences.set(currentVersion, forKey: versionKey)
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    @discardableResult
    static func clear(context: ModelContext, preferences: UserDefaults = .standard) -> Bool {
        guard !context.hasChanges else { return false }
        do {
            try deleteExamples(context: context)
            try context.save()
            preferences.removeObject(forKey: versionKey)
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    private static func deleteExamples(context: ModelContext) throws {
        try context.fetch(FetchDescriptor<MealEntry>()).filter(\.isDemo).forEach(context.delete)
        try context.fetch(FetchDescriptor<BodyMetric>()).filter(\.isDemo).forEach(context.delete)
        try context.fetch(FetchDescriptor<WorkoutEntry>()).filter(\.isDemo).forEach(context.delete)
        try context.fetch(FetchDescriptor<CoachConversation>()).filter(\.isDemo).forEach(context.delete)
    }

    private static func insertExamples(context: ModelContext, now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for offset in (0..<30).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            func time(_ hour: Int, _ minute: Int = 0) -> Date {
                min(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day, now)
            }
            let progress = Double(29 - offset)
            // Missing measurements are intentional: a gap is never a zero value.
            if offset != 9 && offset != 18 {
                context.insert(BodyMetric(date: time(7, 20),
                    weight: 64 + progress * 0.035 + sin(Double(offset) / 3.4) * 0.18,
                    bodyFat: offset % 4 == 1 ? nil : 14.6 - progress * 0.012,
                    waist: offset % 3 == 0 ? 76 - progress * 0.018 : nil,
                    note: "[示例] 晨起测量 · 数值仅用于体验", isDemo: true))
            }
            if offset != 11 {
                let trainingDay = offset % 3 != 2
                let menu: [(MealKind, String, Int, Double, Double, Double, Double)] = [
                    (.breakfast, offset % 2 == 0 ? "燕麦鸡蛋牛奶碗" : "全麦面包煎蛋", 8, 34, 64, 15, 8),
                    (.lunch, offset % 2 == 0 ? "鸡胸肉糙米饭" : "虾仁杂粮饭", 12, trainingDay ? 52 : 45, trainingDay ? 88 : 72, 19, 7),
                    (.dinner, offset % 2 == 0 ? "三文鱼藜麦沙拉" : "鸡腿红薯西兰花", 19, 47, 58, 24, 10),
                    (.snack, "酸奶蓝莓坚果", 16, 22, 33, 10, 5)
                ]
                for (kind, name, hour, protein, carbs, fat, fiber) in menu {
                    if kind == .snack && !trainingDay { continue }
                    if kind == .dinner && offset == 10 { continue }
                    context.insert(MealEntry(date: time(hour), kind: kind, name: name,
                        calories: protein * 4 + carbs * 4 + fat * 9,
                        protein: protein, carbs: carbs, fat: fat, fiber: fiber,
                        note: "[示例] 合成餐食，可点开查看营养明细", isDemo: true))
                }
            }
            if offset % 3 != 2 {
                let duration = Double(40 + offset % 4 * 5) * 60
                let end = time(18, 50)
                let start = end.addingTimeInterval(-duration)
                let workout = WorkoutEntry(date: start, endDate: end,
                    note: "[示例] \(offset % 3 == 0 ? "力量训练 · 查看动作与逐组记录" : "有氧与核心 · 查看计时记录")", isDemo: true)
                if offset % 3 == 0 {
                    workout.bodyParts = ["胸部", "三头"]
                    workout.exercises = [
                        WorkoutExercise(name: "哑铃卧推", sets: (0..<3).map { index in
                            WorkoutSet(reps: 12 - index * 2, weight: 12 + Double((29 - offset) / 10) * 2)
                        }, bodyPart: "胸部"),
                        WorkoutExercise(name: "绳索下压", sets: [WorkoutSet(reps: 12, weight: 15), WorkoutSet(reps: 10, weight: 15)], bodyPart: "三头")
                    ]
                } else {
                    workout.bodyParts = ["有氧", "核心"]
                    workout.exercises = [
                        WorkoutExercise(name: "椭圆机", sets: [WorkoutSet(durationSeconds: 1800)], bodyPart: "有氧"),
                        WorkoutExercise(name: "平板支撑", sets: [WorkoutSet(durationSeconds: 45), WorkoutSet(durationSeconds: 40)], bodyPart: "核心")
                    ]
                }
                context.insert(workout)
            }
        }
        conversation(context, title: "[示例] 看懂一个月的记录", at: now,
            question: "这些趋势和训练记录怎么看？",
            answer: "这是预先写好的示例回答，不是实时 AI 分析。\n\n在「趋势」切换近 7 天或近 30 天，查看体重、体脂、每日热量与训练时长。点进训练日历，可以查看部位、动作和每组记录。空白日期表示未记录。\n\n这些都是合成数据，不代表你的身体情况，也不计入真实目标反馈或 AI 周报。")
        conversation(context, title: "[示例] 从第一餐开始", at: now.addingTimeInterval(-120),
            question: "我该怎样开始记录？",
            answer: "这是预先写好的使用示例。\n\n1. 在「今日」点添加，手动记一餐或一次测量。\n2. 训练时点「开始训练」，结束后可补充动作和组数。\n3. 在「设置」填写自己的目标，需要时再连接同步与 AI 服务。\n\n示例可随时在设置中清除；清除后，你自己的记录会保留。")
    }

    private static func conversation(_ context: ModelContext, title: String, at: Date, question: String, answer: String) {
        let conversation = CoachConversation(title: title, createdAt: at.addingTimeInterval(-60), updatedAt: at, isDemo: true)
        context.insert(conversation)
        for (role, content, date) in [("user", question, at.addingTimeInterval(-60)), ("assistant", answer, at)] {
            let message = CoachMessage(date: date, role: role, content: content)
            message.conversation = conversation
            context.insert(message)
        }
    }
}
