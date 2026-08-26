import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct CoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WaterEntry.date) private var waterEntries: [WaterEntry]

    @State private var input = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imageData: [Data] = []
    @State private var isLoadingPhotos = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var confirmsClear = false
    @FocusState private var composerFocused: Bool

    private let suggestions = ["帮我记录今天晨重 64.2kg", "分析今天是否适合加餐", "看这张配料表是否适合增肌"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            coachIntro
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            if isSending {
                                HStack(spacing: 9) {
                                    ProgressView()
                                    Text("正在读取记录并执行请求…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                                .id("sending")
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in
                        guard let id = messages.last?.id else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 1)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                    .onChange(of: isSending) { _, sending in
                        if sending {
                            withAnimation(.spring(response: 0.35, dampingFraction: 1)) {
                                proxy.scrollTo("sending", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("AI 助手")
            .toolbar {
                if !messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { confirmsClear = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("清空对话")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { composerFocused = false }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("清空全部对话？", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { messages.forEach(modelContext.delete) }
                Button("取消", role: .cancel) { }
            } message: {
                Text("体重、餐食和饮水记录不会受影响。")
            }
            .alert("暂时无法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var coachIntro: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.sparkles")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.23), AppTheme.accentSoft.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.aiCanWrite ? "能回答，也能替你记录" : "只读分析模式")
                            .font(.headline)
                        Text(settings.supportsVision
                             ? "可以发送食物、配料表、营养表或其他图片。"
                             : "当前模型未开启图片输入，可在设置中调整。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if settings.aiCanWrite {
                    Label("新增和调整操作会在回复中列明；删除数据仍由你确认。", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                input = suggestion
                                composerFocused = true
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var composer: some View {
        let visionEnabled = settings.supportsVision
        return VStack(spacing: 8) {
            if !imageData.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(Array(imageData.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 66, height: 66)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                    Button { removePhoto(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.7))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }
                .scrollIndicators(.hidden)
            }

            HStack(alignment: .bottom, spacing: 9) {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: settings.maxPhotos,
                    selectionBehavior: .ordered,
                    matching: .images
                ) {
                    ZStack {
                        Circle().fill(Color(.secondarySystemBackground))
                        if isLoadingPhotos {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.headline)
                                .foregroundStyle(visionEnabled ? AppTheme.accent : .secondary)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .disabled(isSending || !visionEnabled)
                .onChange(of: photoItems) { _, items in Task { await loadPhotos(items) } }
                .accessibilityLabel("添加图片")

                TextField("问问题，或让我替你记录…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { if canSend { Task { await send() } } }

                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(canSend ? AppTheme.accent : Color.secondary, in: Circle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(!canSend)
                .accessibilityLabel("发送")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !isSending && !isLoadingPhotos && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageData.isEmpty)
    }

    @MainActor
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        composerFocused = false
        let attachedImages = imageData
        let displayText = text.isEmpty
            ? "[发送了 \(attachedImages.count) 张图片]"
            : (attachedImages.isEmpty ? text : "\(text)\n[附带 \(attachedImages.count) 张图片]")
        let outgoingHistory = messages.map { AIChatMessage(role: $0.role, content: $0.content) }
            + [AIChatMessage(role: "user", content: text.isEmpty ? "请分析我发送的图片。" : text)]

        input = ""
        photoItems = []
        imageData = []
        modelContext.insert(CoachMessage(role: "user", content: displayText))
        isSending = true
        defer { isSending = false }

        do {
            let client = AIClient(settings: settings)
            if settings.aiCanWrite {
                let reply = try await client.agent(system: systemContext, messages: outgoingHistory, images: attachedImages)
                let receipts = try apply(reply.actions)
                let content = receipts.isEmpty ? reply.answer : reply.answer + "\n\n已执行\n" + receipts.map { "• \($0)" }.joined(separator: "\n")
                modelContext.insert(CoachMessage(role: "assistant", content: content))
            } else {
                let response = try await client.coachText(system: systemContext, messages: outgoingHistory, images: attachedImages)
                modelContext.insert(CoachMessage(role: "assistant", content: response))
            }
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        var loaded: [Data] = []
        for item in items.prefix(settings.maxPhotos) {
            guard let original = try? await item.loadTransferable(type: Data.self) else { continue }
            loaded.append(compressedImageData(original) ?? original)
        }
        imageData = loaded
        if loaded.count < items.count {
            errorMessage = "有 \(items.count - loaded.count) 张图片无法读取，请重新选择。"
        }
    }

    private func compressedImageData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 1600 else { return image.jpegData(compressionQuality: 0.82) ?? data }
        let scale = 1600 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private func removePhoto(at index: Int) {
        guard imageData.indices.contains(index) else { return }
        imageData.remove(at: index)
        if photoItems.indices.contains(index) { photoItems.remove(at: index) }
    }

    @MainActor
    private func apply(_ actions: [AIAgentAction]) throws -> [String] {
        var receipts: [String] = []
        for action in actions.prefix(12) {
            let date = action.date.flatMap(parseDate) ?? .now
            switch action.type.lowercased() {
            case "add_meal":
                guard let name = action.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                      let calories = action.calories, calories >= 0 else { continue }
                let kind = action.mealKind.flatMap(MealKind.init(rawValue:)) ?? .snack
                modelContext.insert(MealEntry(
                    date: date,
                    kind: kind,
                    name: name,
                    calories: calories,
                    protein: max(action.protein ?? 0, 0),
                    carbs: max(action.carbs ?? 0, 0),
                    fat: max(action.fat ?? 0, 0),
                    fiber: max(action.fiber ?? 0, 0),
                    note: action.note ?? "由 AI 助手按要求记录",
                    source: .ai
                ))
                receipts.append("新增\(kind.rawValue)：\(name)，\(Int(calories)) kcal")
            case "add_weight":
                guard let weight = action.weight, (20...400).contains(weight) else { continue }
                modelContext.insert(BodyMetric(date: date, weight: weight, bodyFat: action.bodyFat, waist: action.waist, note: action.note ?? "由 AI 助手按要求记录"))
                receipts.append("记录体重 \(weight.formatted(.number.precision(.fractionLength(1)))) kg")
            case "add_water":
                guard let amount = action.waterML, amount > 0, amount <= 10_000 else { continue }
                modelContext.insert(WaterEntry(date: date, milliliters: amount))
                receipts.append("记录饮水 \(Int(amount)) ml")
            case "update_goals":
                if let value = action.targetWeight, (20...400).contains(value) { settings.targetWeight = value }
                if let value = action.calorieGoal, (500...10_000).contains(value) { settings.calorieGoal = value }
                if let value = action.proteinGoal, (0...600).contains(value) { settings.proteinGoal = value }
                if let value = action.carbsGoal, (0...1200).contains(value) { settings.carbsGoal = value }
                if let value = action.fatGoal, (0...500).contains(value) { settings.fatGoal = value }
                receipts.append("更新每日营养或体重目标")
            default:
                continue
            }
        }
        return receipts
    }

    private func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        return try? Date(string, strategy: .dateTime.year().month().day())
    }

    private var systemContext: String {
        let latestWeight = bodyMetrics.last?.weight ?? settings.baselineWeight
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recentMeals = meals.filter { $0.date >= cutoff }
        let daily = Dictionary(grouping: recentMeals) { Calendar.current.startOfDay(for: $0.date) }
        let foodSummary = daily.sorted { $0.key < $1.key }.suffix(14).map { date, items in
            let calories = items.reduce(0) { $0 + $1.calories }
            let protein = items.reduce(0) { $0 + $1.protein }
            return "\(date.formatted(date: .numeric, time: .omitted))：\(Int(calories))kcal / 蛋白质\(Int(protein))g"
        }.joined(separator: "；")
        let weightSummary = bodyMetrics.suffix(12).map {
            "\($0.date.formatted(date: .numeric, time: .omitted)) \($0.weight)kg"
        }.joined(separator: "，")
        let recentWater = waterEntries.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.milliliters }

        return """
        你是这个私人健身记录 App 内的通用 AI 助手。可以回答用户提出的任何正常问题，也应结合记录给出简洁、可执行、明确区分事实与估算的建议。
        用户身高 \(settings.height)cm，起始体重 \(settings.baselineWeight)kg，当前约 \(latestWeight)kg；目标为\(settings.fitnessGoal.rawValue)，目标体重 \(settings.targetWeight)kg，每周期望变化 \(settings.weeklyWeightTarget)kg。每日目标：\(Int(settings.calorieGoal))kcal、蛋白质 \(Int(settings.proteinGoal))g、碳水 \(Int(settings.carbsGoal))g、脂肪 \(Int(settings.fatGoal))g、饮水 \(Int(settings.waterGoal))ml。
        最近体重：\(weightSummary.isEmpty ? "暂无" : weightSummary)。最近饮食：\(foodSummary.isEmpty ? "暂无" : foodSummary)。近 30 天已记录饮水总量 \(Int(recentWater))ml。
        当用户明确要求记录餐食、体重、饮水或调整目标时，按约定返回 action；不要臆造用户没说的数据。你不能删除数据。涉及伤病、进食障碍或异常体重变化时提示咨询专业人士，不做医疗诊断。
        """
    }
}

private struct ChatBubble: View {
    let message: CoachMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .foregroundStyle(isUser ? .white : .primary)
                .background(isUser ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !isUser { Spacer(minLength: 48) }
        }
    }
}
