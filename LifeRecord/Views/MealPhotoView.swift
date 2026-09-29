import SwiftUI
import ImageIO

struct PhotoSelection: Identifiable {
    let id: String
}

struct MealPhotoView: View {
    @Environment(SyncCoordinator.self) private var syncCoordinator
    let imageID: String
    var preview = false
    var onZoomChange: ((Bool) -> Void)? = nil
    @State private var image: UIImage?
    @State private var errorMessage: String?
    @State private var retry = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                preview ? Color.black : Color(.tertiarySystemFill)
                if let image {
                    if preview {
                        ZoomableMealPhoto(image: image, onZoomChange: onZoomChange)
                    } else {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .accessibilityLabel("餐食照片")
                    }
                } else if let errorMessage {
                    if preview {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                            Text(errorMessage).font(.subheadline).multilineTextAlignment(.center)
                            Button("重新加载", systemImage: "arrow.clockwise") { retry += 1 }
                                .buttonStyle(AppButtonStyle())
                        }.padding(24)
                    } else {
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                            .accessibilityLabel("照片加载失败，打开后可重试")
                    }
                } else {
                    ProgressView().tint(preview ? .white : AppTheme.accent)
                        .accessibilityLabel("正在加载照片")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: "\(imageID)-\(retry)-\(preview)") {
            image = nil
            errorMessage = nil
            do {
                let data = try await syncCoordinator.mealPhotoData(imageID: imageID)
                try Task.checkCancellation()
                let maxPixels = preview ? 2560 : 640
                // ImageIO decodes only the required pixels off the UI thread.
                let decoded = await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return Optional<CGImage>.none }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary)
                }.value
                try Task.checkCancellation()
                guard let decoded else { throw MealPhotoStore.PhotoError.invalidImage }
                image = UIImage(cgImage: decoded)
            } catch is CancellationError {
                // Scrolling away is not a failed download.
            } catch {
                guard !Task.isCancelled else { return }
                if let networkError = error as? URLError {
                    switch networkError.code {
                    case .notConnectedToInternet: errorMessage = "当前没有网络，连接后可重新加载照片。"
                    case .timedOut: errorMessage = "照片加载超时，请稍后重试。"
                    default: errorMessage = "暂时无法连接照片服务器，请检查网络后重试。"
                    }
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct MealPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var syncCoordinator
    let imageIDs: [String]
    @State private var selection: String
    @State private var dragOffset: CGFloat = 0
    @State private var isZoomed = false
    @State private var isSavingPhoto = false
    @State private var photoNotice: String?

    init(imageIDs: [String], initialID: String) {
        var seen = Set<String>()
        self.imageIDs = imageIDs.filter { seen.insert($0).inserted }
        _selection = State(initialValue: initialID)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(imageIDs, id: \.self) { id in
                    // Keep full-size decoding bounded to the visible page and its neighbors.
                    if abs((imageIDs.firstIndex(of: id) ?? 0) - (imageIDs.firstIndex(of: selection) ?? 0)) <= 1 {
                        MealPhotoView(imageID: id, preview: true, onZoomChange: { zoomed in
                            if id == selection { isZoomed = zoomed }
                        }).tag(id)
                    } else {
                        Color.black.tag(id)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .offset(y: dragOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        guard !isZoomed, value.translation.height > 0,
                              abs(value.translation.height) > abs(value.translation.width) * 1.2 else { return }
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        guard dragOffset > 0 else { return }
                        if dragOffset > 110 || value.predictedEndTranslation.height > 180 {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { dragOffset = 0 }
                        }
                    }
            )
            .onChange(of: selection) { _, _ in isZoomed = false; dragOffset = 0 }
            .navigationTitle("\((imageIDs.firstIndex(of: selection) ?? 0) + 1) / \(imageIDs.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSavingPhoto ? "保存中…" : "保存到相册", systemImage: "square.and.arrow.down") {
                        Task { await saveCurrentPhoto() }
                    }.disabled(isSavingPhoto)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { move(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }.disabled(selection == imageIDs.first).accessibilityLabel("上一张照片")
                    Text("左右切换 · 下滑关闭 · 双指缩放")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Button { move(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }.disabled(selection == imageIDs.last).accessibilityLabel("下一张照片")
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.black)
            }
        }
        .preferredColorScheme(.dark)
        .alert("餐食照片", isPresented: Binding(get: { photoNotice != nil }, set: { if !$0 { photoNotice = nil } })) {
            Button("好") { photoNotice = nil }
        } message: { Text(photoNotice ?? "") }
    }

    @MainActor
    private func saveCurrentPhoto() async {
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        do {
            let data = try await syncCoordinator.mealPhotoData(imageID: selection)
            try await PhotoLibrarySaver.save(data)
            photoNotice = "已保存到系统相册。"
        } catch {
            photoNotice = "保存失败：\(error.localizedDescription)"
        }
    }

    private func move(_ offset: Int) {
        guard let current = imageIDs.firstIndex(of: selection), imageIDs.indices.contains(current + offset) else { return }
        selection = imageIDs[current + offset]
    }
}

private struct ZoomableMealPhoto: UIViewRepresentable {
    let image: UIImage
    var onZoomChange: ((Bool) -> Void)?
    func makeUIView(context: Context) -> PhotoZoomScrollView { PhotoZoomScrollView() }
    func updateUIView(_ view: PhotoZoomScrollView, context: Context) {
        view.onZoomChange = onZoomChange
        view.setImage(image)
    }
}

private final class PhotoZoomScrollView: UIScrollView, UIScrollViewDelegate {
    var onZoomChange: ((Bool) -> Void)?
    private let photo = UIImageView()
    private var previousSize = CGSize.zero

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        addSubview(photo)
        photo.contentMode = .scaleAspectFit
        photo.isAccessibilityElement = true
        photo.accessibilityLabel = "餐食照片"
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        guard photo.image !== image else { return }
        photo.image = image
        previousSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != previousSize, bounds.width > 0, bounds.height > 0, let image = photo.image {
            previousSize = bounds.size
            setZoomScale(1, animated: false)
            let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
            photo.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * ratio, height: image.size.height * ratio))
            contentSize = photo.bounds.size
        }
        centerPhoto()
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer && zoomScale <= minimumZoomScale + 0.01 { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPhoto()
        onZoomChange?(zoomScale > minimumZoomScale + 0.01)
    }
    private func centerPhoto() {
        photo.center = CGPoint(x: max(contentSize.width, bounds.width) / 2,
                               y: max(contentSize.height, bounds.height) / 2)
    }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        if zoomScale > 1.01 { setZoomScale(1, animated: animated) }
        else {
            let point = gesture.location(in: photo)
            let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: animated)
        }
    }
}
