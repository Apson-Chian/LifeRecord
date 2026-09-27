import Foundation

actor DownloadCounter {
    var count = 0
    func next() { count += 1 }
}

@main
struct PhotoCacheTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=")!
        let counter = DownloadCounter()
        let cache = MealPhotoStore(directory: root)
        let download: @Sendable () async throws -> Data = {
            await counter.next()
            try await Task.sleep(for: .milliseconds(80))
            return photo
        }
        let results = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<12 {
                group.addTask { try await cache.data(imageID: "a", credential: "test-key", download: download) }
            }
            var values: [Data] = []
            for try await data in group { values.append(data) }
            return values
        }
        let requests = await counter.count
        precondition(results.count == 12 && results.allSatisfy { $0 == photo } && requests == 1)
        print("PASS: 12 simultaneous requests share one download")

        let restarted = MealPhotoStore(directory: root)
        let saved = try await restarted.data(imageID: "a", credential: "test-key") {
            throw URLError(.notConnectedToInternet)
        }
        precondition(saved == photo)
        print("PASS: disk cache survives a new store and works offline")

        do {
            _ = try await restarted.data(imageID: "a", credential: "different-key") { throw URLError(.userAuthenticationRequired) }
            fatalError("Cache leaked across credentials")
        } catch let error as URLError { precondition(error.code == .userAuthenticationRequired) }
        print("PASS: credentials isolate cached photos")

        do {
            _ = try await restarted.data(imageID: "invalid", credential: "test-key") { Data("not an image".utf8) }
            fatalError("Invalid image accepted")
        } catch is MealPhotoStore.PhotoError { }
        let retried = try await restarted.data(imageID: "invalid", credential: "test-key", download: download)
        precondition(retried == photo)
        print("PASS: invalid payload is not cached; retry succeeds")

        let offscreen = Task { try await cache.data(imageID: "cancel", credential: "test-key", download: download) }
        try await Task.sleep(for: .milliseconds(20))
        offscreen.cancel()
        let visible = try await cache.data(imageID: "cancel", credential: "test-key", download: download)
        _ = try await offscreen.value
        precondition(visible == photo)
        let count = await counter.count
        precondition(count == 3)
        print("PASS: an offscreen caller does not cancel the shared download")

        let tinyRoot = root.appendingPathComponent("bounded")
        let bounded = MealPhotoStore(directory: tinyRoot, budget: photo.count)
        await bounded.store(photo, imageID: "one", credential: "test-key")
        await bounded.store(photo, imageID: "two", credential: "test-key")
        let files = try FileManager.default.contentsOfDirectory(at: tinyRoot, includingPropertiesForKeys: [.fileSizeKey])
        let size = try files.reduce(0) { try $0 + $1.resourceValues(forKeys: [.fileSizeKey]).fileSize! }
        precondition(size <= photo.count)
        print("PASS: disk cache evicts older files within its size budget")
    }
}
