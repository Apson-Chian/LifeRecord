import Foundation
import CryptoKit
import ImageIO

/// Private, bounded cache. Credentials are hashed into the cache identity, never stored on disk.
actor MealPhotoStore {
    enum PhotoError: LocalizedError {
        case invalidImage, unavailable(Int)
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "照片数据无法读取，请重试。"
            case .unavailable(let code):
                if code == 401 || code == 403 { return "照片访问未授权，请检查同步密钥。" }
                if code == 404 { return "这张照片已不存在。" }
                return "照片加载失败（\(code)），请稍后重试。"
            }
        }
    }

    private let directory: URL
    private let budget: Int
    private let memory = NSCache<NSString, NSData>()
    private var pending: [String: Task<Data, Error>] = [:]

    init(directory: URL = URL.cachesDirectory.appendingPathComponent("MealPhotos", isDirectory: true),
         budget: Int = 128 * 1024 * 1024) {
        self.directory = directory
        self.budget = budget
        memory.totalCostLimit = 24 * 1024 * 1024
    }

    private func identity(imageID: String, credential: String) -> String {
        SHA256.hash(data: Data("\(credential):\(imageID.lowercased())".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    func data(imageID: String, credential: String,
              download: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let id = identity(imageID: imageID, credential: credential)
        if let cached = memory.object(forKey: id as NSString) { return cached as Data }
        if let task = pending[id] { return try await task.value }
        let file = directory.appendingPathComponent(id)
        if let data = try? Data(contentsOf: file), Self.isImage(data) {
            memory.setObject(data as NSData, forKey: id as NSString, cost: data.count)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return data
        }
        // One shared download survives an individual thumbnail scrolling off screen.
        let task = Task {
            let data = try await download()
            guard Self.isImage(data) else { throw PhotoError.invalidImage }
            return data
        }
        pending[id] = task
        defer { pending[id] = nil }
        let data = try await task.value
        save(data, id: id)
        return data
    }

    func store(_ data: Data, imageID: String, credential: String) {
        guard Self.isImage(data) else { return }
        save(data, id: identity(imageID: imageID, credential: credential))
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        guard CGImageSourceGetCount(source) > 0, CGImageSourceGetStatus(source) == .statusComplete else { return false }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 16
        ] as CFDictionary) != nil
    }

    private func save(_ data: Data, id: String) {
        memory.setObject(data as NSData, forKey: id as NSString, cost: data.count)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(id)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            trimDisk()
        } catch {
            // Cache storage must never turn a successful download into a failed photo.
        }
    }

    private func trimDisk() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries where total > budget {
            if (try? FileManager.default.removeItem(at: url)) != nil { total -= size }
        }
    }
}
