import SwiftUI
import PhotosUI
import ImageIO
import UIKit

struct CoachAvatarView: View {
    let data: Data?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable()
            } else {
                Image("CoachAvatar").resizable()
            }
        }
        .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white.opacity(0.75), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

struct CoachProfileView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var avatarData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?

    init(name: String, avatarData: Data?) {
        _name = State(initialValue: name)
        _avatarData = State(initialValue: avatarData)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        CoachAvatarView(data: avatarData, size: 96)
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(isLoadingPhoto ? "正在读取照片…" : "从相册更换头像", systemImage: "photo")
                        }
                        .disabled(isLoadingPhoto)
                        if isLoadingPhoto { ProgressView() }
                        if avatarData != nil {
                            Button("使用默认头像") {
                                photoItem = nil
                                avatarData = nil
                            }
                            .font(.footnote)
                            .disabled(isLoadingPhoto)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section {
                    TextField("教练名称", text: $name)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                    Text("\(trimmedName.count)/30")
                        .font(.caption)
                        .foregroundStyle(trimmedName.count > 30 ? Color.red : Color.secondary)
                } header: {
                    Text("聊天 AI 名称")
                } footer: {
                    Text("名称和头像会应用到所有教练对话，仅保存在这台设备上。")
                }

                Section {
                    Button("恢复默认名称和头像") {
                        name = AppSettings.defaultCoachName
                        photoItem = nil
                        avatarData = nil
                    }
                    .disabled(isLoadingPhoto)
                }
            }
            .navigationTitle("自定义教练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try settings.updateCoachIdentity(name: name, avatarData: avatarData)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(isLoadingPhoto || trimmedName.isEmpty || trimmedName.count > 30)
                }
            }
            .task(id: photoItem) {
                guard let photoItem else { isLoadingPhoto = false; return }
                isLoadingPhoto = true
                do {
                    guard let original = try await photoItem.loadTransferable(type: Data.self) else {
                        throw AvatarError.unreadable
                    }
                    try Task.checkCancellation()
                    guard let prepared = Self.prepareAvatar(original) else { throw AvatarError.unreadable }
                    avatarData = prepared
                } catch {
                    if !Task.isCancelled { errorMessage = error.localizedDescription }
                }
                if !Task.isCancelled { isLoadingPhoto = false }
            }
            .alert("无法保存教练设置", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "请重试")
            }
        }
    }

    private enum AvatarError: LocalizedError {
        case unreadable
        var errorDescription: String? { "无法读取这张照片，请选择另一张图片。原来的头像未改变。" }
    }

    /// Downsample before cropping so even large camera photos stay bounded in memory and storage.
    private static func prepareAvatar(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: thumbnail)
        let side: CGFloat = 512
        let scale = max(side / image.size.width, side / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }.jpegData(compressionQuality: 0.85)
    }
}
