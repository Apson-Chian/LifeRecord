import Foundation
import CryptoKit
import Observation
import SwiftData


enum SyncServiceError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "请先在设置中配置同步密钥，照片才能安全保存到你的服务器。"
        case .invalidResponse:
            "同步服务器返回了无法识别的数据。"
        case .server(let message):
            message
        }
    }
}

@MainActor
@Observable
final class SyncCoordinator {
    static var baseURL: String { UserDefaults.standard.string(forKey:"sync.base") ?? "https://apsonchian.ltd/liferecord-api" }
    static func endpoint(_ path: String) throws -> URL {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string:base), url.scheme == "https", url.host != nil, url.user == nil, url.fragment == nil, url.query == nil else { throw SyncServiceError.server("同步服务器需要完整 HTTPS 地址") }
        return url.appendingPathComponent(path)
    }
    static func bindIdentity(base: String, key: String) throws {
        guard let url=URL(string:base), url.scheme == "https", url.host != nil, url.user == nil, url.fragment == nil, url.query == nil else { throw SyncServiceError.server("同步服务器需要完整 HTTPS 地址") }
        let hash = SHA256.hash(data:Data((base.trimmingCharacters(in: CharacterSet(charactersIn:"/")) + "\n" + key).utf8)).map { String(format:"%02x",$0) }.joined()
        let previous = UserDefaults.standard.string(forKey:"sync.identity") ?? ""
        guard previous.isEmpty || previous == hash else { throw SyncServiceError.server("此设备已有其他账号数据。请先导出并清除本机数据，再连接新账号。") }
        UserDefaults.standard.set(hash,forKey:"sync.identity")
    }
    private var needsAnotherSync = false
    private let photoStore = MealPhotoStore()
    var compatibilityIssues: [String] = []

    private func diagnosticArchiveURL() throws -> URL {
        let identity = UserDefaults.standard.string(forKey: "sync.identity") ?? ""
        guard !identity.isEmpty, identity.allSatisfy({ $0.isHexDigit }) else { throw SyncServiceError.notConfigured }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true).appendingPathComponent("SyncDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(identity + ".json")
    }

    var isSyncing = false
    var isConfigured = KeychainStore.hasSyncKey
    var lastSyncedAt: Date?
    var statusMessage = "尚未配置跨设备同步"
    var lastError: String?

    func refreshConfiguration() {
        isConfigured = KeychainStore.hasSyncKey
        if !isConfigured {
            statusMessage = "尚未配置跨设备同步"
            lastSyncedAt = nil
        }
    }

    func reportPhotoUploadFailure(_ error: Error) {
        lastError = error.localizedDescription
        statusMessage = "记录已保存，照片未上传"
    }

    func sync(context: ModelContext, settings: AppSettings) async {
        guard !Task.isCancelled else { return }
        let key = KeychainStore.loadSyncKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if isSyncing {
            needsAnotherSync = true
            return
        }
        do { try Self.bindIdentity(base:Self.baseURL,key:key) }
        catch { lastError=error.localizedDescription; statusMessage="账号与本机数据不匹配"; return }
        let baseAtStart = Self.baseURL
        isConfigured = true
        isSyncing = true
        lastError = nil
        statusMessage = "正在同步…"
        defer { isSyncing = false }

        repeat {
            needsAnotherSync = false
            do {
                try Task.checkCancellation()
                let outbound = try makeSnapshot(context: context, settings: settings)
                let inbound = try await exchange(outbound, key: key)
                try Task.checkCancellation()
                guard KeychainStore.loadSyncKey() == key, Self.baseURL == baseAtStart else { throw CancellationError() }
                // Archive before applying the display projection. Failure to retain
                // unreadable originals must never be reported as a complete sync.
                try inbound.original.write(to: diagnosticArchiveURL(), options: .atomic)
                try apply(inbound.snapshot, context: context, settings: settings)
                compatibilityIssues = inbound.issues
                lastSyncedAt = .now
                if inbound.issues.isEmpty {
                    statusMessage = "所有设备已同步"
                } else {
                    statusMessage = "可读取记录已同步；\(inbound.issues.count) 项历史数据待核对"
                    lastError = inbound.issues.prefix(3).joined(separator: "\n") + "\n请在数据导出中保留 compatibilitySnapshot，并按原 ID 人工修正，勿删除原记录。"
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    statusMessage = "同步已暂停，等待下次同步"
                    break
                }
                lastError = SyncFailureDescription.message(for: error)
                statusMessage = "同步失败"
                break
            }
        } while needsAnotherSync
    }

    func uploadMealPhotos(_ images: [Data], mealID: UUID) async throws -> [String] {
        guard !images.isEmpty else { return [] }
        let key = KeychainStore.loadSyncKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SyncServiceError.notConfigured }
        var imageIDs: [String] = []
        for image in images {
            var request = URLRequest(url: try Self.endpoint("images"))
            request.httpMethod = "POST"
            request.timeoutInterval = 45
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "mealId": mealID.uuidString.lowercased(),
                "base64": image.base64EncodedString()
            ])
            let (data, response) = try await PrivateHTTPSession.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SyncServiceError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw SyncServiceError.server(payload?["error"] as? String ?? "照片上传失败（\(http.statusCode)）")
            }
            guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let imageID = payload["id"] as? String else { throw SyncServiceError.invalidResponse }
            imageIDs.append(imageID)
            await photoStore.store(image, imageID: imageID, credential: key)
        }
        return imageIDs
    }

    func mealPhotoData(imageID: String) async throws -> Data {
        let normalizedID = imageID.lowercased()
        guard normalizedID.count == 32,
              normalizedID.allSatisfy({ $0.isHexDigit }) else {
            throw SyncServiceError.invalidResponse
        }
        let key = KeychainStore.loadSyncKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SyncServiceError.notConfigured }
        let endpoint = try Self.endpoint("images").appendingPathComponent(normalizedID)
        return try await photoStore.data(imageID: normalizedID, credential: key) {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 30
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await PrivateHTTPSession.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SyncServiceError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw MealPhotoStore.PhotoError.unavailable(http.statusCode)
            }
            return data
        }
    }

    func clearPhotoCache() async { await photoStore.clear() }

    func exportData(context: ModelContext, settings: AppSettings) throws -> Data {
        let current = try JSONEncoder().encode(makeSnapshot(context:context,settings:settings))
        guard let url = try? diagnosticArchiveURL(), FileManager.default.fileExists(atPath: url.path) else { return current }
        var object = try JSONSerialization.jsonObject(with: current) as! [String: Any]
        object["compatibilitySnapshot"] = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        object["compatibilityNote"] = "只读历史原始快照；不能盲目重放。按原 ID 和当前版本核对后人工修正。"
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func makeSnapshot(context: ModelContext, settings: AppSettings) throws -> SyncSnapshot {
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
            .filter { !$0.isDemo }
            .map {
                SyncedMeal(
                    id: $0.id.uuidString.lowercased(),
                    date: $0.date.timeIntervalSince1970,
                    kind: $0.kindRaw,
                    name: $0.name,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    fiber: $0.fiber,
                    note: $0.note,
                    source: $0.sourceRaw,
                    createdAt: $0.createdAt.timeIntervalSince1970,
                    updatedAt: $0.updatedAt.timeIntervalSince1970,
                    photoIDs: $0.photoIDs,
                    inputText: $0.inputText,
                    sourceConversationID: $0.sourceConversationID
                )
            }
        let bodyMetrics = try context.fetch(FetchDescriptor<BodyMetric>())
            .filter { !$0.isDemo }
            .map {
                SyncedBodyMetric(
                    id: $0.id.uuidString.lowercased(),
                    date: $0.date.timeIntervalSince1970,
                    weight: $0.weight,
                    bodyFat: $0.bodyFat,
                    waist: $0.waist,
                    note: $0.note,
                    updatedAt: $0.updatedAt.timeIntervalSince1970
                )
            }
        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>()).filter { !$0.isDemo }.map {
            SyncedWorkout(exercises: $0.exercises, bodyParts: $0.bodyParts, id: $0.id.uuidString.lowercased(), date: $0.date.timeIntervalSince1970,
                          endDate: $0.endDate?.timeIntervalSince1970, note: $0.note,
                          updatedAt: $0.updatedAt.timeIntervalSince1970)
        }
        let deletions = try context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordType != "water" }
            .map {
            SyncedDeletion(
                id: $0.recordID.uuidString.lowercased(),
                recordType: $0.recordType,
                deletedAt: $0.deletedAt.timeIntervalSince1970
            )
        }
        let profile = SyncedProfile(
            updatedAt: settings.profileUpdatedAt.timeIntervalSince1970,
            displayName: settings.displayName,
            fitnessGoal: settings.fitnessGoal.rawValue,
            height: settings.height,
            baselineWeight: settings.baselineWeight,
            targetWeight: settings.targetWeight,
            weeklyWeightTarget: settings.weeklyWeightTarget,
            calorieGoal: settings.calorieGoal,
            proteinGoal: settings.proteinGoal,
            carbsGoal: settings.carbsGoal,
            fatGoal: settings.fatGoal,
            goalHistory: settings.goalHistory,
            goalTimeZone: settings.goalTimeZone,
        )
        return SyncSnapshot(
            meals: meals,
            bodyMetrics: bodyMetrics,
            workoutEntries: workouts,
            settings: profile,
            deletions: deletions,
            serverTime: nil
        )
    }

    private func exchange(_ snapshot: SyncSnapshot, key: String) async throws -> SyncCompatibility.Read {
        var request = URLRequest(url: try Self.endpoint("sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let encoded = try JSONEncoder().encode(snapshot)
        if let url = try? diagnosticArchiveURL(), let original = try? Data(contentsOf: url) {
            request.httpBody = try SyncCompatibility.preservingUnchanged(encoded, original: original)
        } else { request.httpBody = encoded }
        let (data, response) = try await PrivateHTTPSession.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["error"] as? String ?? "同步服务器错误 \(http.statusCode)"
            throw SyncServiceError.server("HTTP \(http.statusCode)：\(message)")
        }
        return try SyncCompatibility.read(data)
    }

    private func apply(_ snapshot: SyncSnapshot, context callerContext: ModelContext, settings: AppSettings, persist: ((ModelContext) throws -> Void)? = nil) throws {
        // Build and validate the entire inbound plan before touching persistent models.
        func ids(_ values: [String]) throws {
            guard values.allSatisfy({ UUID(uuidString: $0) != nil }),
                  Set(values.map { $0.lowercased() }).count == values.count else { throw SyncServiceError.invalidResponse }
        }
        try ids(snapshot.meals.map(\.id)); try ids(snapshot.bodyMetrics.map(\.id))
        try ids((snapshot.workoutEntries ?? []).map(\.id))
        guard snapshot.deletions.allSatisfy({ UUID(uuidString: $0.id) != nil && ["meal", "body", "workout"].contains($0.recordType) && $0.deletedAt.isFinite }) else { throw SyncServiceError.invalidResponse }
        for workout in snapshot.workoutEntries ?? [] {
            if let exercises = workout.exercises { try WorkoutExercise.validate(exercises) }
            if let parts = workout.bodyParts {
                guard parts.count <= 30, parts.allSatisfy(WorkoutBodyParts.isValid), Set(parts).count == parts.count else { throw SyncServiceError.invalidResponse }
            }
        }
        let dirtyKeys = Set((callerContext.changedModelsArray + callerContext.insertedModelsArray + callerContext.deletedModelsArray).compactMap { model -> String? in
            if let meal = model as? MealEntry { return "meal:" + meal.id.uuidString.lowercased() }
            if let body = model as? BodyMetric { return "body:" + body.id.uuidString.lowercased() }
            if let workout = model as? WorkoutEntry { return "workout:" + workout.id.uuidString.lowercased() }
            return nil
        })
        let context = ModelContext(callerContext.container)
        context.autosaveEnabled = false
        defer { if context.hasChanges { context.rollback() } }
        let localMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let localBody = try context.fetch(FetchDescriptor<BodyMetric>())
        let localWorkouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
        var workoutsByID = Dictionary(uniqueKeysWithValues: localWorkouts.map { ($0.id, $0) })
        let localTombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        var mealsByID = Dictionary(uniqueKeysWithValues: localMeals.map { ($0.id, $0) })
        var bodyByID = Dictionary(uniqueKeysWithValues: localBody.map { ($0.id, $0) })
        var tombstonesByKey = Dictionary(uniqueKeysWithValues: localTombstones.map { ($0.key, $0) })

        var mutations = Set<String>()
        for remote in snapshot.meals where Date(timeIntervalSince1970: remote.updatedAt) > (mealsByID[UUID(uuidString: remote.id)!]?.updatedAt ?? .distantPast) { mutations.insert("meal:" + remote.id.lowercased()) }
        for remote in snapshot.bodyMetrics where Date(timeIntervalSince1970: remote.updatedAt) > (bodyByID[UUID(uuidString: remote.id)!]?.updatedAt ?? .distantPast) { mutations.insert("body:" + remote.id.lowercased()) }
        for remote in snapshot.workoutEntries ?? [] where Date(timeIntervalSince1970: remote.updatedAt) > (workoutsByID[UUID(uuidString: remote.id)!]?.updatedAt ?? .distantPast) { mutations.insert("workout:" + remote.id.lowercased()) }
        for deletion in snapshot.deletions { mutations.insert(deletion.recordType + ":" + deletion.id.lowercased()) }
        guard mutations.isDisjoint(with: dirtyKeys) else {
            throw SyncServiceError.server("同步目标存在未保存草稿，草稿已保留，请先保存或取消后重试")
        }

        for deletion in snapshot.deletions {
            guard let id = UUID(uuidString: deletion.id) else { continue }
            let deletionDate = Date(timeIntervalSince1970: deletion.deletedAt)
            switch deletion.recordType {
            case "meal":
                if let entry = mealsByID.removeValue(forKey: id), entry.updatedAt <= deletionDate { context.delete(entry) }
            case "body":
                if let entry = bodyByID.removeValue(forKey: id), entry.updatedAt <= deletionDate { context.delete(entry) }
            case "workout":
                if let entry = workoutsByID.removeValue(forKey: id), entry.updatedAt <= deletionDate { context.delete(entry) }
            default:
                continue
            }
            let key = "\(deletion.recordType):\(id.uuidString.lowercased())"
            if let existing = tombstonesByKey[key] {
                if deletionDate > existing.deletedAt { existing.deletedAt = deletionDate }
            } else {
                let tombstone = SyncTombstone(recordID: id, recordType: deletion.recordType, deletedAt: deletionDate)
                context.insert(tombstone)
                tombstonesByKey[key] = tombstone
            }
        }

        let deletedKeys = Set(tombstonesByKey.keys)
        for remote in snapshot.meals {
            guard let id = UUID(uuidString: remote.id), !deletedKeys.contains("meal:\(remote.id.lowercased())") else { continue }
            let updatedAt = Date(timeIntervalSince1970: remote.updatedAt)
            if let local = mealsByID[id] {
                guard updatedAt > local.updatedAt else { continue }
                local.date = Date(timeIntervalSince1970: remote.date)
                local.kindRaw = remote.kind
                local.name = remote.name
                local.calories = remote.calories
                local.protein = remote.protein
                local.carbs = remote.carbs
                local.fat = remote.fat
                local.fiber = remote.fiber
                local.note = remote.note
                local.sourceRaw = remote.source
                local.createdAt = Date(timeIntervalSince1970: remote.createdAt)
                local.updatedAt = updatedAt
                if let photoIDs = remote.photoIDs { local.photoIDs = photoIDs }
                if let inputText = remote.inputText { local.inputText = inputText }
                if let conversationID = remote.sourceConversationID { local.sourceConversationID = conversationID }
            } else {
                let entry = MealEntry(
                    id: id,
                    date: Date(timeIntervalSince1970: remote.date),
                    kind: MealKind(rawValue: remote.kind) ?? .snack,
                    name: remote.name,
                    calories: remote.calories,
                    protein: remote.protein,
                    carbs: remote.carbs,
                    fat: remote.fat,
                    fiber: remote.fiber,
                    note: remote.note,
                    source: EntrySource(rawValue: remote.source) ?? .manual,
                    photoIDs: remote.photoIDs ?? [],
                    inputText: remote.inputText ?? "",
                    sourceConversationID: remote.sourceConversationID ?? ""
                )
                entry.kindRaw = remote.kind
                entry.sourceRaw = remote.source
                entry.createdAt = Date(timeIntervalSince1970: remote.createdAt)
                entry.updatedAt = updatedAt
                context.insert(entry)
            }
        }

        for remote in snapshot.bodyMetrics {
            guard let id = UUID(uuidString: remote.id), !deletedKeys.contains("body:\(remote.id.lowercased())") else { continue }
            let updatedAt = Date(timeIntervalSince1970: remote.updatedAt)
            if let local = bodyByID[id] {
                guard updatedAt > local.updatedAt else { continue }
                local.date = Date(timeIntervalSince1970: remote.date)
                local.weight = remote.weight
                local.bodyFat = remote.bodyFat
                local.waist = remote.waist
                local.note = remote.note
                local.updatedAt = updatedAt
            } else {
                let entry = BodyMetric(id: id, date: Date(timeIntervalSince1970: remote.date), weight: remote.weight, bodyFat: remote.bodyFat, waist: remote.waist, note: remote.note)
                entry.updatedAt = updatedAt
                context.insert(entry)
            }
        }

        for remote in snapshot.workoutEntries ?? [] {
            guard let id = UUID(uuidString: remote.id), !deletedKeys.contains("workout:\(remote.id.lowercased())") else { continue }
            let updated = Date(timeIntervalSince1970: remote.updatedAt)
            let existing = workoutsByID[id]
            if let existing, existing.updatedAt >= updated { continue }
            let record = existing ?? WorkoutEntry(id: id)
            if existing == nil { context.insert(record); workoutsByID[id] = record }
            record.date = Date(timeIntervalSince1970: remote.date)
            record.endDate = remote.endDate.map { Date(timeIntervalSince1970: $0) }
            record.note = remote.note
            if let exercises = remote.exercises {
                try WorkoutExercise.validate(exercises)
                record.exercises = exercises
            }
            if let bodyParts = remote.bodyParts {
                guard WorkoutBodyParts.normalized(bodyParts).count == bodyParts.count,
                      Set(bodyParts).count == bodyParts.count else { throw SyncServiceError.invalidResponse }
                record.bodyParts = bodyParts
            }
            record.updatedAt = updated
        }

        try Task.checkCancellation()
        try (persist ?? { try $0.save() })(context)
        // No suspension or cancellation point between database commit and the
        // nonthrowing preference projection. A failed save leaves preferences intact.
        if let profile = snapshot.settings {
            settings.applySyncedProfile(profile, updatedAt: Date(timeIntervalSince1970: profile.updatedAt))
        }
    }
}

@MainActor
enum SyncDeletion {
    static func delete(_ meal: MealEntry, context: ModelContext) {
        if !meal.isDemo { context.insert(SyncTombstone(recordID: meal.id, recordType: "meal")) }
        context.delete(meal)
    }

    static func delete(_ bodyMetric: BodyMetric, context: ModelContext) {
        if !bodyMetric.isDemo { context.insert(SyncTombstone(recordID: bodyMetric.id, recordType: "body")) }
        context.delete(bodyMetric)
    }
}
