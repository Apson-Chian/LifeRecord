import Foundation

// Defaults and credentials are injected; no real keychain, account or network.
enum KeychainStore {
    static func loadSyncKey() -> String { fatalError("unexpected real credential access") }
    static func saveSyncKey(_ key: String) throws { fatalError("unexpected real credential access") }
}
enum PrivateHTTPSession { static let session = URLSession(configuration: .ephemeral) }

@main struct AccountConnectionChecks {
    @MainActor static func main() async throws {
        let suite = "liferecord-account-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let base = "https://account.invalid/liferecord-api"
        let password = "synthetic password 42!"
        var token = ""
        var calls: [URLRequest] = []
        var responseUser = "alice-id"
        var status = 200
        var failSave = false
        var changeConfiguration = false
        var cancelResponse = false
        var malformed = false
        var echoSecrets = false
        let client = AccountConnection(defaults: defaults, loadKey: { token }, saveKey: {
            if failSave { throw AccountConnection.Failure(message: "synthetic keychain failure") }
            token = $0
        }, transport: { request in
            calls.append(request)
            precondition(request.url?.host == "account.invalid")
            precondition(!request.httpShouldHandleCookies)
            if changeConfiguration { defaults.set("changed", forKey: "sync.identity") }
            if cancelResponse { throw CancellationError() }
            let object: [String: Any]
            if request.url!.lastPathComponent == "me" {
                object = ["userId": "alice-id", "username": "alice"]
            } else if status != 200 {
                let body = request.httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
                object = ["error": echoSecrets ? "echo: \(body?["password"] ?? "") \(body?["currentPassword"] ?? "") \(request.value(forHTTPHeaderField: "Authorization") ?? "")" : "fixture error"]
            } else {
                object = ["userId": responseUser, "username": "alice", "token": malformed ? "" : "session-\(calls.count)",
                          "expiresAt": Date.now.timeIntervalSince1970 + 3600]
            }
            return (try JSONSerialization.data(withJSONObject: object),
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        func reset() {
            defaults.removePersistentDomain(forName: suite)
            token = ""; calls = []; responseUser = "alice-id"; status = 200
            failSave = false; changeConfiguration = false; cancelResponse = false; malformed = false
            echoSecrets = false
        }
        func legacy() {
            defaults.set(base, forKey: "sync.base")
            token = "legacy-key"
            defaults.set(AccountConnection.scope(base: base, key: token), forKey: "sync.identity")
        }
        func rejected(_ operation: () async throws -> Void) async {
            do { try await operation(); preconditionFailure("invalid account transition accepted") }
            catch { }
        }
        // Confirmation and malformed inputs fail before creating an account.
        await rejected { _ = try await client.connect(mode: .register, base: base, username: "alice", password: password, confirmation: "different") }
        await rejected { _ = try await client.connect(mode: .login, base: "http://account.invalid", username: "alice", password: password) }
        await rejected { _ = try await client.connect(mode: .login, base: base, username: "bad name", password: password) }
        precondition(calls.isEmpty && token.isEmpty && defaults.string(forKey: "sync.identity") == nil)
        let registered = try await client.connect(mode: .register, base: base + "/", username: " Alice ", password: password, confirmation: password)
        precondition(registered.userId == "alice-id" && token == registered.token)
        precondition(calls.count == 1 && calls[0].url!.path == "/liferecord-api/account/register")
        precondition(calls[0].value(forHTTPHeaderField: "Authorization") == nil)
        let payload = try JSONDecoder().decode([String: String].self, from: calls[0].httpBody!)
        precondition(payload["username"] == "Alice" && payload["password"] == password)
        precondition(!defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains(password) || String(describing: $0).contains(registered.token) })
        precondition(defaults.string(forKey: "sync.identity") == AccountConnection.scope(base: base, key: token))
        let oldToken = token
        let oldIdentity = defaults.string(forKey: "sync.identity")
        let callCount = calls.count
        await rejected { _ = try await client.connect(mode: .register, base: base, username: "other", password: password, confirmation: password) }
        precondition(calls.count == callCount, "bound device created an unwanted account")
        responseUser = "bob-id"
        await rejected { _ = try await client.connect(mode: .login, base: base, username: "bob", password: password) }
        precondition(token == oldToken && defaults.string(forKey: "sync.identity") == oldIdentity)
        let beforeServerChange = calls.count
        await rejected { _ = try await client.connect(mode: .login, base: "https://other.invalid", username: "alice", password: password) }
        precondition(calls.count == beforeServerChange)
        responseUser = "alice-id"
        // Local disconnect keeps account ownership; the same user may re-login
        // after session expiry without sending an expired credential to /me.
        token = ""
        let relogged = try await client.connect(mode: .login, base: base, username: "alice", password: password)
        precondition(token == relogged.token && calls.last!.url!.lastPathComponent == "login")
        reset(); legacy()
        let migrated = try await client.connect(mode: .credentials, base: base, username: "alice", password: password, confirmation: password)
        precondition(migrated.userId == "alice-id" && calls.count == 2)
        precondition(calls[0].url!.lastPathComponent == "me" && calls[1].url!.lastPathComponent == "credentials")
        precondition(calls.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer legacy-key" })
        // Current password reaches the credential endpoint, never preferences.
        calls = []
        _ = try await client.connect(mode: .credentials, base: base, username: "alice", password: password,
                                     confirmation: password, currentPassword: "old synthetic password")
        let change = try JSONDecoder().decode([String: String].self, from: calls[0].httpBody!)
        precondition(change["currentPassword"] == "old synthetic password")
        reset(); legacy(); responseUser = "bob-id"
        await rejected { _ = try await client.connect(mode: .login, base: base, username: "bob", password: password) }
        precondition(token == "legacy-key" && defaults.string(forKey: "sync.accountId") == nil)
        // Failed server/keychain operations cannot partially switch identity.
        for code in [401, 404, 429, 500] {
            reset(); status = code
            await rejected { _ = try await client.connect(mode: .login, base: base, username: "alice", password: password) }
            precondition(token.isEmpty && defaults.string(forKey: "sync.identity") == nil)
        }
        reset(); failSave = true
        await rejected { _ = try await client.connect(mode: .login, base: base, username: "alice", password: password) }
        precondition(token.isEmpty && defaults.string(forKey: "sync.base") == nil && defaults.string(forKey: "sync.accountId") == nil)
        reset(); malformed = true
        await rejected { _ = try await client.connect(mode: .login, base: base, username: "alice", password: password) }
        precondition(token.isEmpty && defaults.string(forKey: "sync.identity") == nil)
        reset(); changeConfiguration = true
        await rejected { _ = try await client.connect(mode: .login, base: base, username: "alice", password: password) }
        precondition(token.isEmpty && defaults.string(forKey: "sync.identity") == "changed")
        reset(); cancelResponse = true
        await rejected { _ = try await client.connect(mode: .login, base: base, username: "alice", password: password) }
        precondition(token.isEmpty && defaults.string(forKey: "sync.identity") == nil)
        reset(); legacy(); status = 400; echoSecrets = true
        do {
            _ = try await client.connect(mode: .credentials, base: base, username: "alice", password: password,
                                         confirmation: password, currentPassword: "old-password-fixture")
            preconditionFailure("server rejection accepted")
        } catch {
            precondition(!error.localizedDescription.contains(password))
            precondition(!error.localizedDescription.contains("old-password-fixture"))
            precondition(!error.localizedDescription.contains("legacy-key"))
        }
        reset()
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await client.connect(mode: .login, base: base, username: "alice", password: password)
        }
        await rejected { try await cancelled.value }
        precondition(token.isEmpty && defaults.string(forKey: "sync.identity") == nil)
        print("PASS: iOS registration/login, legacy migration, password change, session rotation, cross-account/server isolation, keychain failure, configuration race, cancellation and credential privacy")
    }
}
