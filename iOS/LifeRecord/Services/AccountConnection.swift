import Foundation
import CryptoKit

/// Account transitions do not touch records. Only a verified matching user may
/// replace the credential associated with the device's existing data.
@MainActor
final class AccountConnection {
    enum Mode: String, CaseIterable, Identifiable {
        case login = "账号登录", register = "注册账号", credentials = "设置账号密码"
        var id: String { rawValue }
    }
    struct Session: Decodable {
        let userId: String
        let username: String
        let token: String
        let expiresAt: Double
    }
    private struct Identity: Decodable { let userId: String }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    private let defaults: UserDefaults
    private let loadKey: @MainActor () -> String
    private let saveKey: @MainActor (String) throws -> Void
    private let transport: Transport

    init(defaults: UserDefaults = .standard,
         loadKey: @escaping @MainActor () -> String = { KeychainStore.loadSyncKey() },
         saveKey: @escaping @MainActor (String) throws -> Void = { try KeychainStore.saveSyncKey($0) },
         transport: @escaping Transport = { try await PrivateHTTPSession.session.data(for: $0) }) {
        self.defaults = defaults
        self.loadKey = loadKey
        self.saveKey = saveKey
        self.transport = transport
    }

    static func normalizedBase(_ value: String) throws -> String {
        let base = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw Failure(message: "同步服务器需要完整 HTTPS 地址")
        }
        return base
    }

    static func scope(base: String, key: String) -> String {
        SHA256.hash(data: Data((base + "\n" + key).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func validate(mode: Mode, username: String, password: String, confirmation: String) throws {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.range(of: "^[A-Za-z0-9][A-Za-z0-9_.]{2,31}$", options: .regularExpression) != nil else {
            throw Failure(message: "账号需为 3–32 位字母、数字、下划线或点，以字母或数字开头")
        }
        guard !password.isEmpty else { throw Failure(message: "请输入密码") }
        if mode != .login {
            guard (10...128).contains(password.count) else { throw Failure(message: "密码需要 10–128 个字符") }
            guard password == confirmation else { throw Failure(message: "两次输入的密码不一致") }
        }
    }

    func connect(mode: Mode, base: String, username: String, password: String,
                 confirmation: String = "", currentPassword: String = "") async throws -> Session {
        try Task.checkCancellation()
        try Self.validate(mode: mode, username: username, password: password, confirmation: confirmation)
        let base = try Self.normalizedBase(base)
        let oldBase = defaults.string(forKey: "sync.base") ?? "https://apsonchian.ltd/liferecord-api"
        let oldKey = loadKey()
        let previous = defaults.string(forKey: "sync.identity") ?? ""
        let oldUser = defaults.string(forKey: "sync.accountId") ?? ""
        if mode == .register && !previous.isEmpty {
            throw Failure(message: "此设备已绑定账号；请使用原账号登录，或先导出并清除本机数据后再注册")
        }
        // A base change must never carry health records to a different server.
        if !previous.isEmpty && oldBase != base {
            throw Failure(message: "此设备已有其他服务器的账号数据，请先导出并清除本机数据")
        }
        func ensureUnchanged() throws {
            try Task.checkCancellation()
            guard loadKey() == oldKey,
                  (defaults.string(forKey: "sync.base") ?? "https://apsonchian.ltd/liferecord-api") == oldBase,
                  (defaults.string(forKey: "sync.identity") ?? "") == previous,
                  (defaults.string(forKey: "sync.accountId") ?? "") == oldUser else {
                throw Failure(message: "本机配置已更改，请重试")
            }
        }
        var knownUser = oldBase == base ? oldUser : ""
        if !previous.isEmpty && knownUser.isEmpty {
            guard !oldKey.isEmpty, previous == Self.scope(base: oldBase, key: oldKey) else {
                throw Failure(message: "请先用原同步密钥连接，确认本机记录归属后再登录")
            }
            let data = try await request(base: base, path: "me", token: oldKey)
            knownUser = try JSONDecoder().decode(Identity.self, from: data).userId
            guard !knownUser.isEmpty else { throw Failure(message: "服务器未返回账号身份") }
            try ensureUnchanged()
        }
        if mode == .credentials {
            guard !oldKey.isEmpty, !previous.isEmpty, oldBase == base,
                  previous == Self.scope(base: oldBase, key: oldKey) else {
                throw Failure(message: "请先连接原账号或自己的同步密钥，再设置账号密码")
            }
        }
        var payload = ["username": username.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]
        if mode == .credentials { payload["currentPassword"] = currentPassword }
        let path = mode == .credentials ? "credentials" : (mode == .register ? "register" : "login")
        let data = try await request(base: base, path: path, token: mode == .credentials ? oldKey : nil, payload: payload)
        let session = try JSONDecoder().decode(Session.self, from: data)
        try ensureUnchanged()
        guard !session.userId.isEmpty, !session.username.isEmpty, !session.token.isEmpty,
              session.token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }),
              session.expiresAt.isFinite, session.expiresAt > Date.now.timeIntervalSince1970 else {
            throw Failure(message: "服务器返回的登录凭据无效，请重试")
        }
        guard previous.isEmpty || knownUser == session.userId else {
            throw Failure(message: "此设备已有其他账号的数据；请先导出并清除本机数据，再登录新账号")
        }
        // A keychain failure must leave both identity and sync server untouched.
        try saveKey(session.token)
        defaults.set(base, forKey: "sync.base")
        defaults.set(Self.scope(base: base, key: session.token), forKey: "sync.identity")
        defaults.set(session.userId, forKey: "sync.accountId")
        defaults.set(session.username, forKey: "sync.username")
        return session
    }

    private func request(base: String, path: String, token: String? = nil,
                         payload: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: base)!.appendingPathComponent("account").appendingPathComponent(path))
        request.httpMethod = payload == nil ? "GET" : "POST"
        request.timeoutInterval = 30
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
        }
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse else { throw Failure(message: "服务器响应无效") }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 404 { throw Failure(message: "当前服务器尚未启用账号功能，请升级同步服务；已有用户可继续使用密钥连接") }
            if response.statusCode == 401 { throw Failure(message: path == "login" ? "账号或密码不正确" : "登录已过期，请重新登录原账号") }
            if response.statusCode == 429 { throw Failure(message: "尝试次数过多，请稍后再试") }
            var error = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? "账号服务暂时不可用（HTTP \(response.statusCode)）"
            // A custom server may echo the request. Never surface passwords or
            // bearer credentials in the UI, including partial failure reports.
            for secret in [token, payload?["password"], payload?["currentPassword"]].compactMap({ $0 }) where !secret.isEmpty {
                error = error.replacingOccurrences(of: secret, with: "[凭据已隐藏]")
            }
            throw Failure(message: String(error.prefix(240)))
        }
        return data
    }
}
