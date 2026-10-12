import Foundation

@main
struct WorkoutPartReviewTests {
    static func main() throws {
        let id = UUID().uuidString
        let record = WorkoutPartReviewRecord(id: id, date: "2026-10-12T08:00:00+08:00", bodyParts: ["胸部", "手臂"],
                                             note: "卧推和三头", exerciseNames: ["卧推"], updatedAt: Date(timeIntervalSince1970: 100))
        let json = "{\"answer\":\"请核对\",\"changes\":[{\"id\":\"\(id.lowercased())\",\"bodyParts\":[\"胸部\",\"三头\"]}]}"
        let reply = try JSONDecoder().decode(WorkoutPartReviewReply.self, from: Data(json.utf8))
        let valid = try WorkoutPartReview.validated(reply, records: [record], focusedPart: "手臂")
        assert(valid.changes.count == 1 && valid.changes[0].id == id && valid.changes[0].bodyParts == ["胸部", "三头"])
        func rejected(_ changes: [WorkoutPartSuggestion], records: [WorkoutPartReviewRecord] = [record], focus: String? = nil) {
            do {
                _ = try WorkoutPartReview.validated(.init(answer: "", changes: changes), records: records, focusedPart: focus)
                assertionFailure("Invalid modification accepted")
            } catch {}
        }
        rejected([.init(id: UUID().uuidString, bodyParts: ["三头"])])
        rejected([reply.changes[0], .init(id: id, bodyParts: ["二头"])]) // Case-insensitive duplicate ID.
        rejected([.init(id: id, bodyParts: ["三头", "三头"])])
        rejected([.init(id: id, bodyParts: [" 三头"])])
        rejected([.init(id: id, bodyParts: ["未分类"])])
        rejected([.init(id: id, bodyParts: ["三头\n"])])
        rejected(reply.changes, focus: "背部")
        rejected(reply.changes, records: [record, record])
        rejected([.init(id: id, bodyParts: (0..<31).map { "自定义\($0)" })])
        let manyRecords = (0..<31).map { _ -> WorkoutPartReviewRecord in
            var copy = record; copy.id = UUID().uuidString; return copy
        }
        rejected(manyRecords.map { .init(id: $0.id, bodyParts: ["三头"]) }, records: manyRecords)
        let unchanged = try WorkoutPartReview.validated(.init(answer: "", changes: [.init(id: id, bodyParts: ["手臂", "胸部"])]), records: [record], focusedPart: nil)
        assert(unchanged.changes.isEmpty)
        let clear = try WorkoutPartReview.validated(.init(answer: "", changes: [.init(id: id, bodyParts: [])]), records: [record], focusedPart: nil)
        assert(clear.changes[0].bodyParts.isEmpty) // Explicitly clearing tags remains possible.
        assert(WorkoutPartReview.canApply(original: record, current: record, focusedPart: "手臂"))
        assert(!WorkoutPartReview.canApply(original: record, current: record, focusedPart: "背部"))
        var edited = record; edited.updatedAt = record.updatedAt.addingTimeInterval(1)
        assert(!WorkoutPartReview.canApply(original: record, current: edited, focusedPart: nil))
        edited = record; edited.note = "修改了备注"
        assert(!WorkoutPartReview.canApply(original: record, current: edited, focusedPart: nil))
        edited = record; edited.bodyParts = ["二头"]
        assert(!WorkoutPartReview.canApply(original: record, current: edited, focusedPart: nil))
        edited = record; edited.date = "2026-10-11T08:00:00+08:00"
        assert(!WorkoutPartReview.canApply(original: record, current: edited, focusedPart: nil))
        print("PASS: scoped preview validation, canonical IDs, limits, no-op changes and concurrent edits")
    }
}
