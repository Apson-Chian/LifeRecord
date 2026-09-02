import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct CoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @EnvironmentObject private var coachTaskCenter: CoachTaskCenter
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \CoachMessage.date) private var allMessages: [CoachMessage]
    @Query(sort: \CoachConversation.updatedAt, order: .reverse) private var conversations: [CoachConversation]
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WaterEntry.date) private var waterEntries: [WaterEntry]

    @State private var input = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imageData: [Data] = []
    @State private var isLoadingPhotos = false
    @State private var showsCamera = false
    @State private var showsPhotoLibrary = false
    @State private var errorMessage: String?
    @State private var confirmsClear = false
    @State private var showsConversationSidebar = false
    @State private var activeConversationID: UUID?
    @State private var handledRouteID: UUID?
    @FocusState private var composerFocused: Bool

    private let suggestions = ["帮我记录今天晨重 64.2kg", "分析今天是否适合加餐", "看这张配料表是否适合增肌"]

    private var activeConversation: CoachConversation? {
        conversations.first(where: { $0.id == activeConversationID }) ?? conversations.first
    }

    private var messages: [CoachMessage] {
        guard let conversation = activeConversation else { return [] }
        return conversation.messages.sorted { $0.date < $1.date }
    }

    private var isSending: Bool {
        activeConversation.map { coachTaskCenter.isGenerating($0.id) } ?? false
    }

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
                                GlassCard {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(coachTaskCenter.activeQuestion(for: activeConversation?.id ?? UUID()) ?? "正在生成回答…")
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(2)
                                            Text("你可以离开这个页面，回答会继续生成并自动保存到当前对话。")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("停止") {
                                            if let id = activeConversation?.id {
                                                coachTaskCenter.cancel(id)
                                            }
                                        }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                                .id("sending")
                            } else if let status = activeConversation.flatMap({ coachTaskCenter.statusMessage(for: $0.id) }), !status.isEmpty {
                                GlassCard {
                                    Label(status, systemImage: status.hasPrefix("回答失败") ? "exclamationmark.triangle" : "checkmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(status.hasPrefix("回答失败") ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                                }
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
                    .onChange(of: coachTaskCenter.generatingConversationIDs) { _, _ in
                        if isSending {
                            withAnimation(.spring(response: 0.35, dampingFraction: 1)) {
                                proxy.scrollTo("sending", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard abs(horizontal) > abs(vertical), abs(horizontal) > 70 else { return }
                        withAnimation(.spring(response: 0.34, dampingFraction: 1)) {
                            if !showsConversationSidebar, value.startLocation.x < 72, horizontal > 0 {
                                showsConversationSidebar = true
                            } else if showsConversationSidebar, horizontal < 0 {
                                showsConversationSidebar = false
                            }
                        }
                    }
            )
            .onAppear { prepareConversations() }
            .onReceive(router.$coachRoute.compactMap { $0 }) { route in
                guard handledRouteID != route.id else { return }
                handledRouteID = route.id
                if let conversationID = route.conversationID {
                    activeConversationID = conversationID
                }
                if let draft = route.draft {
                    input = draft
                    composerFocused = true
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(activeConversation?.title ?? "AI 助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 1)) {
                            showsConversationSidebar.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel("对话列表")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startNewConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("新建对话")
                }
            }
            .overlay(alignment: .leading) {
                if showsConversationSidebar {
                    ConversationSidebar(
                        conversations: conversations,
                        activeConversationID: activeConversation?.id,
                        onSelect: { conversation in
                            activeConversationID = conversation.id
                            withAnimation(.spring(response: 0.34, dampingFraction: 1)) {
                                showsConversationSidebar = false
                            }
                        },
                        onDelete: { conversation in
                            deleteConversation(conversation)
                        },
                        onNew: {
                            startNewConversation()
                            withAnimation(.spring(response: 0.34, dampingFraction: 1)) {
                                showsConversationSidebar = false
                            }
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 1)) {
                                showsConversationSidebar = false
                            }
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .confirmationDialog("清空当前对话？", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    messages.forEach(modelContext.delete)
                    activeConversation?.updatedAt = .now
                    do {
                        try modelContext.save()
                    } catch {
                        modelContext.rollback()
                        errorMessage = "对话清空失败：\(error.localizedDescription)"
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("其他对话、体重、餐食和饮水记录不会受影响。")
            }
            .alert("暂时无法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraImagePicker { image in
                    addCameraPhoto(image)
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showsPhotoLibrary,
                selection: $photoItems,
                maxSelectionCount: max(settings.maxPhotos - imageData.count, 1),
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
        }
    }

    @ViewBuilder
    private var coachIntro: some View {
        if messages.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Label(settings.aiCanWrite ? "今天想聊什么？" : "AI 助手", systemImage: "wand.and.sparkles")
                        .font(.title2.bold())
                    Text(settings.supportsVision
                         ? "可以发送食物、配料表、营养表或训练截图，也可以让我替你记录数据。"
                         : "当前模型未开启图片输入，请在设置中切换多模态模型。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            input = suggestion
                            composerFocused = true
                        } label: {
                            Text(suggestion)
                                .font(.footnote.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .foregroundStyle(.primary)
                    }
                }

                if settings.aiCanWrite {
                    Label("新增和调整会在回复中列明；删除数据始终由你手动完成。", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)
        }
    }

    private var composer: some View {
        let visionEnabled = settings.supportsVision
        return VStack(spacing: 0) {
            if !imageData.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(Array(imageData.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                                        }
                                    Button { removePhoto(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.72))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button {
                        showsCamera = true
                    } label: {
                        Label("拍照", systemImage: "camera.fill")
                    }
                    .disabled(
                        imageData.count >= settings.maxPhotos
                        || !UIImagePickerController.isSourceTypeAvailable(.camera)
                    )

                    Button {
                        showsPhotoLibrary = true
                    } label: {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }
                    .disabled(imageData.count >= settings.maxPhotos)
                } label: {
                    Group {
                        if isLoadingPhotos {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus")
                                .font(.body.weight(.medium))
                        }
                    }
                    .foregroundStyle(visionEnabled ? AppTheme.accent : .secondary)
                    .frame(width: 38, height: 38)
                    .background(Color(.tertiarySystemFill), in: Circle())
                }
                .disabled(isSending || isLoadingPhotos || !settings.supportsVision)
                .accessibilityLabel("添加照片")
                .accessibilityHint("可以拍照或从相册选择")

                TextField(imageData.isEmpty ? "问问题，或让我替你记录…" : "告诉教练你做了什么…", text: $input, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.vertical, 9)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { if canSend { send() } }

                if composerFocused {
                    Button {
                        composerFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, height: 38)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("收起键盘")
                }

                Button {
                    if isSending {
                        if let id = activeConversation?.id { coachTaskCenter.cancel(id) }
                    } else {
                        send()
                    }
                } label: {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            Group {
                                if canSend {
                                    Circle().fill(AppTheme.accent)
                                } else {
                                    Circle().fill(Color(.systemGray3))
                                }
                            }
                        )
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(isLoadingPhotos || (!canSend && !isSending))
                .accessibilityLabel(isSending ? "正在生成" : "发送")
            }
            .padding(7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var canSend: Bool {
        !isSending && !isLoadingPhotos && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageData.isEmpty)
    }

    @MainActor
    private func prepareConversations() {
        if conversations.isEmpty, !allMessages.isEmpty {
            let legacy = CoachConversation(title: "历史对话")
            modelContext.insert(legacy)
            for message in allMessages { message.conversation = legacy }
            legacy.updatedAt = allMessages.last?.date ?? .now
            do {
                try modelContext.save()
                activeConversationID = legacy.id
            } catch {
                modelContext.rollback()
                errorMessage = "历史对话升级失败：\(error.localizedDescription)"
            }
        } else {
            activeConversationID = activeConversation?.id
        }
    }

    @MainActor
    private func startNewConversation() {
        let conversation = CoachConversation()
        modelContext.insert(conversation)
        do {
            try modelContext.save()
            activeConversationID = conversation.id
            errorMessage = nil
            composerFocused = true
        } catch {
            modelContext.rollback()
            errorMessage = "新建对话失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteConversation(_ conversation: CoachConversation) {
        modelContext.delete(conversation)
        do {
            try modelContext.save()
            if activeConversationID == conversation.id {
                activeConversationID = conversations.first(where: { $0.id != conversation.id })?.id
            }
        } catch {
            modelContext.rollback()
            errorMessage = "删除对话失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        composerFocused = false

        let attachedImages = imageData
        let displayText = text.isEmpty
            ? "[发送了 \(attachedImages.count) 张图片]"
            : (attachedImages.isEmpty ? text : "\(text)\n[附带 \(attachedImages.count) 张图片]")
        let requestText: String
        if attachedImages.isEmpty {
            requestText = text
        } else if text.isEmpty {
            requestText = "请识别我发送的图片。如果这是我实际吃下的餐食或饮料，请估算营养并直接记录进饮食记录；如果只是配料表、包装或菜单，则只分析。"
        } else {
            requestText = text + "\n如果图片是我实际吃下的餐食或饮料，且我没有明确说不要记录，请同时记录进饮食记录。"
        }
        let outgoingHistory = messages.map { AIChatMessage(role: $0.role, content: $0.content) }
            + [AIChatMessage(role: "user", content: requestText)]

        let conversation = activeConversation ?? CoachConversation()
        if activeConversation == nil {
            modelContext.insert(conversation)
            activeConversationID = conversation.id
        }
        if conversation.title == "新对话" {
            conversation.title = text.isEmpty ? "图片对话" : String(text.prefix(28))
        }

        let userMessage = CoachMessage(role: "user", content: displayText)
        userMessage.conversation = conversation
        modelContext.insert(userMessage)
        conversation.updatedAt = .now

        // 用户问题先落盘，再启动后台生成；离开教练页也不会取消请求。
        do {
            try modelContext.save()
        } catch {
            errorMessage = "问题保存失败：\(error.localizedDescription)"
            return
        }

        input = ""
        photoItems = []
        imageData = []

        let conversationID = conversation.id
        AIAnswerNotificationCenter.shared.requestAuthorizationIfNeeded()
        let context = systemContext
        let settings = settings
        let modelContext = modelContext

        let accepted = coachTaskCenter.submit(conversationID: conversationID, question: displayText) {
            do {
                let client = AIClient(settings: settings)
                if settings.aiCanWrite {
                    let reply = try await client.agent(
                        system: context,
                        messages: outgoingHistory,
                        images: attachedImages
                    )
                    let execution = try await apply(
                        reply.actions,
                        attachedImages: attachedImages,
                        explicitlyRequestedDate: requestedActionDate(in: requestText)
                    )
                    let content: String
                    if !execution.receipts.isEmpty {
                        content = reply.answer
                            + "\n\n已核验并执行\n"
                            + execution.receipts.map { "• \($0)" }.joined(separator: "\n")
                            + (execution.rejectedCount > 0 ? "\n• 另有 \(execution.rejectedCount) 项参数无效，未写入" : "")
                            + (execution.warnings.isEmpty ? "" : "\n\n" + execution.warnings.map { "⚠️ \($0)" }.joined(separator: "\n"))
                    } else if execution.rejectedCount > 0 || isMutationRequest(text) || !attachedImages.isEmpty {
                        content = "未执行：AI 没有返回可验证的有效操作，数据库没有被修改。"
                            + (reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                               ? " 请把目标记录说得更明确后重试。"
                               : "\n\n" + reply.answer)
                    } else {
                        content = reply.answer
                    }
                    insertAssistantMessage(content, in: conversation)
                } else {
                    let response = try await client.coachText(
                        system: context,
                        messages: outgoingHistory,
                        images: attachedImages
                    )
                    insertAssistantMessage(response, in: conversation)
                }
                try modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                insertAssistantMessage("回答失败：\(error.localizedDescription)", in: conversation)
                try? modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                throw error
            }
        }

        if !accepted {
            // 极端情况下任务未成功提交时，把输入恢复，避免用户问题被吞掉。
            input = text
            imageData = attachedImages
            errorMessage = "当前对话正在生成，请稍后再发。"
        }
    }

    @MainActor
    private func insertAssistantMessage(_ content: String, in conversation: CoachConversation) {
        let message = CoachMessage(role: "assistant", content: content)
        message.conversation = conversation
        modelContext.insert(message)
        conversation.updatedAt = .now
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        let remaining = max(settings.maxPhotos - imageData.count, 0)
        var loaded = imageData
        var failedCount = 0
        for item in items.prefix(remaining) {
            guard let original = try? await item.loadTransferable(type: Data.self) else { continue }
            loaded.append(AIClient.jpegImageData(forSending: original))
        }
        failedCount = min(items.count, remaining) - (loaded.count - imageData.count)
        imageData = loaded
        photoItems = []
        isLoadingPhotos = false
        if failedCount > 0 {
            errorMessage = "有 \(failedCount) 张图片无法读取，请重新选择。"
        }
        if !loaded.isEmpty { composerFocused = true }
    }

    @MainActor
    private func addCameraPhoto(_ image: UIImage) {
        guard imageData.count < settings.maxPhotos,
              let original = image.jpegData(compressionQuality: 0.9) else { return }
        imageData.append(AIClient.jpegImageData(forSending: original))
        composerFocused = true
    }

    private func removePhoto(at index: Int) {
        guard imageData.indices.contains(index) else { return }
        imageData.remove(at: index)
        if photoItems.indices.contains(index) { photoItems.remove(at: index) }
    }

    @MainActor
    private struct ActionExecution {
        var receipts: [String] = []
        var rejectedCount = 0
        var warnings: [String] = []
    }

    @MainActor
    private func apply(
        _ actions: [AIAgentAction],
        attachedImages: [Data],
        explicitlyRequestedDate: Date?
    ) async throws -> ActionExecution {
        var receipts: [String] = []
        var rejectedCount = 0
        var warnings: [String] = []
        var photoUploadError: Error?
        var didAttachPhotos = false
        for action in actions.prefix(12) {
            let date = explicitlyRequestedDate ?? resolvedActionDate(action.date)
            let type = action.type
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            switch type {
            case "add_meal", "record_meal", "log_meal":
                guard let name = action.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                      let calories = action.calories, calories >= 0 else {
                    rejectedCount += 1
                    continue
                }
                let kind = action.mealKind.flatMap(MealKind.init(rawValue:)) ?? .snack
                let mealID = UUID()
                let photoIDs: [String]
                if !didAttachPhotos && !attachedImages.isEmpty {
                    do {
                        photoIDs = try await syncCoordinator.uploadMealPhotos(attachedImages, mealID: mealID)
                    } catch {
                        // 图片持久化是附加能力，不应该把已经成功的 AI 识别和数据写入整体判定为失败。
                        photoIDs = []
                        photoUploadError = error
                        let warning = "AI 识别和记录已完成，但附带图片未保存：\(error.localizedDescription)"
                        if !warnings.contains(warning) { warnings.append(warning) }
                    }
                    didAttachPhotos = true
                } else {
                    photoIDs = []
                }
                modelContext.insert(MealEntry(
                    id: mealID,
                    date: date,
                    kind: kind,
                    name: name,
                    calories: calories,
                    protein: max(action.protein ?? 0, 0),
                    carbs: max(action.carbs ?? 0, 0),
                    fat: max(action.fat ?? 0, 0),
                    fiber: max(action.fiber ?? 0, 0),
                    note: action.note ?? "由 AI 助手按要求记录",
                    source: .ai,
                    photoIDs: photoIDs
                ))
                if let waterML = action.waterML,
                   waterML > 0,
                   waterML <= 10_000,
                   let waterSource = action.waterSource?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !waterSource.isEmpty {
                    modelContext.insert(WaterEntry(date: date, milliliters: waterML, note: "来自 AI 识别：\(waterSource)"))
                }
                receipts.append("新增\(kind.rawValue)：\(name)，\(Int(calories)) kcal · \(receiptDate(date))")
            case "add_weight", "record_weight", "log_weight":
                guard let weight = action.weight, (20...400).contains(weight) else {
                    rejectedCount += 1
                    continue
                }
                modelContext.insert(BodyMetric(date: date, weight: weight, bodyFat: action.bodyFat, note: action.note ?? "由 AI 助手按要求记录"))
                receipts.append("记录体重 \(weight.formatted(.number.precision(.fractionLength(1)))) kg · \(receiptDate(date))")
            case "add_water", "record_water", "log_water":
                guard let amount = action.waterML, amount > 0, amount <= 10_000 else {
                    rejectedCount += 1
                    continue
                }
                modelContext.insert(WaterEntry(date: date, milliliters: amount, note: action.note ?? "由 AI 助手按要求记录"))
                receipts.append("记录饮水 \(Int(amount)) ml · \(receiptDate(date))")
            case "delete_meal", "remove_meal":
                guard let id = actionRecordID(action), let meal = meals.first(where: { $0.id == id }) else {
                    rejectedCount += 1
                    continue
                }
                let description = "\(meal.kind.rawValue)：\(meal.name) · \(receiptDate(meal.date))"
                SyncDeletion.delete(meal, context: modelContext)
                receipts.append("删除\(description)")
            case "delete_weight", "remove_weight", "delete_body":
                guard let id = actionRecordID(action), let metric = bodyMetrics.first(where: { $0.id == id }) else {
                    rejectedCount += 1
                    continue
                }
                let description = "体重 \(metric.weight.formatted(.number.precision(.fractionLength(1)))) kg · \(receiptDate(metric.date))"
                SyncDeletion.delete(metric, context: modelContext)
                receipts.append("删除\(description)")
            case "delete_water", "remove_water":
                guard let id = actionRecordID(action), let water = waterEntries.first(where: { $0.id == id }) else {
                    rejectedCount += 1
                    continue
                }
                let description = "饮水 \(Int(water.milliliters)) ml · \(receiptDate(water.date))"
                SyncDeletion.delete(water, context: modelContext)
                receipts.append("删除\(description)")
            case "update_goals", "update_goal", "set_goals", "set_goal":
                var updates: [String] = []
                if let value = action.targetWeight, (20...400).contains(value) {
                    settings.targetWeight = value
                    updates.append("目标体重 \(value.formatted(.number.precision(.fractionLength(1)))) kg")
                }
                if let value = action.calorieGoal, (500...10_000).contains(value) {
                    settings.calorieGoal = value
                    updates.append("热量目标 \(Int(value)) kcal")
                }
                if let value = action.proteinGoal, (0...600).contains(value) {
                    settings.proteinGoal = value
                    updates.append("蛋白质目标 \(Int(value)) g")
                }
                if let value = action.carbsGoal, (0...1200).contains(value) {
                    settings.carbsGoal = value
                    updates.append("碳水目标 \(Int(value)) g")
                }
                if let value = action.fatGoal, (0...500).contains(value) {
                    settings.fatGoal = value
                    updates.append("脂肪目标 \(Int(value)) g")
                }
                if updates.isEmpty {
                    rejectedCount += 1
                } else {
                    receipts.append("更新" + updates.joined(separator: "、"))
                }
            default:
                rejectedCount += 1
            }
        }
        if !receipts.isEmpty {
            // 只有数据库真正保存成功，界面才允许显示成功回执。
            try modelContext.save()
            await syncCoordinator.sync(context: modelContext, settings: settings)
            if let photoUploadError {
                syncCoordinator.reportPhotoUploadFailure(photoUploadError)
            }
        }
        return ActionExecution(receipts: receipts, rejectedCount: rejectedCount, warnings: warnings)
    }

    private func resolvedActionDate(_ string: String?) -> Date {
        guard let string, !string.isEmpty else { return .now }
        if string.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            if let day = formatter.date(from: string) {
                // AI 常只返回日期；今天的记录用实际提交时间，确保不会被当天示例/旧记录盖住。
                if Calendar.current.isDateInToday(day) { return .now }
                return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string) ?? .now
    }

    private func isMutationRequest(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return ["帮我记录", "帮我记", "记录一下", "记一下", "新增", "添加", "修改", "改成", "更新目标", "设置为", "删掉", "删除", "移除"]
            .contains { compact.contains($0) }
            || compact.hasPrefix("记录")
    }

    private func actionRecordID(_ action: AIAgentAction) -> UUID? {
        guard let value = action.recordID?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return UUID(uuidString: value)
    }

    private func receiptDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Explicit times in the user's own instruction win over a model-produced timestamp.
    private func requestedActionDate(in text: String) -> Date? {
        let normalized = text.replacingOccurrences(of: "：", with: ":")
        let timePattern = #"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)|(?<!\d)([0-2]?\d)点(?:(半)|([0-5]?\d)分?)?"#
        guard let match = firstRegexMatch(timePattern, in: normalized) else { return nil }

        let hourText = match[1] ?? match[3]
        guard var hour = hourText.flatMap(Int.init) else { return nil }
        let minute = match[2].flatMap(Int.init) ?? (match[4] == "半" ? 30 : match[5].flatMap(Int.init) ?? 0)

        if normalized.range(of: #"下午|晚上|今晚|傍晚"#, options: .regularExpression) != nil, hour < 12 {
            hour += 12
        } else if normalized.contains("中午"), hour < 11 {
            hour += 12
        } else if normalized.contains("凌晨"), hour == 12 {
            hour = 0
        }

        let calendar = Calendar.current
        var base = Date.now
        if normalized.contains("前天") {
            base = calendar.date(byAdding: .day, value: -2, to: base) ?? base
        } else if normalized.contains("昨天") || normalized.contains("昨日") {
            base = calendar.date(byAdding: .day, value: -1, to: base) ?? base
        } else if normalized.contains("明天") || normalized.contains("明日") {
            base = calendar.date(byAdding: .day, value: 1, to: base) ?? base
        } else if let dateMatch = firstRegexMatch(#"(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?"#, in: normalized),
                  let year = dateMatch[1].flatMap(Int.init),
                  let month = dateMatch[2].flatMap(Int.init),
                  let day = dateMatch[3].flatMap(Int.init) {
            var components = calendar.dateComponents(in: .current, from: base)
            components.year = year
            components.month = month
            components.day = day
            base = calendar.date(from: components) ?? base
        } else if let dateMatch = firstRegexMatch(#"(?<!\d)(\d{1,2})月(\d{1,2})日?"#, in: normalized),
                  let month = dateMatch[1].flatMap(Int.init),
                  let day = dateMatch[2].flatMap(Int.init) {
            var components = calendar.dateComponents(in: .current, from: base)
            components.month = month
            components.day = day
            base = calendar.date(from: components) ?? base
        }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
    }

    private func firstRegexMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange])
        }
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
        let deletableMeals = recentMeals.sorted { $0.date > $1.date }.prefix(30).map {
            "meal id=\($0.id.uuidString) | \(receiptDate($0.date)) | \($0.kind.rawValue) | \($0.name) | \(Int($0.calories))kcal"
        }.joined(separator: "\n")
        let deletableWeights = bodyMetrics.sorted { $0.date > $1.date }.prefix(20).map {
            "weight id=\($0.id.uuidString) | \(receiptDate($0.date)) | \($0.weight)kg"
        }.joined(separator: "\n")
        let deletableWater = waterEntries.sorted { $0.date > $1.date }.prefix(30).map {
            "water id=\($0.id.uuidString) | \(receiptDate($0.date)) | \(Int($0.milliliters))ml | \($0.note.isEmpty ? "无备注" : $0.note)"
        }.joined(separator: "\n")

        return """
        你是这个私人健身记录 App 内的通用 AI 助手。可以回答用户提出的任何正常问题，也应结合记录给出简洁、可执行、明确区分事实与估算的建议。
        用户身高 \(settings.height)cm，起始体重 \(settings.baselineWeight)kg，当前约 \(latestWeight)kg；目标为\(settings.fitnessGoal.rawValue)，目标体重 \(settings.targetWeight)kg，每周期望变化 \(settings.weeklyWeightTarget)kg。每日目标：\(Int(settings.calorieGoal))kcal、蛋白质 \(Int(settings.proteinGoal))g、碳水 \(Int(settings.carbsGoal))g、脂肪 \(Int(settings.fatGoal))g、饮水 \(Int(settings.waterGoal))ml。
        最近体重：\(weightSummary.isEmpty ? "暂无" : weightSummary)。最近饮食：\(foodSummary.isEmpty ? "暂无" : foodSummary)。近 30 天已记录饮水总量 \(Int(recentWater))ml。
        当前可操作记录清单（删除只能使用这里的准确 id；找不到或有歧义就先询问）：
        \(deletableMeals.isEmpty ? "暂无餐食" : deletableMeals)
        \(deletableWeights.isEmpty ? "暂无体重" : deletableWeights)
        \(deletableWater.isEmpty ? "暂无饮水" : deletableWater)
        当用户明确要求记录餐食、体重、饮水、调整目标或删除记录时，按约定返回 action；用户发送明显属于实际摄入的餐食或饮料照片且没有要求“只分析/不要记录”时，也必须识别营养并返回 add_meal action。不要把单独的配料表、商品包装或菜单误判为已经摄入。不要臆造用户没说的数据。删除动作必须与用户明确指定的类型、时间和内容一致。涉及伤病、进食障碍或异常体重变化时提示咨询专业人士，不做医疗诊断。
        """
    }
}

private struct ConversationListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CoachConversation.updatedAt, order: .reverse) private var conversations: [CoachConversation]

    let activeConversationID: UUID?
    let onSelect: (CoachConversation) -> Void
    let onDelete: (CoachConversation) -> Void
    let onNew: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView {
                        Label("还没有对话", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("新建一个对话，可以围绕增肌、饮食复盘或某几张配料表连续追问。")
                    } actions: {
                        Button("新建对话", action: onNew)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(conversations) { conversation in
                                Button {
                                    onSelect(conversation)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: conversation.id == activeConversationID ? "bubble.left.fill" : "bubble.left")
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 5) {
                                                Text(conversation.title)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                if conversation.isDemo {
                                                    Text("示例")
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                                                        .foregroundStyle(AppTheme.accent)
                                                }
                                            }
                                            Text("\(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(conversation.messages.count) 条消息")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if conversation.id == activeConversationID {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        onDelete(conversation)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text("全部对话")
                        } footer: {
                            Text("每个对话拥有独立上下文；删除对话不会影响饮食、体重和饮水记录。")
                        }
                    }
                }
            }
            .navigationTitle("对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onNew()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建对话")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ConversationSidebar: View {
    let conversations: [CoachConversation]
    let activeConversationID: UUID?
    let onSelect: (CoachConversation) -> Void
    let onDelete: (CoachConversation) -> Void
    let onNew: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("对话")
                        .font(.headline)
                    Spacer()
                    Button(action: onNew) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建对话")
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭对话列表")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                if conversations.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label("还没有对话", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("新建一个对话，可以围绕增肌、饮食复盘或某几张配料表连续追问。")
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(conversations) { conversation in
                                Button {
                                    onSelect(conversation)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: conversation.id == activeConversationID ? "bubble.left.fill" : "bubble.left")
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(conversation.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text("\(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(conversation.messages.count) 条消息")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if conversation.id == activeConversationID {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                    }
                                    .padding(11)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDelete(conversation)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
            }
            .frame(width: 306)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 0.5)
            }

            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
        }
        .background(.clear)
    }
}

private struct ChatBubble: View {
    let message: CoachMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser {
                Spacer(minLength: 52)
            } else {
                Image("CoachAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.75), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }

            Group {
                if isUser {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    ChatMarkdownText(content: message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 0.5)
                        }
                }
            }

            if !isUser {
                Spacer(minLength: 52)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct ChatMarkdownText: View {
    let content: String

    private var lines: [String] {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .font(.body)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            Color.clear.frame(height: 3)
        } else if trimmed == "---" || trimmed == "***" {
            Divider()
        } else if trimmed.hasPrefix("### ") {
            markdownText(String(trimmed.dropFirst(4)))
                .font(.subheadline.weight(.semibold))
        } else if trimmed.hasPrefix("## ") {
            markdownText(String(trimmed.dropFirst(3)))
                .font(.headline)
        } else if trimmed.hasPrefix("# ") {
            markdownText(String(trimmed.dropFirst(2)))
                .font(.title3.weight(.semibold))
        } else if trimmed.hasPrefix("> ") {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.35))
                    .frame(width: 3)
                markdownText(String(trimmed.dropFirst(2)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .foregroundStyle(AppTheme.accent)
                markdownText(String(trimmed.dropFirst(2)))
            }
        } else {
            markdownText(trimmed)
        }
    }

    private func markdownText(_ value: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: value, options: options) {
            return Text(attributed)
        }
        return Text(value)
    }
}
