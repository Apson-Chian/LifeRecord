import SwiftUI
import UIKit

private struct LegacySettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.modelContext) private var modelContext

    @State private var showsAPIKeyEditor = false
    @State private var hasAPIKey = false
    @State private var isTesting = false
    @State private var connectionMessage: String?
    @State private var showsLifeTrackUnavailable = false
    @State private var showsOnboarding = false
    @State private var showsSyncKeyEditor = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case profile, nutrition, endpoint, model, header, instructions
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    TextField("称呼（可选）", text: $settings.displayName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .profile)
                    Picker("当前目标", selection: $settings.fitnessGoal) {
                        ForEach(FitnessGoal.allCases) { goal in
                            Label(goal.rawValue, systemImage: goal.symbol).tag(goal)
                        }
                    }
                    settingNumber("身高", value: $settings.height, unit: "cm", field: .profile)
                    settingNumber("起始体重", value: $settings.baselineWeight, unit: "kg", field: .profile)
                    settingNumber("目标体重", value: $settings.targetWeight, unit: "kg", field: .profile)
                    settingNumber("每周体重变化", value: $settings.weeklyWeightTarget, unit: "kg", field: .profile)
                    Button("套用“\(settings.fitnessGoal.rawValue)”建议模板", systemImage: "wand.and.stars") {
                        settings.applyGoalTemplate(settings.fitnessGoal)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } header: {
                    Text("身体与目标")
                } footer: {
                    Text("模板仅作为 181 cm、64 kg 的增肌起点。热量和体重变化请根据连续 2–3 周趋势调整。")
                }

                Section {
                    settingNumber("每日热量", value: $settings.calorieGoal, unit: "kcal", field: .nutrition)
                    settingNumber("蛋白质", value: $settings.proteinGoal, unit: "g", field: .nutrition)
                    settingNumber("碳水", value: $settings.carbsGoal, unit: "g", field: .nutrition)
                    settingNumber("脂肪", value: $settings.fatGoal, unit: "g", field: .nutrition)
                    settingNumber("饮水", value: $settings.waterGoal, unit: "ml", field: .nutrition)
                } header: {
                    Text("每日目标")
                }

                Section {
                    Picker("服务商", selection: $settings.provider) {
                        ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("接口地址", text: $settings.endpoint, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .endpoint)
                    TextField("模型名称", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .model)
                    Picker("认证方式", selection: $settings.authStyle) {
                        ForEach(AIAuthStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if settings.authStyle == .custom {
                        TextField("认证请求头名称", text: $settings.customHeaderName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .header)
                    }
                    Button {
                        focusedField = nil
                        showsAPIKeyEditor = true
                    } label: {
                        HStack {
                            Label("\(settings.provider.rawValue) API Key", systemImage: "key.horizontal.fill")
                            Spacer()
                            Text(hasAPIKey ? "已安全保存" : "未设置")
                                .foregroundStyle(hasAPIKey ? AppTheme.success : .secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        Task { await testSavedConnection() }
                    } label: {
                        HStack {
                            Label("测试当前配置", systemImage: "network")
                            Spacer()
                            if isTesting { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isTesting || !hasAPIKey)

                    if let connectionMessage {
                        Text(connectionMessage)
                            .font(.caption)
                            .foregroundStyle(connectionMessage.hasPrefix("连接成功") ? AppTheme.success : .red)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("AI 接口")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("兼容 OpenAI Chat Completions 格式。每个服务商的 API Key 分开保存在本机钥匙串。当前预设：DeepSeek deepseek-v4-flash、Dots dots3-note-prev、GLM glm-4.6v-flash。")
                        if settings.provider == .dots {
                            Link("Dots API 开放平台与接口文档", destination: URL(string: "https://dots.ai/platform/docs")!)
                        }
                    }
                }

                Section {
                    Toggle("支持图片输入", isOn: $settings.supportsVision)
                    Stepper("单次最多照片：\(settings.maxPhotos) 张", value: $settings.maxPhotos, in: 1...12)
                    Toggle("允许 AI 修改记录", isOn: $settings.aiCanWrite)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("创造性")
                            Spacer()
                            Text(settings.temperature.formatted(.number.precision(.fractionLength(1))))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.temperature, in: 0...1, step: 0.1)
                    }
                    Stepper("最长回复：\(settings.maxTokens) tokens", value: $settings.maxTokens, in: 400...8000, step: 200)
                    TextField("给 AI 的长期偏好，例如训练安排、忌口", text: $settings.customInstructions, axis: .vertical)
                        .lineLimit(3...7)
                        .focused($focusedField, equals: .instructions)
                } header: {
                    Text("AI 能力与权限")
                } footer: {
                    Text(settings.aiCanWrite
                         ? "AI 可按你的明确要求新增或删除餐食、体重与饮水记录，并调整目标。"
                         : "AI 目前只能读取摘要并回答，不会修改任何记录。")
                }

                Section("引导") {
                    Button("重新查看使用引导", systemImage: "book") {
                        showsOnboarding = true
                    }
                    Button("重新写入完整示例数据", systemImage: "arrow.counterclockwise") {
                        DemoDataService.reinstall(context: modelContext)
                    }
                    Button("清除示例数据", systemImage: "trash") {
                        DemoDataService.clear(context: modelContext)
                    }
                    .foregroundStyle(.red)
                }

                Section {
                    Button {
                        showsSyncKeyEditor = true
                    } label: {
                        HStack {
                            Label("同步密钥", systemImage: "key.viewfinder")
                            Spacer()
                            Text(syncCoordinator.isConfigured ? "已配置" : "未配置")
                                .foregroundStyle(syncCoordinator.isConfigured ? AppTheme.recorded : .secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
                    } label: {
                        HStack {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if syncCoordinator.isSyncing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(!syncCoordinator.isConfigured || syncCoordinator.isSyncing)

                    Link(destination: URL(string: "https://apsonchian.ltd/liferecord/")!) {
                        Label("打开网页版", systemImage: "safari")
                    }

                    HStack(spacing: 8) {
                        Image(systemName: syncCoordinator.lastError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(syncCoordinator.statusMessage)
                            if let date = syncCoordinator.lastSyncedAt {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let error = syncCoordinator.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(syncCoordinator.lastError == nil ? AppTheme.recorded : .orange)
                } header: {
                    Text("App 与浏览器同步")
                } footer: {
                    Text("餐食、身体数据、饮水记录和每日目标通过你的私有服务器双向同步。同步密钥只保存在 iOS 钥匙串中。")
                }

                Section("隐私") {
                    Label(syncCoordinator.isConfigured ? "健康数据仅在本机和你的服务器间同步" : "健康数据默认只保存在本机", systemImage: "lock.shield")
                    Label("仅在使用 AI 时发送相关文字与所选图片", systemImage: "arrow.up.forward.app")
                }

                Section {
                    if let lastSync = SharedProfileStore.lastPublishedAt {
                        Label("身体档案已同步", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Text("最近同步：\(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("尚未同步到 LifeTrack", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        if !LifeLink.openLifeTrack() {
                            showsLifeTrackUnavailable = true
                        }
                    } label: {
                        Label("打开 LifeTrack", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("与 LifeTrack 联动")
                } footer: {
                    Text("身高、体重与每日目标会通过 App Group 同步给 LifeTrack；若无法跨 App 同步，请在 Apple 开发者后台注册 group.com.aotelei.liferecord。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showsAPIKeyEditor, onDismiss: {
                hasAPIKey = KeychainStore.hasAPIKey(for: settings.provider)
            }) {
                APIKeyEditorView(settings: settings)
            }
            .sheet(isPresented: $showsSyncKeyEditor, onDismiss: {
                syncCoordinator.refreshConfiguration()
            }) {
                SyncKeyEditorView()
            }
            .onAppear {
                hasAPIKey = KeychainStore.hasAPIKey(for: settings.provider)
                syncCoordinator.refreshConfiguration()
            }
            .onChange(of: settings.provider) { _, provider in
                hasAPIKey = KeychainStore.hasAPIKey(for: provider)
                connectionMessage = nil
            }
            .fullScreenCover(isPresented: $showsOnboarding) {
                OnboardingView()
            }
            .alert("未安装 LifeTrack", isPresented: $showsLifeTrackUnavailable) {
                Button("好") { }
            } message: {
                Text("请先安装 LifeTrack，或确认两个 App 使用相同的开发者签名。")
            }
        }
    }

    private func settingNumber(
        _ title: String,
        value: Binding<Double>,
        unit: String,
        field: Field
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 105)
                .focused($focusedField, equals: field)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
        }
    }

    @MainActor
    private func testSavedConnection() async {
        focusedField = nil
        isTesting = true
        connectionMessage = nil
        defer { isTesting = false }
        do {
            let response = try await AIClient(settings: settings).testConnection()
            connectionMessage = "连接成功：\(response.prefix(80))"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            connectionMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

struct SyncKeyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator

    @State private var syncKey = KeychainStore.loadSyncKey()
    @State private var revealsKey = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var showsDeleteConfirmation = false
    @FocusState private var isFocused: Bool

    private var trimmedKey: String {
        syncKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        if revealsKey {
                            TextField("粘贴同步密钥", text: $syncKey)
                        } else {
                            SecureField("粘贴同步密钥", text: $syncKey)
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)

                    Toggle("显示内容", isOn: $revealsKey)
                    Button("从剪贴板粘贴", systemImage: "doc.on.clipboard") {
                        if let value = UIPasteboard.general.string {
                            syncKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } header: {
                    Text("私有同步密钥")
                } footer: {
                    Text("网页版首次打开时也填写同一密钥。验证成功后，浏览器会使用安全 Cookie，不会把密钥保存在网页脚本中。")
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(statusMessage.hasPrefix("保存并同步成功") ? AppTheme.recorded : .red)
                    }
                }

                if KeychainStore.hasSyncKey {
                    Section {
                        Button("移除本机同步密钥", systemImage: "trash", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle("跨设备同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "同步中…" : "保存并同步") {
                        Task { await saveAndSync() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || trimmedKey.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { isFocused = false }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("移除同步密钥？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("移除", role: .destructive) { removeKey() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("本机数据不会删除，但之后不会继续与浏览器同步。")
            }
            .onAppear { isFocused = syncKey.isEmpty }
        }
    }

    @MainActor
    private func saveAndSync() async {
        isFocused = false
        isSaving = true
        statusMessage = nil
        defer { isSaving = false }
        do {
            try KeychainStore.saveSyncKey(trimmedKey)
            syncCoordinator.refreshConfiguration()
            await syncCoordinator.sync(context: modelContext, settings: settings)
            if let error = syncCoordinator.lastError {
                statusMessage = "密钥已保存，但同步失败：\(error)"
            } else {
                statusMessage = "保存并同步成功"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            statusMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func removeKey() {
        do {
            try KeychainStore.deleteSyncKey()
            syncKey = ""
            syncCoordinator.refreshConfiguration()
            statusMessage = "同步密钥已从本机移除。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

struct APIKeyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let settings: AppSettings

    @State private var apiKey: String
    @State private var revealsKey = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var showsDeleteConfirmation = false
    @FocusState private var isFocused: Bool

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(settings: AppSettings) {
        self.settings = settings
        _apiKey = State(initialValue: KeychainStore.loadAPIKey(for: settings.provider))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        if revealsKey {
                            TextField("粘贴 API Key", text: $apiKey)
                        } else {
                            SecureField("粘贴 API Key", text: $apiKey)
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)

                    Toggle("显示内容", isOn: $revealsKey)

                    Button("从剪贴板粘贴", systemImage: "doc.on.clipboard") {
                        if let value = UIPasteboard.general.string {
                            apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } header: {
                    Text("\(settings.provider.rawValue) 密钥")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("保存会先写入 iOS 钥匙串，再使用当前接口与模型发起一次结构化输出测试。该密钥仅属于 \(settings.provider.rawValue)，不会与其他服务商共用。")
                        if settings.provider == .dots {
                            Text("Dots 必须使用 dots.ai API 开放平台创建的完整 API Key；普通账号凭证、旧密钥或其他平台密钥会被 401/403 拒绝。")
                            Link("打开 Dots API 文档", destination: URL(string: "https://dots.ai/platform/docs")!)
                        }
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(statusMessage.hasPrefix("保存并连接成功") ? AppTheme.success : .red)
                            .textSelection(.enabled)
                    }
                }

                if KeychainStore.hasAPIKey(for: settings.provider) {
                    Section {
                        Button("删除本机密钥", systemImage: "trash", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "测试中…" : "保存并测试") {
                        Task { await saveAndTest() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || trimmedKey.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { isFocused = false }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("删除 API Key？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("删除", role: .destructive) { deleteKey() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("只会删除本机钥匙串中的密钥。")
            }
            .onAppear { isFocused = apiKey.isEmpty }
        }
    }

    @MainActor
    private func saveAndTest() async {
        isFocused = false
        isSaving = true
        statusMessage = nil
        defer { isSaving = false }
        do {
            try KeychainStore.saveAPIKey(trimmedKey, for: settings.provider)
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        do {
            let response = try await AIClient(settings: settings).testConnection(apiKey: trimmedKey)
            statusMessage = "保存并连接成功：\(response.prefix(80))"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            statusMessage = "密钥已保存，但连接测试失败：\(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func deleteKey() {
        do {
            try KeychainStore.deleteAPIKey(for: settings.provider)
            apiKey = ""
            statusMessage = "API Key 已从本机删除。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
