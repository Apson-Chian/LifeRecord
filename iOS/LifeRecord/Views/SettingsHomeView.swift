import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator

    var body: some View {
        NavigationStack {
            Form {
                Section("日常使用") {
                    NavigationLink { ProfileSettingsView() } label: {
                        SettingsDestinationLabel(title: "个人与目标", subtitle: "\(settings.fitnessGoal.rawValue) · 身体与营养", symbol: "person", tint: AppTheme.accent)
                    }
                    NavigationLink { RecordingSettingsView() } label: {
                        SettingsDestinationLabel(title: "记录与提醒", symbol: AppSymbol.workout, tint: .teal)
                    }
                    NavigationLink { CoachSettingsView() } label: {
                        SettingsDestinationLabel(title: "教练与 AI", subtitle: settings.provider.rawValue, symbol: AppSymbol.coach, tint: AppTheme.accentSoft)
                    }
                }
                Section("应用与数据") {
                    NavigationLink { PersonalizationSettingsView() } label: {
                        SettingsDestinationLabel(title: "外观与个性化", symbol: "paintpalette", tint: .orange)
                    }
                    NavigationLink { SyncAndIntegrationSettingsView() } label: {
                        SettingsDestinationLabel(title: "同步与联动", subtitle: syncCoordinator.isConfigured ? "已配置" : "未配置", symbol: "arrow.triangle.2.circlepath", tint: AppTheme.recorded)
                    }
                    NavigationLink { PrivacyAndDataSettingsView() } label: {
                        SettingsDestinationLabel(title: "隐私、数据与帮助", symbol: "lock.shield", tint: .blue)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("设置")
            .onAppear { syncCoordinator.refreshConfiguration() }
        }
    }
}

private struct SettingsDestinationLabel: View {
    let title: String
    var subtitle: String = ""
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            IconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 7)
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

            Section("每日营养目标") {
                SettingsNumberRow(title: "每日热量", value: $settings.calorieGoal, unit: "kcal", focused: $focused)
                SettingsNumberRow(title: "蛋白质", value: $settings.proteinGoal, unit: "g", focused: $focused)
                SettingsNumberRow(title: "碳水", value: $settings.carbsGoal, unit: "g", focused: $focused)
                SettingsNumberRow(title: "脂肪", value: $settings.fatGoal, unit: "g", focused: $focused)
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
        .navigationTitle("个人与目标")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
    }
}

private struct RecordingSettingsView: View {
    var body: some View {
        Form {
            Section("常用记录") {
                NavigationLink { FavoriteFoodsView() } label: {
                    SettingsDestinationLabel(title: "常用餐食", symbol: AppSymbol.meal, tint: .orange)
                }
                NavigationLink { ExerciseLibraryView() } label: {
                    SettingsDestinationLabel(title: "我的动作库", symbol: AppSymbol.workout, tint: .teal)
                }
            }
            Section {
                NavigationLink { ReminderSettingsView() } label: {
                    SettingsDestinationLabel(title: "漏记提醒", symbol: "bell", tint: .orange)
                }
            }
        }
        .navigationTitle("记录与提醒").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CoachSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showsProfile = false
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("教练") {
                Button { showsProfile = true } label: {
                    HStack(spacing: 12) {
                        CoachAvatarView(data: settings.coachAvatarData, size: 36)
                        Text(settings.coachName).foregroundStyle(.primary)
                        Spacer()
                        Text("名称与头像").foregroundStyle(.secondary).font(.subheadline)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                TextField("长期偏好，例如训练安排、忌口", text: $settings.customInstructions, axis: .vertical)
                    .lineLimit(3...6).focused($focused)
            }
            Section {
                Toggle("允许 AI 修改记录", isOn: $settings.aiCanWrite)
            } footer: {
                Text(settings.aiCanWrite ? "按你的明确要求更改记录。" : "只读模式，仅分析和回答。")
            }
            Section {
                NavigationLink { AISettingsView() } label: {
                    SettingsDestinationLabel(title: "接口与模型", subtitle: "\(settings.provider.rawValue) · \(settings.model)", symbol: "network", tint: AppTheme.accent)
                }
            }
        }
        .navigationTitle("教练与 AI").navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .sheet(isPresented: $showsProfile) { CoachProfileView(name: settings.coachName, avatarData: settings.coachAvatarData) }
    }
}

private struct AISettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showsAPIKeyEditor = false
    @State private var hasAPIKey = false
    @State private var isTesting = false
    @State private var connectionMessage: String?
    @FocusState private var focused: Bool

    @State private var profileName = ""
    @State private var selectedProfile = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                DisclosureGroup("保存与切换接口") {
                Picker("选择配置", selection:$selectedProfile) {
                    Text("当前配置").tag("")
                    ForEach(settings.savedAPIProfiles) { Text($0.name).tag($0.id) }
                }
                .onChange(of:selectedProfile) { _, id in
                    if let p=settings.savedAPIProfiles.first(where:{$0.id == id}) { settings.loadAPIProfile(id);profileName=p.name;refreshKeyState() }
                }
                TextField("配置名称", text:$profileName)
                Button("另存为新配置") { saveProfile(updating:false) }
                if !selectedProfile.isEmpty {
                    Button("更新所选配置") { saveProfile(updating:true) }
                    Button("删除所选配置",role:.destructive) { settings.deleteAPIProfile(selectedProfile);selectedProfile="";profileName="" }
                }
                Text("接口配置保存在本机，密钥单独保存在钥匙串。删除配置不会删除健康记录或密钥。")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("服务") {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0) }
                }
                if settings.provider == .builtin {
                    Text("无需填写 API Key。先在同步设置中连接你的独立账号；相关文字、记录与所选照片会由云端处理，也可切换自己的接口。")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
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
                }
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Label("测试当前配置", systemImage: "network")
                        Spacer()
                        if isTesting { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isTesting || (settings.provider == .builtin ? !KeychainStore.hasSyncKey : !hasAPIKey))
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
            } header: {
                Text("图片输入")
            }

            if settings.provider != .builtin {
            Section {
                DisclosureGroup("高级接口参数") {
                Picker("输出 Token 参数",selection:$settings.tokenParameter) {
                    Text("max_tokens").tag("max_tokens")
                    Text("max_completion_tokens").tag("max_completion_tokens")
                }
                Picker("图片 detail 参数", selection:$settings.imageDetail) {
                    Text("不发送").tag("");Text("low").tag("low");Text("medium").tag("medium");Text("high").tag("high");Text("auto").tag("auto")
                }
                Toggle("发送 Temperature",isOn:$settings.sendTemperature)
                Toggle("发送 JSON 格式参数",isOn:$settings.jsonMode)
                TextField("额外请求参数 JSON（例如 top_p）",text:$settings.extraBody,axis:.vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(3...8)
                Text("兼容 OpenAI Chat Completions。改地址后需重新保存密钥；扩展参数不要填写密钥，也不能覆盖模型与消息。")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            }
            Section {
                DisclosureGroup("生成参数") {
                if settings.provider != .builtin {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("创造性")
                        Spacer()
                        Text(settings.temperature.formatted(.number.precision(.fractionLength(1))))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.temperature, in: 0...2, step: 0.1)
                }
                }
                Stepper("最长回复：\(settings.maxTokens) tokens", value: $settings.maxTokens, in: 256...(settings.provider == .builtin ? 4096 : 65536), step: 256)
                }
            }
        }
        .navigationTitle("接口与模型")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .sheet(isPresented: $showsAPIKeyEditor, onDismiss: refreshKeyState) {
            APIKeyEditorView(settings: settings)
        }
        .onAppear(perform: refreshKeyState)
        .onChange(of: settings.endpoint) { _, _ in refreshKeyState(); connectionMessage = nil }
        .onChange(of: settings.provider) { _, _ in
            refreshKeyState()
            connectionMessage = nil
        }
    }

    private func saveProfile(updating: Bool) {
        do { selectedProfile = try settings.saveAPIProfile(name:profileName, updating:updating ? selectedProfile : nil);connectionMessage="配置已保存" }
        catch { connectionMessage=error.localizedDescription }
    }

    private func refreshKeyState() {
        hasAPIKey = KeychainStore.hasAPIKey(for: settings.provider, endpoint: settings.endpoint)
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
        @Bindable var settings = settings
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
                if let error = syncCoordinator.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("同步失败原因：\(error)")
                }
                if let date = syncCoordinator.lastSyncedAt {
                    Text("最近同步：\(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("App 与浏览器")
            } footer: {
                Text("餐食、身体数据和每日营养目标通过私有服务器双向同步。")
            }

            Section {
                Toggle("与 LifeTrack 共享身体与每日摘要",isOn: $settings.shareWithLifeTrack)
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
    @Environment(AppSettings.self) private var settings
    @EnvironmentObject private var coachTasks: CoachTaskCenter
    @State private var showsReset = false
    @State private var dataError: String?
    @State private var exportURL: URL?
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
            Section("数据") {
                Button("导出同步记录",systemImage:"square.and.arrow.up") {
                    do {
                        let data=try syncCoordinator.exportData(context:modelContext,settings:settings)
                        let url=URL.temporaryDirectory.appendingPathComponent("LifeRecord-export.json")
                        try data.write(to:url,options:.atomic); exportURL=url
                    } catch { dataError=error.localizedDescription }
                }
                if let exportURL { ShareLink("分享导出文件",item:exportURL) }
                Button("清除全部本机数据",systemImage:"trash",role:.destructive) { showsReset=true }
                    .disabled(syncCoordinator.isSyncing || coachTasks.isGenerating)
                if let dataError { Text(dataError).font(.caption).foregroundStyle(.red) }
                Text("导出包含餐食、身体、训练、目标和删除标记；不含密钥、照片字节、常用餐食和对话。清除本机数据同时移除密钥与接口偏好；云端记录仍保留。")
                    .font(.caption).foregroundStyle(.secondary)
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
        .confirmationDialog("清除全部本机数据？请先导出需要保留的记录。",isPresented:$showsReset,titleVisibility:.visible) {
            Button("清除",role:.destructive) {
                do {
                    guard !syncCoordinator.isSyncing && !coachTasks.isGenerating else { throw SyncServiceError.server("请等待同步与 AI 任务结束") }
                    try KeychainStore.clearAllSecrets()
                    try modelContext.delete(model:MealEntry.self)
                    try modelContext.delete(model:BodyMetric.self)
                    try modelContext.delete(model:WorkoutEntry.self)
                    try modelContext.delete(model:WaterEntry.self)
                    try modelContext.delete(model:FavoriteFood.self)
                    try modelContext.delete(model:CoachMessage.self)
                    try modelContext.delete(model:CoachConversation.self)
                    try modelContext.delete(model:SyncTombstone.self)
                    try modelContext.save()
                    Task { await syncCoordinator.clearPhotoCache() }
                    UserDefaults.standard.removeObject(forKey:"recordQuality.acknowledged")
                    UserDefaults.standard.removeObject(forKey:"sync.identity")
                    SharedProfileStore.clear()
                    if let bundleID=Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName:bundleID) }
                    settings.resetAfterLocalDeletion()
                    if let exportURL { try? FileManager.default.removeItem(at:exportURL) };exportURL=nil
                    syncCoordinator.refreshConfiguration()
                } catch { dataError=error.localizedDescription }
            }
            Button("取消",role:.cancel) {}
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

private struct PersonalizationSettingsView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker("主题模式",selection:$settings.appearance) {
                Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
            }
            Picker("强调色",selection:$settings.accentColor) {
                Text("紫色").tag("purple"); Text("蓝色").tag("blue"); Text("绿色").tag("green"); Text("橙色").tag("orange")
            }
            Text("称呼、目标、提醒、常用餐食、动作库和 AI 长期偏好可在对应设置中自定义。")
                .font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("外观与个性化").navigationBarTitleDisplayMode(.inline)
    }
}
