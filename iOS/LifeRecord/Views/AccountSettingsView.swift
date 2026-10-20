import SwiftUI

struct AccountSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.modelContext) private var modelContext
    @AppStorage("sync.username") private var savedUsername = ""
    @State private var mode = AccountConnection.Mode.login
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var currentPassword = ""
    @State private var base = SyncCoordinator.baseURL
    @State private var working = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showsKeyEditor = false
    @State private var showsDisconnect = false
    @FocusState private var focused: Bool

    private var busy: Bool { working || syncCoordinator.isSyncing }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 13) {
                    IconBadge(symbol: "person.crop.circle", tint: AppTheme.accent, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(syncCoordinator.isConfigured ? (savedUsername.isEmpty ? "已连接私有同步" : savedUsername) : "让记录，随你同行")
                            .font(.title3.weight(.semibold))
                        Text(syncCoordinator.isConfigured ? "已连接 · 记录会在设备间同步" : "登录后，在其他设备继续记录")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
                Text("同步餐食、身体测量、训练和目标。常用餐食、动作库与教练对话保留在本机。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Picker("连接方式", selection: $mode) {
                    ForEach(AccountConnection.Mode.allCases.filter { $0 != .credentials || syncCoordinator.isConfigured }) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .disabled(busy)
                .accessibilityIdentifier("account-mode")
                TextField("账号", text: $username)
                    .textContentType(.username).keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused).accessibilityIdentifier("account-username")
                if mode == .credentials {
                    SecureField("当前密码（首次设置留空）", text: $currentPassword)
                        .textContentType(.password).focused($focused)
                }
                SecureField(mode == .login ? "密码" : "新密码（10–128 个字符）", text: $password)
                    .textContentType(mode == .login ? .password : .newPassword)
                    .focused($focused).accessibilityIdentifier("account-password")
                if mode != .login {
                    SecureField("确认新密码", text: $confirmation)
                        .textContentType(.newPassword).focused($focused)
                        .accessibilityIdentifier("account-confirmation")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.red)
                        .accessibilityIdentifier("account-error")
                }
                if let successMessage {
                    Label(successMessage, systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(AppTheme.recorded)
                }
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text(working ? "正在连接…" : mode == .register ? "注册并同步" : mode == .credentials ? "保存账号密码" : "登录并同步")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .fontWeight(.semibold)
                .disabled(busy || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                .accessibilityIdentifier("account-submit")
            } header: {
                Text(mode == .register ? "创建你的 LifeRecord 账号" : mode == .credentials ? "设置你的登录方式" : "欢迎回来")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("账号为 3–32 位字母、数字、下划线或点，以字母或数字开头。")
                    if mode == .register {
                        Text("无需邀请码。注册后自动登录，并同步这台设备尚未绑定账号的本机记录。")
                    } else if mode == .credentials {
                        Text("修改账号或密码需要当前密码；原密钥用户首次设置时，当前密码留空。")
                    }
                    Text("密码只用于请求，不保存在本机。登录凭据保存在 iOS 钥匙串；会话到期后需重新登录。")
                }
            }
            .disabled(working)

            Section {
                Button("使用原有同步密钥", systemImage: "key") { showsKeyEditor = true }
                    .disabled(busy)
                DisclosureGroup("同步服务器") {
                    TextField("服务器（HTTPS）", text: $base, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).focused($focused).disabled(busy)
                }
                if syncCoordinator.isConfigured {
                    Button("立即同步", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
                    }.disabled(busy)
                    Button("关闭同步", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        showsDisconnect = true
                    }.disabled(busy)
                }
                NavigationLink("同步状态与 LifeTrack 联动") { SyncAndIntegrationSettingsView() }
                    .disabled(busy)
            }
        }
        .navigationTitle("账号与同步")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .keyboardDoneButton()
        .interactiveDismissDisabled(working)
        .onAppear {
            syncCoordinator.refreshConfiguration()
            if username.isEmpty { username = savedUsername }
        }
        .onChange(of: mode) { _, _ in
            clearPasswords(); errorMessage = nil; successMessage = nil
        }
        .onDisappear { clearPasswords() }
        .sheet(isPresented: $showsKeyEditor, onDismiss: syncCoordinator.refreshConfiguration) { SyncKeyEditorView() }
        .alert("关闭同步？", isPresented: $showsDisconnect) {
            Button("关闭同步", role: .destructive) {
                do {
                    guard !busy else { return }
                    try KeychainStore.deleteSyncKey()
                    syncCoordinator.refreshConfiguration()
                    clearPasswords(); mode = .login
                    successMessage = "同步已关闭，本机记录已保留。"
                    errorMessage = nil
                } catch { errorMessage = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机记录和账号归属会保留。恢复时请登录原账号；连接其他账号前需先导出并清除本机数据。")
        }
    }

    @MainActor private func connect() async {
        guard !busy else { return }
        focused = false; working = true; errorMessage = nil; successMessage = nil
        defer { working = false }
        do {
            // Share the sync lock so periodic sync/local reset cannot race a
            // credential rotation. Release it before requesting the first sync.
            syncCoordinator.isSyncing = true
            do {
                defer { syncCoordinator.isSyncing = false }
                let session = try await AccountConnection().connect(mode: mode, base: base, username: username,
                    password: password, confirmation: confirmation, currentPassword: currentPassword)
                settings.syncBaseURL = try AccountConnection.normalizedBase(base)
                username = session.username
            }
            clearPasswords(); mode = .login
            syncCoordinator.refreshConfiguration()
            await syncCoordinator.sync(context: modelContext, settings: settings)
            if let error = syncCoordinator.lastError {
                errorMessage = "账号已连接，但同步未完成：\(error)"
            } else { successMessage = "账号已连接，记录已同步。" }
        } catch {
            clearPasswords()
            errorMessage = error.localizedDescription
        }
    }

    private func clearPasswords() {
        password = ""; confirmation = ""; currentPassword = ""
    }
}
