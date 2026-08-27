import Foundation
import SwiftData

@MainActor
enum DemoDataService {
    private static let versionKey = "LifeRecordDemoDataVersion"
    private static let currentVersion = 2

    static var hasInstalledDemoData: Bool {
        UserDefaults.standard.integer(forKey: versionKey) >= currentVersion
    }

    static func installIfNeeded(context: ModelContext) {
        guard !hasInstalledDemoData else { return }
        reinstall(context: context)
    }

    static func reinstall(context: ModelContext) {
        clear(context: context)
        insertComprehensiveDemoData(context: context)
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }

    static func clear(context: ModelContext) {
        let meals = (try? context.fetch(FetchDescriptor<MealEntry>())) ?? []
        let metrics = (try? context.fetch(FetchDescriptor<BodyMetric>())) ?? []
        let water = (try? context.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let conversations = (try? context.fetch(FetchDescriptor<CoachConversation>())) ?? []

        meals.filter(\.isDemo).forEach(context.delete)
        metrics.filter(\.isDemo).forEach(context.delete)
        water.filter(\.isDemo).forEach(context.delete)
        conversations.filter(\.isDemo).forEach(context.delete)
        try? context.save()
    }

    private static func insertComprehensiveDemoData(context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // 30 天完整身体指标：体重与体脂。
        for offset in (0..<30).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let progress = Double(29 - offset)
            let wave = sin(Double(offset) / 3.4) * 0.12
            let weight = 64.0 + progress * 0.035 + wave
            let bodyFat = 14.6 - progress * 0.012 + cos(Double(offset) / 4.2) * 0.08
            context.insert(BodyMetric(
                date: calendar.date(bySettingHour: 7, minute: 40, second: 0, of: day) ?? day,
                weight: weight,
                bodyFat: bodyFat,
                note: "[示例] 晨起空腹测量",
                isDemo: true
            ))
        }

        // 30 天完整饮食与饮水，偶尔留一个缺口用于展示记录连续性。
        for offset in (0..<30).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let progress = Double(29 - offset)
            let trainingDay = offset % 3 != 2
            let skippedDinner = offset == 10

            let breakfast = MealEntry(
                date: calendar.date(bySettingHour: 7, minute: 50, second: 0, of: day) ?? day,
                kind: .breakfast,
                name: offset % 2 == 0 ? "燕麦鸡蛋牛奶碗" : "全麦面包煎蛋拿铁",
                calories: offset % 2 == 0 ? 545 : 505,
                protein: offset % 2 == 0 ? 34 : 30,
                carbs: offset % 2 == 0 ? 64 : 57,
                fat: offset % 2 == 0 ? 15 : 14,
                fiber: 8,
                note: "[示例] 早餐",
                isDemo: true
            )

            let lunchCalories = trainingDay ? 780.0 : 700.0
            let lunch = MealEntry(
                date: calendar.date(bySettingHour: 12, minute: 20, second: 0, of: day) ?? day,
                kind: .lunch,
                name: offset % 3 == 0 ? "鸡胸肉糙米饭" : (offset % 3 == 1 ? "牛肉面" : "虾仁杂粮饭"),
                calories: lunchCalories,
                protein: trainingDay ? 56 : 47,
                carbs: trainingDay ? 88 : 77,
                fat: trainingDay ? 19 : 17,
                fiber: 7,
                note: "[示例] 午餐",
                isDemo: true
            )

            context.insert(breakfast)
            context.insert(lunch)

            if !skippedDinner {
                let dinner = MealEntry(
                    date: calendar.date(bySettingHour: 19, minute: 10, second: 0, of: day) ?? day,
                    kind: .dinner,
                    name: offset % 2 == 0 ? "三文鱼藜麦沙拉" : "鸡腿肉红薯西兰花",
                    calories: offset % 2 == 0 ? 665 : 690,
                    protein: offset % 2 == 0 ? 47 : 50,
                    carbs: offset % 2 == 0 ? 58 : 66,
                    fat: offset % 2 == 0 ? 24 : 21,
                    fiber: 10,
                    note: "[示例] 晚餐",
                    isDemo: true
                )
                context.insert(dinner)
            }

            if trainingDay {
                let snack = MealEntry(
                    date: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: day) ?? day,
                    kind: .snack,
                    name: offset % 2 == 0 ? "蛋白棒与香蕉" : "酸奶蓝莓坚果",
                    calories: offset % 2 == 0 ? 285 : 310,
                    protein: offset % 2 == 0 ? 24 : 22,
                    carbs: offset % 2 == 0 ? 35 : 33,
                    fat: offset % 2 == 0 ? 8 : 10,
                    fiber: 5,
                    note: "[示例] 训练日加餐",
                    isDemo: true
                )
                context.insert(snack)
            }

            for (hour, amount) in [(9, 400), (13, 500), (17, 450), (20, 550)] {
                let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                let adjusted = Double(amount) + sin(progress / 5.0) * 70
                context.insert(WaterEntry(date: date, milliliters: max(300, adjusted), isDemo: true))
            }
        }

        insertConversation(
            context: context,
            title: "[示例] 增肌饮食复盘",
            updatedAt: .now,
            user: "最近一个月体重和热量怎么样？",
            assistant: """
            ## 近 30 天趋势
            - **体重**：从约 64.0kg 增至 65.0kg，增幅约 1.0kg。
            - **体脂率**：约 14.6% 降至 14.2%，波动不大。
            - **热量**：训练日约 2,700kcal，休息日约 2,300kcal。

            ### 建议
            1. 保持当前热量盈余，不需要额外大幅加餐。
            2. 训练日把更多碳水安排在训练前后。
            3. 继续观察 7 日平均体重，而不是单日波动。
            """
        )

        insertConversation(
            context: context,
            title: "[示例] 训练日加餐",
            updatedAt: .now.addingTimeInterval(-60 * 60 * 20),
            user: "训练日应该怎么安排加餐？",
            assistant: """
            ## 训练日加餐
            - **训练前 60–90 分钟**：易消化碳水，例如香蕉或白面包。
            - **训练后 30 分钟内**：蛋白质加碳水，例如乳清蛋白与香蕉。
            - **热量调整**：训练日可比休息日多 300kcal 左右。

            如果当天已经达到热量目标，不必强行加餐。
            """
        )

        insertConversation(
            context: context,
            title: "[示例] 饮水与恢复",
            updatedAt: .now.addingTimeInterval(-60 * 60 * 48),
            user: "最近饮水和恢复怎么样？",
            assistant: """
            ## 饮水与恢复
            - 最近 30 天日均饮水约 **1,900ml**，接近 2,000ml。
            - 训练日饮水略高，休息日略低。
            - 若训练时间超过 75 分钟，可考虑补充电解质。

            ### 执行
            把最大的一杯水固定在训练前后，比分散到处补更有效。
            """
        )

        try? context.save()
    }

    private static func insertConversation(
        context: ModelContext,
        title: String,
        updatedAt: Date,
        user: String,
        assistant: String
    ) {
        let conversation = CoachConversation(
            title: title,
            createdAt: updatedAt.addingTimeInterval(-60 * 60 * 24 * 7),
            updatedAt: updatedAt,
            isDemo: true
        )
        context.insert(conversation)

        let userMessage = CoachMessage(
            date: updatedAt.addingTimeInterval(-60),
            role: "user",
            content: user
        )
        userMessage.conversation = conversation
        context.insert(userMessage)

        let assistantMessage = CoachMessage(
            date: updatedAt,
            role: "assistant",
            content: assistant
        )
        assistantMessage.conversation = conversation
        context.insert(assistantMessage)
    }
}
