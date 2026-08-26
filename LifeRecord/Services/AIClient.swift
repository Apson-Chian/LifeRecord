import Foundation

struct AIChatMessage: Codable {
    let role: String
    let content: String
}

enum MealScanMode: String, CaseIterable, Identifiable {
    case meal = "餐盘识别"
    case nutritionLabel = "营养成分表"
    case ingredients = "配料表"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .meal: "fork.knife"
        case .nutritionLabel: "list.clipboard"
        case .ingredients: "text.viewfinder"
        }
    }
    var instruction: String {
        switch self {
        case .meal:
            "多张图片可能是同一餐的不同角度。合并判断，不要把同一食物重复计算；估算整餐份量。"
        case .nutritionLabel:
            "图片是包装营养成分表。优先读取每份含量、份数与用户实际食用量；看不清的数字不要编造。"
        case .ingredients:
            "图片是食品配料表或外包装。识别配料、过敏原和可能影响增肌饮食的高糖/高钠信息；若缺少营养表，只能给宽范围估算并明确说明。"
        }
    }
}

struct AIAgentReply: Codable {
    var answer: String
    var actions: [AIAgentAction] = []
}

struct AIAgentAction: Codable, Identifiable {
    var id = UUID()
    var type: String
    var date: String?
    var mealKind: String?
    var name: String?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var waterML: Double?
    var targetWeight: Double?
    var calorieGoal: Double?
    var proteinGoal: Double?
    var carbsGoal: Double?
    var fatGoal: Double?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case type, date, mealKind, name, calories, protein, carbs, fat, fiber, weight, bodyFat, waist, waterML, targetWeight, calorieGoal, proteinGoal, carbsGoal, fatGoal, note
    }
}

enum AIClientError: LocalizedError {
    case missingKey
    case invalidEndpoint
    case invalidResponse
    case server(String)
    case malformedNutrition
    case malformedAgentReply
    case visionNotEnabled
    case tooManyImages(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: "请先在设置中保存 API Key。"
        case .invalidEndpoint: "AI 接口地址无效，请填写完整的 https://…/chat/completions 地址。"
        case .invalidResponse: "AI 返回了无法识别的响应。请检查模型是否兼容 OpenAI Chat Completions。"
        case .server(let message): message
        case .malformedNutrition: "AI 没有返回可用的营养数据，请换一种描述或模型重试。"
        case .malformedAgentReply: "AI 没有按应用代理格式返回结果，请重试或更换模型。"
        case .visionNotEnabled: "当前模型未开启图片能力。请在设置中启用“支持图片输入”，并填写多模态模型名称。"
        case .tooManyImages(let limit): "最多可发送 \(limit) 张图片。"
        }
    }
}

struct AIClient {
    let settings: AppSettings

    func analyzeMeal(description: String, images: [Data], mode: MealScanMode) async throws -> MealDraft {
        let prompt = """
        你是谨慎的营养记录助手。\(mode.instruction)
        用户补充：\(description.isEmpty ? "无" : description)

        只输出 JSON，不要 Markdown：
        {"name":"简短餐食名称","calories":0,"protein":0,"carbs":0,"fat":0,"fiber":0,"note":"识别依据、每份/总份量、配料或不确定性"}
        单位：热量 kcal，其余均为 g。所有数字按用户实际摄入的整份估算。无法判断时给合理范围的中位估计，并在 note 中说明。
        """
        let response = try await complete(
            system: "你负责生成可供用户复核的结构化营养估算。不要提供医疗诊断。",
            user: prompt,
            images: images,
            wantsJSON: true
        )
        guard let data = cleanedJSON(response).data(using: .utf8),
              let draft = try? JSONDecoder().decode(MealDraft.self, from: data) else {
            throw AIClientError.malformedNutrition
        }
        return draft
    }

    func coachText(system: String, messages: [AIChatMessage], images: [Data] = []) async throws -> String {
        let history = messages.suffix(14).map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        return try await complete(system: system, user: history, images: images, wantsJSON: false)
    }

    func agent(system: String, messages: [AIChatMessage], images: [Data] = []) async throws -> AIAgentReply {
        let history = messages.suffix(14).map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        let envelope = """
        \(history)

        只输出 JSON：
        {"answer":"给用户的自然语言回答","actions":[{"type":"add_meal|add_weight|add_water|update_goals","date":"ISO8601 可选","mealKind":"早餐|午餐|晚餐|加餐","name":"可选","calories":0,"protein":0,"carbs":0,"fat":0,"fiber":0,"weight":0,"bodyFat":0,"waist":0,"waterML":0,"targetWeight":0,"calorieGoal":0,"proteinGoal":0,"carbsGoal":0,"fatGoal":0,"note":"可选"}]}
        只有用户明确要求修改或记录数据时才生成 actions。普通问答 actions 必须为空。不得生成删除动作。图片可能是食物、营养表、配料表、训练截图或用户希望你分析的任何内容。
        """
        let response = try await complete(system: system, user: envelope, images: images, wantsJSON: true)
        guard let data = cleanedJSON(response).data(using: .utf8),
              let reply = try? JSONDecoder().decode(AIAgentReply.self, from: data) else {
            throw AIClientError.malformedAgentReply
        }
        return reply
    }

    func testConnection(apiKey: String? = nil) async throws -> String {
        try await complete(
            system: "只做连通性测试。",
            user: "请只回复：连接成功",
            images: [],
            wantsJSON: false,
            apiKeyOverride: apiKey
        )
    }

    private func complete(
        system: String,
        user: String,
        images: [Data],
        wantsJSON: Bool,
        apiKeyOverride: String? = nil
    ) async throws -> String {
        let override = apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiKey = override.isEmpty ? KeychainStore.loadAPIKey(for: settings.provider) : override
        guard !apiKey.isEmpty else { throw AIClientError.missingKey }
        guard let url = URL(string: settings.endpoint), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw AIClientError.invalidEndpoint
        }
        guard images.count <= settings.maxPhotos else { throw AIClientError.tooManyImages(settings.maxPhotos) }
        if !images.isEmpty && !settings.supportsVision { throw AIClientError.visionNotEnabled }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch settings.authStyle {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKey:
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        case .custom:
            let header = settings.customHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !header.isEmpty else { throw AIClientError.server("自定义认证请求头不能为空。") }
            request.setValue(apiKey, forHTTPHeaderField: header)
        }

        var userContent: Any = user
        if !images.isEmpty {
            var parts: [[String: Any]] = [["type": "text", "text": user]]
            for data in images {
                let mime = Self.mimeType(for: data)
                parts.append(["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]])
            }
            userContent = parts
        }

        var body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": system + (settings.customInstructions.isEmpty ? "" : "\n用户自定义指令：\(settings.customInstructions)")],
                ["role": "user", "content": userContent]
            ],
            "temperature": settings.temperature,
            "max_tokens": settings.maxTokens
        ]
        // Dots 的托管接口当前没有在公开文档中声明 response_format；
        // 依靠提示词返回 JSON，避免连接正常却因未知参数被 400 拒绝。
        if wantsJSON && settings.provider != .dots {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            let message = error?["message"] as? String
                ?? payload?["message"] as? String
                ?? payload?["detail"] as? String
                ?? payload?["title"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "未知错误"
            throw AIClientError.server("接口错误 \(http.statusCode)：\(message.prefix(360))")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIClientError.invalidResponse
        }
        if let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        throw AIClientError.invalidResponse
    }

    private func cleanedJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mimeType(for data: Data) -> String {
        guard let first = data.first else { return "image/jpeg" }
        if first == 0x89 { return "image/png" }
        if first == 0x47 { return "image/gif" }
        if data.count > 12,
           let marker = String(data: data[8..<12], encoding: .ascii),
           marker == "WEBP" { return "image/webp" }
        return "image/jpeg"
    }
}
