import Foundation
import Observation
import SwiftData

struct SyncedProfile: Codable {
    var id = "profile"
    var updatedAt: Double
    var displayName: String
    var fitnessGoal: String
    var height: Double
    var baselineWeight: Double
    var targetWeight: Double
    var weeklyWeightTarget: Double
    var calorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double
    var waterGoal: Double
}

private struct SyncedMeal: Codable {
    var id: String
    var date: Double
    var kind: String
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var note: String
    var source: String
    var createdAt: Double
    var updatedAt: Double
}

private struct SyncedBodyMetric: Codable {
    var id: String
    var date: Double
    var weight: Double
    var bodyFat: Double?
    var waist: Double?
    var note: String
    var updatedAt: Double
}

private struct SyncedWater: Codable {
    var id: String
    var date: Double
    var milliliters: Double
    var note: String
    var updatedAt: Double
}

private struct SyncedDeletion: Codable {
    var id: String
    var recordType: String
    var deletedAt: Double
}

private struct SyncSnapshot: Codable {
    var meals: [SyncedMeal]
    var bodyMetrics: [SyncedBodyMetric]
    var waterEntries: [SyncedWater]
    var settings: SyncedProfile?
    var deletions: [SyncedDeletion]
    var serverTime: Double?
}

enum SyncServiceError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
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
    private static let endpoint = URL(string: "https://apsonchian.ltd/liferecord-api/sync")!

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

    func sync(context: ModelContext, settings: AppSettings) async {
        let key = KeychainStore.loadSyncKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isSyncing else { return }
        isConfigured = true
        isSyncing = true
        lastError = nil
        statusMessage = "正在同步…"
        defer { isSyncing = false }

        do {
            let outbound = try makeSnapshot(context: context, settings: settings)
            let inbound = try await exchange(outbound, key: key)
            try apply(inbound, context: context, settings: settings)
            lastSyncedAt = .now
            statusMessage = "所有设备已同步"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "同步失败"
        }
    }

    private func makeSnapshot(context: ModelContext, settings: AppSettings) throws -> SyncSnapshot {
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
            .filter { !$0.isDemo }
            .map {
                SyncedMeal(
                    id: $0.id.uuidString.lowercased(),
                    date: $0.date.timeIntervalSince1970,
                    kind: $0.kind.rawValue,
                    name: $0.name,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    fiber: $0.fiber,
                    note: $0.note,
                    source: $0.source.rawValue,
                    createdAt: $0.createdAt.timeIntervalSince1970,
                    updatedAt: $0.updatedAt.timeIntervalSince1970
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
        let waterEntries = try context.fetch(FetchDescriptor<WaterEntry>())
            .filter { !$0.isDemo }
            .map {
                SyncedWater(
                    id: $0.id.uuidString.lowercased(),
                    date: $0.date.timeIntervalSince1970,
                    milliliters: $0.milliliters,
                    note: $0.note,
                    updatedAt: $0.updatedAt.timeIntervalSince1970
                )
            }
        let deletions = try context.fetch(FetchDescriptor<SyncTombstone>()).map {
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
            waterGoal: settings.waterGoal
        )
        return SyncSnapshot(
            meals: meals,
            bodyMetrics: bodyMetrics,
            waterEntries: waterEntries,
            settings: profile,
            deletions: deletions,
            serverTime: nil
        )
    }

    private func exchange(_ snapshot: SyncSnapshot, key: String) async throws -> SyncSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(snapshot)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["error"] as? String ?? "同步服务器错误 \(http.statusCode)"
            throw SyncServiceError.server(message)
        }
        guard let result = try? JSONDecoder().decode(SyncSnapshot.self, from: data) else {
            throw SyncServiceError.invalidResponse
        }
        return result
    }

    private func apply(_ snapshot: SyncSnapshot, context: ModelContext, settings: AppSettings) throws {
        let localMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let localBody = try context.fetch(FetchDescriptor<BodyMetric>())
        let localWater = try context.fetch(FetchDescriptor<WaterEntry>())
        let localTombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        var mealsByID = Dictionary(uniqueKeysWithValues: localMeals.map { ($0.id, $0) })
        var bodyByID = Dictionary(uniqueKeysWithValues: localBody.map { ($0.id, $0) })
        var waterByID = Dictionary(uniqueKeysWithValues: localWater.map { ($0.id, $0) })
        var tombstonesByKey = Dictionary(uniqueKeysWithValues: localTombstones.map { ($0.key, $0) })

        for deletion in snapshot.deletions {
            guard let id = UUID(uuidString: deletion.id) else { continue }
            let deletionDate = Date(timeIntervalSince1970: deletion.deletedAt)
            switch deletion.recordType {
            case "meal":
                if let entry = mealsByID.removeValue(forKey: id), entry.updatedAt <= deletionDate { context.delete(entry) }
            case "body":
                if let entry = bodyByID.removeValue(forKey: id), entry.updatedAt <= deletionDate { context.delete(entry) }
            case "water":
                if let entry = waterByID.removeValue(forKey: id), entry.updatedAt <= deletionDate { context.delete(entry) }
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
                    source: EntrySource(rawValue: remote.source) ?? .manual
                )
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

        for remote in snapshot.waterEntries {
            guard let id = UUID(uuidString: remote.id), !deletedKeys.contains("water:\(remote.id.lowercased())") else { continue }
            let updatedAt = Date(timeIntervalSince1970: remote.updatedAt)
            if let local = waterByID[id] {
                guard updatedAt > local.updatedAt else { continue }
                local.date = Date(timeIntervalSince1970: remote.date)
                local.milliliters = remote.milliliters
                local.note = remote.note
                local.updatedAt = updatedAt
            } else {
                let entry = WaterEntry(id: id, date: Date(timeIntervalSince1970: remote.date), milliliters: remote.milliliters, note: remote.note)
                entry.updatedAt = updatedAt
                context.insert(entry)
            }
        }

        if let profile = snapshot.settings {
            settings.applySyncedProfile(profile, updatedAt: Date(timeIntervalSince1970: profile.updatedAt))
        }
        try context.save()
    }
}

@MainActor
enum SyncDeletion {
    static func delete(_ meal: MealEntry, context: ModelContext) {
        context.insert(SyncTombstone(recordID: meal.id, recordType: "meal"))
        context.delete(meal)
    }

    static func delete(_ bodyMetric: BodyMetric, context: ModelContext) {
        context.insert(SyncTombstone(recordID: bodyMetric.id, recordType: "body"))
        context.delete(bodyMetric)
    }

    static func delete(_ water: WaterEntry, context: ModelContext) {
        context.insert(SyncTombstone(recordID: water.id, recordType: "water"))
        context.delete(water)
    }
}
