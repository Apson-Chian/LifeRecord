import Foundation
import SwiftData

struct AIAgentReply: Codable {
    var answer: String
    var actions: [AIAgentAction] = []

    enum CodingKeys: String, CodingKey { case answer, actions }

    init(answer: String, actions: [AIAgentAction] = []) {
        self.answer = answer
        self.actions = actions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        answer = try values.decode(String.self, forKey: .answer)
        actions = try values.decodeIfPresent([AIAgentAction].self, forKey: .actions) ?? []
    }
}

struct AIAgentAction: Codable, Identifiable {
    var id = UUID()
    var type: String
    var recordID: String?
    var date: String?
    var endDate: String?
    var exercises: [WorkoutExercise]?
    var bodyParts: [String]?
    var bodyPart: String?
    var clearBodyPart: Bool?
    var mealKind: String?
    var source: String?
    var name: String?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var clearBodyFat: Bool?
    var clearWaist: Bool?
    var displayName: String?
    var fitnessGoal: String?
    var height: Double?
    var baselineWeight: Double?
    var weeklyWeightTarget: Double?
    var targetWeight: Double?
    var calorieGoal: Double?
    var proteinGoal: Double?
    var carbsGoal: Double?
    var fatGoal: Double?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case type, recordID, date, endDate, exercises, bodyParts, bodyPart, clearBodyPart, mealKind, source, name, calories, protein, carbs, fat, fiber, weight, bodyFat, waist, clearBodyFat, clearWaist, displayName, fitnessGoal, height, baselineWeight, weeklyWeightTarget, targetWeight, calorieGoal, proteinGoal, carbsGoal, fatGoal, note
    }
}

/// The same gate is used for text and image requests before any record is changed.
enum CoachActionPolicy {
    static func isMutationRequest(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        return ["帮我记录", "帮我记", "记录一下", "记一下", "记到", "记入", "录入", "登记", "保存", "新增", "添加", "修改", "改成", "更新目标", "设置为", "删掉", "删除", "移除"]
            .contains { compact.contains($0) } || compact.hasPrefix("记录")
    }

    static func blockedMessage(for reply: AIAgentReply, writesAllowed: Bool, request: String) -> String? {
        guard !writesAllowed, !reply.actions.isEmpty || isMutationRequest(request) else { return nil }
        return "未保存：当前未开启 AI 写入。请打开输入框上方的“允许 AI 修改记录”，再发送这条记录请求。"
    }
}

/// Converts a validated agent action into the actual meal model used by the app.
enum CoachMealRecorder {
    static let instructions = """
    用户描述已经吃下的食物并明确要求添加、记录或保存到餐食时，必须返回 add_meal，不能只用文字答应或仅提供营养建议。上一轮已描述食物、本轮说“帮我添加到餐食”也属于记录请求，应结合对话生成操作。
    add_meal 必须包含 name、mealKind、calories、protein、carbs、fat、fiber、date；热量单位 kcal，营养单位 g，数值为整餐总量。来源 source 用“AI 估算”。用户没有提供精确营养时，应按已描述的食物和份量作合理估算，并在 note 说明依据和不确定性；份量未说明时可按常见一份估算并注明，不应因缺少精确克数或营养值就拒绝记录。完全不知道吃了什么时先询问。
    餐食未指定时间时使用当前本地时间；指定昨天、午餐等信息时保留对应日期与餐次，不要因缺少精确时分而拒绝新增餐食。仅咨询、计划吃、否认吃过或明确不要记录时，不能新增。answer 只能说明估算或待执行内容，不能声称已保存，实际保存回执由 App 生成。
    """

    @MainActor
    static func makeMeal(from action: AIAgentAction, id: UUID = UUID(), date: Date,
                         photoIDs: [String] = [], inputText: String, conversationID: UUID) -> MealEntry? {
        guard let name = action.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let calories = action.calories, calories.isFinite, calories >= 0,
              [action.protein, action.carbs, action.fat, action.fiber].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
              action.mealKind.map({ MealKind(rawValue: $0) != nil }) ?? true,
              action.source.map({ EntrySource(rawValue: $0) != nil }) ?? true else { return nil }
        guard (try? RecordInput.meal(name: name, calories: calories, protein: action.protein ?? 0,
                                    carbs: action.carbs ?? 0, fat: action.fat ?? 0, fiber: action.fiber ?? 0,
                                    note: action.note ?? "")) != nil else { return nil }
        return MealEntry(id: id, date: date,
                         kind: action.mealKind.flatMap(MealKind.init(rawValue:)) ?? .snack,
                         name: name, calories: calories, protein: action.protein ?? 0,
                         carbs: action.carbs ?? 0, fat: action.fat ?? 0, fiber: action.fiber ?? 0,
                         note: action.note ?? "由 AI 助手按要求记录",
                         source: action.source.flatMap(EntrySource.init(rawValue:)) ?? .ai,
                         photoIDs: photoIDs, inputText: inputText,
                         sourceConversationID: conversationID.uuidString.lowercased())
    }
}
