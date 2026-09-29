import Foundation
import Photos

enum PhotoLibrarySaveError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "未获得保存照片的权限，请在系统设置中允许生活记录添加照片。"
        case .saveFailed: "系统相册未能保存这张照片，请重试。"
        }
    }
}

@MainActor
enum PhotoLibrarySaver {
    static func save(_ data: Data) async throws {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaveError.permissionDenied
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? PhotoLibrarySaveError.saveFailed) }
            }
        }
    }
}
