import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator

    var body: some View {
        NavigationStack {
            Form {
                Section("个人") {
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "身体与目标",
                            subtitle: "\(settings.fitnessGoal.rawValue) · \(Int(settings.height)) cm · 目标 \(settings.targetWeight.formatted(.number.precision(.fractionLength(1)))) kg",
                            symbol: "person.crop.circle.fill",
                            tint: AppTheme.accent
                        )
                    }

                    NavigationLink {
                        DailyGoalSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "每日目标",
                            subtitle: "\(Int(settings.calorieGoal)) kcal · 蛋白质 \(Int(settings.proteinGoal)) g",
                            symbol: "target",
                            tint: .orange
                        )
                    }
                }

                Section("智能与连接") {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "AI 助手",
                            subtitle: "\(settings.provider.rawValue) · \(settings.aiCanWrite ? "可管理记录" : "只读")",
                            symbol: "wand.and.sparkles",
                            tint: AppTheme.accentSoft
                        )
                    }

                    NavigationLink {
                        SyncAndIntegrationSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "同步与联动",
                            subtitle: syncCoordinator.isConfigured ? syncCoordinator.statusMessage : "尚未配置跨设备同步",
                            symbol: "arrow.triangle.2.circlepath.icloud.fill",
                            tint: AppTheme.recorded
                        )
                    }
                }

                Section("应用") {
                    NavigationLink {
                        PrivacyAndDataSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "隐私、数据与帮助",
                            subtitle: "隐私说明、使用引导与示例数据",
                            symbol: "lock.shield.fill",
                            tint: .blue
                        )
                    }
                }
            }
            .navigationTitle("设置")
            .onAppear { syncCoordinator.refreshConfiguration() }
        }
    }
}

private struct SettingsDestinationLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ProfileSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("个人资料") {
                TextField("称呼（可选）", text: $settings.displayName)
                    .textContentType(.name)
                    .focused($focused)
                Picker("当前目标", selection: $settings.fitnessGoal) {
                    ForEach(FitnessGoal.allCases) { goal in
                        Label(goal.rawValue, systemImage: goal.symbol).tag(goal)
                    }
                }
            }

            Section("身体与体重") {
                SettingsNumberRow(title: "身高", value: $settings.height, unit: "cm", focused: $focused)
                SettingsNumberRow(title: "起始体重", value: $settings.baselineWeight, unit: "kg", focused: $focused)
                SettingsNumberRow(title: "目标体重", value: $settings.targetWeight, unit: "kg", focused: $focused)
                SettingsNumberRow(title: "每周体重变化", value: $settings.weeklyWeightTarget, unit: "kg", focused: $focused)
            }

            Section {
                Button("套用“\(settings.fitnessGoal.rawValue)”建议模板", systemImage: "wand.and.stars") {
                    settings.applyGoalTemplate(settings.fitnessGoal)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } footer: {
                Text("模板只作为起点。请根据连续 2–3 周的体重趋势调整目标。")
            }
        }
        .navigationTitle("身体与目标")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}

private struct DailyGoalSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("营养") {
                SettingsNumberRow(title: "每日热量", value: $settings.calorieGoal, unit: "kcal", focused: $focused)
                SettingsNumberRow(title: "蛋白质", value: $settings.proteinGoal, unit: "g", focused: $focused)
                SettingsNumberRow(title: "碳水", value: $settings.carbsGoal, unit: "g", focused: $focused)
                SettingsNumberRow(title: "脂肪", value: $settings.fatGoal, unit: "g", focused: $focused)
            }
            Section {
                SettingsNumberRow(title: "每日饮水", value: $settings.waterGoal, unit: "ml", focused: $focused)
            } header: {
                Text("饮水")
            } footer: {
                Text("首页饮水量是当天每条饮水记录的毫升数之和；明确记录的饮料也可由 AI 添加。")
            }
        }
        .navigationTitle("每日目标")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}

private struct AISettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showsAPIKeyEditor = false
    @State private var hasAPIKey = false
    @State private var isTesting = false
    @State private var connectionMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("服务") {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("接口地址", text: $settings.endpoint, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focused)
                TextField("模型名称", text: $settings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                Picker("认证方式", selection: $settings.authStyle) {
                    ForEach(AIAuthStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                if settings.authStyle == .custom {
                    TextField("认证请求头名称", text: $settings.customHeaderName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                }
                Button {
                    focused = false
                    showsAPIKeyEditor = true
                } label: {
                    HStack {
                        Label("\(settings.provider.rawValue) API Key", systemImage: "key.horizontal.fill")
                        Spacer()
                        Text(hasAPIKey ? "已保存" : "未设置")
                            .foregroundStyle(hasAPIKey ? AppTheme.success : .secondary)
                    }
                }
                .foregroundStyle(.primary)
                Button {
                    Task { await testConnection() }
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
            }

            Section {
                Toggle("支持图片输入", isOn: $settings.supportsVision)
                Stepper("单次最多照片：\(settings.maxPhotos) 张", value: $settings.maxPhotos, in: 1...12)
                Toggle("允许 AI 新增、修改和删除记录", isOn: $settings.aiCanWrite)
            } header: {
                Text("能力与权限")
            } footer: {
                Text(settings.aiCanWrite
                     ? "AI 仅会按你的明确要求更改数据；删除时必须准确匹配现有记录。"
                     : "AI 只能读取摘要并回答，不会修改任何记录。")
            }

            Section("回答偏好") {
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
                TextField("长期偏好，例如训练安排、忌口", text: $settings.customInstructions, axis: .vertical)
                    .lineLimit(3...7)
                    .focused($focused)
            }
        }
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .sheet(isPresented: $showsAPIKeyEditor, onDismiss: refreshKeyState) {
            APIKeyEditorView(settings: settings)
        }
        .onAppear(perform: refreshKeyState)
        .onChange(of: settings.provider) { _, _ in
            refreshKeyState()
            connectionMessage = nil
        }
    }

    private func refreshKeyState() {
        hasAPIKey = KeychainStore.hasAPIKey(for: settings.provider)
    }

    @MainActor
    private func testConnection() async {
        focused = false
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

private struct SyncAndIntegrationSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.modelContext) private var modelContext
    @State private var showsSyncKeyEditor = false
    @State private var showsLifeTrackUnavailable = false

    var body: some View {
        Form {
            Section {
                Button {
                    showsSyncKeyEditor = true
                } label: {
                    HStack {
                        Label("同步密钥", systemImage: "key.viewfinder")
                        Spacer()
                        Text(syncCoordinator.isConfigured ? "已配置" : "未配置")
                            .foregroundStyle(syncCoordinator.isConfigured ? AppTheme.recorded : .secondary)
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
                Label(syncCoordinator.statusMessage, systemImage: syncCoordinator.lastError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(syncCoordinator.lastError == nil ? AppTheme.recorded : .orange)
                if let date = syncCoordinator.lastSyncedAt {
                    Text("最近同步：\(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("App 与浏览器")
            } footer: {
                Text("餐食、身体数据、饮水记录和每日目标通过私有服务器双向同步。")
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
                    if !LifeLink.openLifeTrack() { showsLifeTrackUnavailable = true }
                } label: {
                    Label("打开 LifeTrack", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("LifeTrack")
            } footer: {
                Text("身高、体重与每日目标通过 App Group 同步给 LifeTrack。")
            }
        }
        .navigationTitle("同步与联动")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsSyncKeyEditor, onDismiss: syncCoordinator.refreshConfiguration) {
            SyncKeyEditorView()
        }
        .onAppear { syncCoordinator.refreshConfiguration() }
        .alert("未安装 LifeTrack", isPresented: $showsLifeTrackUnavailable) {
            Button("好") {}
        } message: {
            Text("请先安装 LifeTrack，或确认两个 App 使用相同的开发者签名。")
        }
    }
}

private struct PrivacyAndDataSettingsView: View {
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.modelContext) private var modelContext
    @State private var showsOnboarding = false

    var body: some View {
        Form {
            Section("隐私") {
                Label(syncCoordinator.isConfigured ? "健康数据仅在本机和你的服务器间同步" : "健康数据默认只保存在本机", systemImage: "lock.shield")
                Label("仅在使用 AI 时发送相关文字与所选图片", systemImage: "arrow.up.forward.app")
                Label("API Key 与同步密钥保存在 iOS 钥匙串", systemImage: "key.fill")
            }
            Section("帮助") {
                Button("重新查看使用引导", systemImage: "book") { showsOnboarding = true }
                Button("重新写入完整示例数据", systemImage: "arrow.counterclockwise") {
                    DemoDataService.reinstall(context: modelContext)
                }
                Button("清除示例数据", systemImage: "trash") {
                    DemoDataService.clear(context: modelContext)
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("隐私、数据与帮助")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsOnboarding) { OnboardingView() }
    }
}

private struct SettingsNumberRow: View {
    let title: String
    @Binding var value: Double
    let unit: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 105)
                .focused(focused)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
        }
    }
}
