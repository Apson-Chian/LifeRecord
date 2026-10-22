import Foundation

/// Keeps every unrepresentable record in an original, exportable wire snapshot.
/// Quarantine is a display boundary, never a deletion or a repaired copy.
enum SyncCompatibility {
    struct Read {
        var snapshot: SyncSnapshot
        var issues: [String]
        var original: Data
    }
    static func read(_ data: Data) throws -> Read {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecordInput.Invalid(field: "snapshot", reason: "需要 JSON 对象")
        }
        var issues: [String] = []
        for (collection, kind) in [("meals", "meal"), ("bodyMetrics", "body"), ("workoutEntries", "workout"), ("deletions", "deletion")] {
            if object[collection] == nil { object[collection] = [[String: Any]](); continue }
            guard let records = object[collection] as? [[String: Any]] else {
                throw RecordInput.Invalid(field: collection, reason: "需要记录数组；原始响应可供诊断")
            }
            let groups = Dictionary(grouping: records) { row in
                let id = (row["id"] as? String)?.lowercased() ?? "<missing>"
                return kind == "deletion" ? "\(row["recordType"] as? String ?? "?"):\(id)" : id
            }
            object[collection] = records.filter { row in
                let id = row["id"] as? String ?? "<missing>"
                let key = kind == "deletion" ? "\(row["recordType"] as? String ?? "?"):\(id.lowercased())" : id.lowercased()
                guard UUID(uuidString: id) != nil, groups[key]?.count == 1 else {
                    issues.append("\(kind) \(id)：历史 ID 无法表示或存在大小写碰撞；原值保留在诊断导出中，请人工核对")
                    return false
                }
                do {
                    let raw = try JSONSerialization.data(withJSONObject: row)
                    let decoder = JSONDecoder()
                    switch kind {
                    case "meal": _ = try decoder.decode(SyncedMeal.self, from: raw)
                    case "body": _ = try decoder.decode(SyncedBodyMetric.self, from: raw)
                    case "workout": _ = try decoder.decode(SyncedWorkout.self, from: raw)
                    default:
                        let deletion = try decoder.decode(SyncedDeletion.self, from: raw)
                        guard ["meal", "body", "workout"].contains(deletion.recordType) else {
                            throw RecordInput.Invalid(field: "recordType", reason: "未知删除类型")
                        }
                    }
                    return true
                } catch {
                    issues.append("\(kind) \(id)：\(error.localizedDescription)；原值保留在诊断导出中")
                    return false
                }
            }
        }
        if let profile = object["settings"], !(profile is NSNull) {
            do {
                let value = try JSONDecoder().decode(SyncedProfile.self, from: JSONSerialization.data(withJSONObject: profile))
                guard ["增肌", "减脂", "维持"].contains(value.fitnessGoal) else {
                    throw RecordInput.Invalid(field: "fitnessGoal", reason: "历史目标无法表示，需人工核对")
                }
            } catch {
                issues.append("settings profile：\(error.localizedDescription)；原始档案保留在诊断导出中")
                object["settings"] = NSNull()
            }
        }
        let projected = try JSONSerialization.data(withJSONObject: object)
        return Read(snapshot: try JSONDecoder().decode(SyncSnapshot.self, from: projected), issues: issues, original: data)
    }
    /// Do not turn a read-time default into a historical write. Only unchanged
    /// versions reuse raw wire records; an explicit edit uses the new typed value.
    static func preservingUnchanged(_ current: Data, original: Data) throws -> Data {
        guard var now = try JSONSerialization.jsonObject(with: current) as? [String: Any],
              let old = try JSONSerialization.jsonObject(with: original) as? [String: Any] else { return current }
        for collection in ["meals", "bodyMetrics", "workoutEntries"] {
            let records = old[collection] as? [[String: Any]] ?? []
            let groups = Dictionary(grouping: records) { ($0["id"] as? String ?? "").lowercased() }
            now[collection] = (now[collection] as? [[String: Any]] ?? []).map { row in
                let matches = groups[(row["id"] as? String ?? "").lowercased()] ?? []
                if matches.count == 1, let previous = matches.first,
                   let stamp = row["updatedAt"] as? Double, stamp == previous["updatedAt"] as? Double {
                    return previous
                }
                return row
            }
        }
        if let profile = now["settings"] as? [String: Any], let previous = old["settings"] as? [String: Any],
           let stamp = profile["updatedAt"] as? Double, stamp == previous["updatedAt"] as? Double {
            var preserved=previous
            // Goal versions merge independently of the current profile's stamp.
            // Keep raw legacy fields without discarding a newly merged offline timeline.
            for field in ["goalHistory","goalTimeZone"] where profile[field] != nil {preserved[field]=profile[field]}
            now["settings"] = preserved
        }
        return try JSONSerialization.data(withJSONObject: now)
    }

}
