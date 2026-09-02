import Foundation
import UIKit

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
    var recordID: String?
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
    var waterSource: String?
    var targetWeight: Double?
    var calorieGoal: Double?
    var proteinGoal: Double?
    var carbsGoal: Double?
    var fatGoal: Double?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case type, recordID, date, mealKind, name, calories, protein, carbs, fat, fiber, weight, bodyFat, waist, waterML, waterSource, targetWeight, calorieGoal, proteinGoal, carbsGoal, fatGoal, note
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
    case missingModel

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
        case .missingModel: "AI 模型名称不能为空。请在设置中选择服务商或填写模型名称。"
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
        {"name":"简短餐食名称","calories":0,"protein":0,"carbs":0,"fat":0,"fiber":0,"waterML":0,"note":"识别依据、每份/总份量、配料或不确定性"}
        单位：热量 kcal，waterML 为 ml，其余均为 g。所有数字按用户实际摄入的整份估算。只有画面或文字明确包含一杯/一瓶实际饮用的饮料时，waterML 才可大于 0：白水按实际容量；无糖茶、咖啡、牛奶可按主要液体量；奶茶、含糖饮料按实际液体量谨慎折算，通常为杯体积的 70%–90%；酒精饮料记 0。菜肴、米饭、汤汁、蔬菜、水果本身的含水量不能计入饮水；没有明确饮料时必须为 0。无法判断食物营养时给合理范围的中位估计，并在 note 中说明。
        """
        let response = try await complete(
            system: "你负责生成可供用户复核的结构化营养估算。不要提供医疗诊断。",
            user: prompt,
            images: images,
            wantsJSON: true,
            maxTokensOverride: 700,
            temperatureOverride: 0.1
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
        let currentTime = Self.localISO8601String(from: .now)
        let envelope = """
        \(history)

        当前本地时间：\(currentTime)
        只输出 JSON：
        {"answer":"给用户的自然语言回答","actions":[{"type":"add_meal|add_weight|add_water|update_goals|delete_meal|delete_weight|delete_water","recordID":"删除时必填，必须来自当前记录清单","date":"带时区的 ISO8601，可选","mealKind":"早餐|午餐|晚餐|加餐","name":"可选","calories":0,"protein":0,"carbs":0,"fat":0,"fiber":0,"weight":0,"bodyFat":0,"waterML":0,"waterSource":"仅在明确包含实际饮用的饮料时填写饮料名称","targetWeight":0,"calorieGoal":0,"proteinGoal":0,"carbsGoal":0,"fatGoal":0,"note":"可选"}]}
        只有用户明确要求新增、修改或删除数据时才生成 actions。例外：只要用户发送的图片明显是其实际摄入的餐食或饮料，且没有明确说“只分析/不要记录”，就视为明确的记录请求；必须识别整份餐食、估算营养并返回 add_meal action。配料表、商品包装或菜单图片若无法确认已经摄入，则只分析、不记录。普通问答 actions 必须为空。
        用户指定了日期或时间时必须严格保留，date 输出带本地时区的完整 ISO8601；不要擅自改成当前时间。删除仅在用户明确要求时生成，必须从系统提供的当前记录清单选择准确 recordID；有歧义时 actions 为空，并在 answer 里询问要删哪一条。answer 只能说明计划、需要澄清的内容或结果含义，绝不能声称“已记录”“已更新”“已删除”或“执行成功”；App 会在数据库操作成功后自行给出核验回执。
        图片可能是食物、饮料、营养表、配料表、训练截图或用户希望你分析的任何内容。只有新增餐食中明确包含实际饮用的白水、茶、咖啡、牛奶、奶茶或其他饮料时，才填写 waterSource 并给出 waterML；菜肴、米饭、汤汁、蔬菜、水果本身的水分不能计入饮水，酒精记 0。没有明确饮料时 waterSource 为空且 waterML 为 0。
        """
        let response = try await complete(
            system: system,
            user: envelope,
            images: images,
            wantsJSON: true,
            maxTokensOverride: 1_600
        )
        guard let data = cleanedJSON(response).data(using: .utf8),
              let reply = try? JSONDecoder().decode(AIAgentReply.self, from: data) else {
            throw AIClientError.malformedAgentReply
        }
        return reply
    }

    private static func localISO8601String(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return formatter.string(from: date)
    }

    func testConnection(apiKey: String? = nil) async throws -> String {
        let response = try await complete(
            system: "只做连通性和结构化输出测试。只输出 JSON，不要 Markdown。",
            user: #"{"status":"连接成功"}"#,
            images: [],
            wantsJSON: true,
            apiKeyOverride: apiKey
        )
        guard let data = cleanedJSON(response).data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = payload["status"] as? String,
              !status.isEmpty else {
            throw AIClientError.invalidResponse
        }
        return status
    }

    private func complete(
        system: String,
        user: String,
        images: [Data],
        wantsJSON: Bool,
        apiKeyOverride: String? = nil,
        maxTokensOverride: Int? = nil,
        temperatureOverride: Double? = nil
    ) async throws -> String {
        let override = apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiKey = override.isEmpty ? KeychainStore.loadAPIKey(for: settings.provider) : override
        guard !apiKey.isEmpty else { throw AIClientError.missingKey }
        let endpoint = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AIClientError.missingModel }
        guard let url = URL(string: endpoint), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
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
            for original in images {
                // 相册原图可能是 HEIC；教练页此前能识别，是因为它先压成了 JPEG。
                // 这里统一兜底，保证首页加号、教练页和后续新入口发送的都是 JPEG。
                let data = Self.jpegImageData(forSending: original)
                var imageObject: [String: Any] = ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]
                // Dots 需要 detail 字段；GLM/OpenAI 兼容接口保持最小字段，避免未知参数被拒绝。
                if settings.provider == .dots {
                    imageObject["detail"] = "medium"
                }
                parts.append(["type": "image_url", "image_url": imageObject])
            }
            userContent = parts
        }

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system + (settings.customInstructions.isEmpty ? "" : "\n用户自定义指令：\(settings.customInstructions)")],
                ["role": "user", "content": userContent]
            ],
            "temperature": temperatureOverride ?? settings.temperature,
            "max_tokens": min(max(maxTokensOverride ?? settings.maxTokens, 256), 4_096),
        ]
        // 客户端一次性解码完整回复，明确关闭流式，避免兼容接口修改默认值。
        body["stream"] = false
        if settings.provider == .dots {
            // Dots 的 Chat Completions 接口使用专有参数控制深度思考，默认为开启。
            // 营养 JSON 和 App 操作需要稳定的最终 content，不能让 reasoning 耗尽输出上限。
            body["chat_template_kwargs"] = ["enable_thinking": false]
        } else if settings.provider == .deepSeek || settings.provider == .glm {
            // 结构化营养数据和 App 操作需要稳定的最终答案；深度思考会占用输出预算，
            // 在较短 max_tokens 下可能只返回 reasoning_content 而没有 content。
            body["thinking"] = ["type": "disabled"]
        }
        // Dots 的托管接口当前没有在公开文档中声明 response_format；
        // 依靠提示词返回 JSON，避免连接正常却因未知参数被 400 拒绝。
        // Some multimodal endpoints accept image content but reject JSON response_format.
        // For image requests, rely on the prompt's JSON schema instead.
        if wantsJSON && images.isEmpty && settings.provider != .dots {
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
                ?? payload?["error_type"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "未知错误"
            if settings.provider == .dots && http.statusCode == 401 {
                throw AIClientError.server("Dots API Key 缺失或无效。请粘贴 Dots API 开放平台生成的完整密钥。")
            }
            if settings.provider == .dots && http.statusCode == 403 {
                throw AIClientError.server("Dots 拒绝了当前 API Key：该密钥无权访问 dots3-note-prev。请在 Dots API 开放平台的 API Keys 页面重新创建平台密钥。服务端：\(message.prefix(180))")
            }
            throw AIClientError.server("接口错误 \(http.statusCode)：\(message.prefix(360))")
        }
        guard let content = Self.responseText(from: data), !content.isEmpty else {
            throw AIClientError.invalidResponse
        }
        return content
    }

    private func cleanedJSON(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return cleaned }
        let opening = cleaned[start]
        let closing: Character = opening == "{" ? "}" : "]"
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var cursor = start
        while cursor < cleaned.endIndex {
            let character = cleaned[cursor]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 { return String(cleaned[start...cursor]) }
            }
            cursor = cleaned.index(after: cursor)
        }
        return cleaned
    }

    /// Accepts OpenAI Chat Completions, OpenAI Responses-style output, provider wrappers,
    /// and servers that return SSE despite `stream: false`.
    nonisolated static func responseText(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let text = extractResponseText(object)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let chunks = raw.split(whereSeparator: \Character.isNewline).compactMap { line -> String? in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.hasPrefix("data:") else { return nil }
            let payload = value.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let chunkData = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: chunkData) else { return nil }
            return extractResponseText(object)
        }
        let joined = chunks.joined()
        if !joined.isEmpty { return joined.trimmingCharacters(in: .whitespacesAndNewlines) }
        let plain = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty || plain.hasPrefix("<") ? nil : plain
    }

    nonisolated private static func extractResponseText(_ value: Any) -> String? {
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let values = value as? [Any] {
            let text = values.compactMap(extractResponseText).joined()
            return text.isEmpty ? nil : text
        }
        guard let object = value as? [String: Any] else { return nil }

        if let choices = object["choices"] as? [Any] {
            for choice in choices {
                guard let dictionary = choice as? [String: Any] else { continue }
                for key in ["message", "delta", "text"] {
                    if let nested = dictionary[key], let text = extractResponseText(nested), !text.isEmpty { return text }
                }
            }
        }
        for key in ["output_text", "answer", "result", "message", "content", "output", "data", "text"] {
            if let nested = object[key], let text = extractResponseText(nested), !text.isEmpty { return text }
        }
        if (object["name"] != nil || object["actions"] != nil),
           JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return nil
    }

    /// 统一转成 JPEG 再发送：相册原图可能是 HEIC，多模态接口普遍只接受 JPEG/PNG/WebP。
    static func jpegImageData(forSending data: Data, maxDimension: CGFloat = 1600) -> Data {
        if isJPEG(data), let image = UIImage(data: data) {
            let longest = max(image.size.width, image.size.height)
            if longest <= maxDimension { return data }
        }
        guard let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: 0.82) ?? data }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8) ?? data
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0xFF && data[data.index(after: data.startIndex)] == 0xD8
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
