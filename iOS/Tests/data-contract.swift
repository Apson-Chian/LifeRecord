import Foundation

@main struct DataContractChecks {
    static func main() throws {
        var fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "../Tests/Fixtures/data-contract.json"))) as! [String: Any]
        if CommandLine.arguments.count > 2 {
            fixture["snapshot"] = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        }
        let data=try JSONSerialization.data(withJSONObject: fixture["snapshot"]!)
        let snapshot=try JSONDecoder().decode(SyncSnapshot.self, from: data)
        precondition(snapshot.meals[0].photoIDs?.count == 12)
        precondition(snapshot.bodyMetrics[0].bodyFat == 78 && snapshot.bodyMetrics[0].waist == nil)
        precondition(snapshot.settings?.height == 70 && snapshot.settings?.weeklyWeightTarget == 3)
        precondition(snapshot.workoutEntries![0].bodyParts == nil)
        let oldData=try JSONSerialization.data(withJSONObject: fixture["legacyMeal"]!)
        let old=try JSONDecoder().decode(SyncedMeal.self, from: oldData)
        precondition(old.note == "" && old.fiber == 0 && old.createdAt == old.date)
        precondition(old.kind == "加餐" && old.source == "手动")
        let again=try JSONDecoder().decode(SyncSnapshot.self, from: JSONEncoder().encode(snapshot))
        precondition(again.meals[0].inputText == "原始描述" && again.meals[0].photoIDs == snapshot.meals[0].photoIDs)
        var raw = fixture["snapshot"] as! [String: Any]
        var malformed = fixture["legacyMeal"] as! [String: Any]
        malformed["id"] = "legacy-meal"
        malformed["customField"] = ["keep": "all"]
        var broken = malformed; broken["id"] = "abcdefab-cdef-4abc-8abc-abcdefabcdef"; broken["note"] = ["bad type"]
        raw["meals"] = (raw["meals"] as! [[String: Any]]) + [malformed, broken]
        let rawData = try JSONSerialization.data(withJSONObject: raw)
        let read = try SyncCompatibility.read(rawData)
        precondition(read.snapshot.meals.count == 1 && read.issues.count == 2)
        precondition(read.original == rawData)
        let preserved = try JSONSerialization.jsonObject(with: read.original) as! [String: Any]
        precondition((preserved["meals"] as! [[String: Any]])[1]["id"] as? String == "legacy-meal")
        var upper = (fixture["snapshot"] as! [String: Any])["meals"] as! [[String: Any]]
        upper[0]["id"] = "abcdefab-cdef-4abc-8abc-abcdefabcdef"
        var alias = upper[0]; alias["id"] = "ABCDEFAB-CDEF-4ABC-8ABC-ABCDEFABCDEF"
        raw["meals"] = upper + [alias]
        let collision = try SyncCompatibility.read(JSONSerialization.data(withJSONObject: raw))
        precondition(collision.snapshot.meals.isEmpty && collision.issues.count == 2)
        // Historical outliers remain readable. New-write validation is separate.
        var historyBody = (raw["bodyMetrics"] as! [[String: Any]])[0]; historyBody["bodyFat"] = 0
        raw["bodyMetrics"] = [historyBody]
        let history = try SyncCompatibility.read(JSONSerialization.data(withJSONObject: raw))
        precondition(history.snapshot.bodyMetrics[0].bodyFat == 0)
        let oldEnvelope: [String: Any] = ["meals": [fixture["legacyMeal"]!], "bodyMetrics": [], "deletions": []]
        let oldWire = try JSONSerialization.data(withJSONObject: oldEnvelope)
        let oldRead = try SyncCompatibility.read(oldWire)
        let typed = try JSONEncoder().encode(oldRead.snapshot)
        let unchanged = try SyncCompatibility.preservingUnchanged(typed, original: oldWire)
        let preservedLegacy = try JSONSerialization.jsonObject(with: unchanged) as! [String: Any]
        let originalLegacy = fixture["legacyMeal"] as! NSDictionary
        precondition((preservedLegacy["meals"] as! [NSDictionary])[0] == originalLegacy)
        let limits = fixture["limits"] as! [String: [String: [Double]]]
        for (kind, fields) in limits {
            for (field, bounds) in fields {
                for value in [bounds[0], bounds[1]] {
                    if kind == "meal" {
                        var values: [String: Double] = ["calories": 600, "protein": 40, "carbs": 70, "fat": 18, "fiber": 6]
                        values[field] = value
                        try RecordInput.meal(name: "边界", calories: values["calories"]!, protein: values["protein"]!, carbs: values["carbs"]!, fat: values["fat"]!, fiber: values["fiber"]!)
                    } else {
                        try RecordInput.number(value, field: field, low: bounds[0], high: bounds[1])
                    }
                }
                for value in [bounds[0] - 1, bounds[1] + 1, Double.infinity, Double.nan] {
                    do { try RecordInput.number(value, field: field, low: bounds[0], high: bounds[1]); preconditionFailure("invalid bound accepted") } catch { }
                }
            }
        }
        if CommandLine.arguments.count > 1 {
            let outbound = try SyncCompatibility.preservingUnchanged(JSONEncoder().encode(snapshot), original: data)
            try outbound.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("PASS: Swift shared contract decoding, null, old missing fields and re-encoding")
    }
}
