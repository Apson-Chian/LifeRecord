import Foundation

struct WorkoutPartSuggestion: Codable {
    var id: String
    var bodyParts: [String]
}

struct WorkoutPartReviewRecord: Codable, Equatable {
    var id: String
    var date: String
    var bodyParts: [String]
    var note: String
    var exerciseNames: [String]
    var updatedAt: Date
}

struct WorkoutPartReviewReply: Codable {
    var answer: String
    var changes: [WorkoutPartSuggestion]
}

enum WorkoutPartReview {
    enum ReviewError: LocalizedError {
        case invalidReply
        var errorDescription: String? { "AI 返回的部位修改超出当前范围或格式无效，请重新生成预览。" }
    }

    static func validated(_ reply: WorkoutPartReviewReply, records: [WorkoutPartReviewRecord], focusedPart: String?) throws -> WorkoutPartReviewReply {
        let recordIDs = records.map { $0.id.lowercased() }
        let changeIDs = reply.changes.map { $0.id.lowercased() }
        guard Set(recordIDs).count == recordIDs.count,
              reply.changes.count <= 30, Set(changeIDs).count == changeIDs.count else {
            throw ReviewError.invalidReply
        }
        let originals = Dictionary(uniqueKeysWithValues: records.map { ($0.id.lowercased(), $0) })
        var changes: [WorkoutPartSuggestion] = []
        for change in reply.changes {
            guard let record = originals[change.id.lowercased()],
                  focusedPart.map({ record.bodyParts.contains($0) }) ?? true,
                  change.bodyParts.count <= 30,
                  change.bodyParts.allSatisfy({ WorkoutBodyParts.isValid($0) }),
                  Set(change.bodyParts).count == change.bodyParts.count else { throw ReviewError.invalidReply }
            let parts = WorkoutBodyParts.normalized(change.bodyParts)
            if parts != WorkoutBodyParts.normalized(record.bodyParts) {
                changes.append(WorkoutPartSuggestion(id: record.id, bodyParts: parts))
            }
        }
        return WorkoutPartReviewReply(answer: reply.answer, changes: changes)
    }

    static func canApply(original: WorkoutPartReviewRecord, current: WorkoutPartReviewRecord, focusedPart: String?) -> Bool {
        original == current && (focusedPart.map { current.bodyParts.contains($0) } ?? true)
    }
}
