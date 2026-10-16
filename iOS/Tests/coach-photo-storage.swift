import Foundation
import SwiftData

@main struct CoachPhotoStorageTests {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("coach-photos-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("chat.sqlite")
        let photos = [Data(repeating: 0x45, count: 300_000), Data(repeating: 0x78, count: 400_000)]
        do {
            let container = try ModelContainer(for: CoachConversation.self, CoachMessage.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            let conversation = CoachConversation()
            context.insert(conversation)
            let message = CoachMessage(role: "user", content: "午餐\n[附带 2 张图片]")
            message.images = photos
            message.generationState = .failed
            message.generationFailure = "网络连接中断"
            message.conversation = conversation
            context.insert(message)
            let legacy = CoachMessage(role: "user", content: "[发送了 1 张图片]")
            legacy.conversation = conversation
            context.insert(legacy)
            try context.save()
        }
        do {
            let container = try ModelContainer(for: CoachConversation.self, CoachMessage.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            let messages = try context.fetch(FetchDescriptor<CoachMessage>())
            let photoMessage = messages.first { !$0.images.isEmpty }!
            assert(photoMessage.images == photos && photoMessage.visibleContent == "午餐")
            assert(photoMessage.generationState == .failed && photoMessage.generationState.canRetry)
            assert(photoMessage.generationFailure == "网络连接中断")
            photoMessage.generationState = .pending
            assert(!photoMessage.recoverInterruptedGeneration(isRunning: true))
            assert(photoMessage.generationState == .pending)
            assert(photoMessage.recoverInterruptedGeneration(isRunning: false))
            assert(photoMessage.generationState == .interrupted && photoMessage.generationState.canRetry)
            assert(photoMessage.images == photos)
            photoMessage.generationState = .applying
            assert(photoMessage.recoverInterruptedGeneration(isRunning: false))
            assert(photoMessage.generationState == .needsReview && !photoMessage.generationState.canRetry)
            photoMessage.generationState = .completed
            assert(!photoMessage.recoverInterruptedGeneration(isRunning: false))
            assert(!photoMessage.generationState.canRetry)
            let legacy = messages.first { $0.imageData == nil }!
            assert(legacy.images.isEmpty && legacy.visibleContent == "[发送了 1 张图片]" && legacy.generationState == .none)
            photoMessage.content = "[发送了 2 张图片]"
            assert(photoMessage.visibleContent.isEmpty)
            context.delete(try context.fetch(FetchDescriptor<CoachConversation>()).first!)
            try context.save()
            let remaining = try context.fetchCount(FetchDescriptor<CoachMessage>())
            assert(remaining == 0)
        }
        print("PASS: multiple chat images persist across reopen; image captions and legacy messages; cascade deletion")
    }
}
