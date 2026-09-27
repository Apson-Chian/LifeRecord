import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import AVFoundation

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator

    let defaultDate: Date
    @State private var date: Date
    @State private var kind: MealKind
    @State private var scanMode: MealScanMode = .meal
    @State private var description = ""
    @State private var draft = MealDraft()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imageData: [Data] = []
    @State private var isLoadingPhotos = false
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var showsCamera = false
    @State private var isRequestingCamera = false
    @State private var errorMessage: String?
    @State private var wasAIAnalyzed = false
    @FocusState private var focusedField: Field?

    private enum Field { case description, name, nutrition, note }

    init(defaultDate: Date) {
        self.defaultDate = defaultDate
        _date = State(initialValue: defaultDate)
        let hour = Calendar.current.component(.hour, from: defaultDate)
        _kind = State(initialValue: hour < 10 ? .breakfast : (hour < 15 ? .lunch : (hour < 21 ? .dinner : .snack)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("识别类型", selection: $scanMode) {
                        ForEach(MealScanMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    TextField("例如：一碗牛肉面，少油，加一个蛋", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .description)
                    HStack(spacing: 0) {
                        Button {
                            Task { await openCamera() }
                        } label: {
                            Label("拍照", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(
                            isAnalyzing || isLoadingPhotos || isRequestingCamera || imageData.count >= settings.maxPhotos
                            || !UIImagePickerController.isSourceTypeAvailable(.camera)
                        )

                        Divider().frame(height: 24)

                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: max(settings.maxPhotos - imageData.count, 1),
                            selectionBehavior: .ordered,
                            matching: .images
                        ) {
                            Label("从相册选择", systemImage: "photo.stack")
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .disabled(isAnalyzing || isLoadingPhotos || isRequestingCamera || imageData.count >= settings.maxPhotos)
                    }
                    // Form 的自动按钮样式会把同一行的操作一起触发。
                    .buttonStyle(.borderless)
                    .onChange(of: photoItems) { _, items in
                        guard !items.isEmpty else { return }
                        Task { await loadPhotos(items) }
                    }
                    photoPreview
                    Button {
                        Task { await analyze() }
                    } label: {
                        HStack {
                            Label(imageData.isEmpty ? "用 AI 估算营养" : "重新分析照片", systemImage: "sparkles")
                            Spacer()
                            if isAnalyzing { ProgressView() }
                        }
                    }
                    .disabled(isAnalyzing || isLoadingPhotos || (description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData.isEmpty))
                } header: {
                    Text("这顿吃了什么")
                } footer: {
                    Text(syncCoordinator.isConfigured
                         ? "照片和文字会发送到你配置的 AI 服务商；保存餐食后，照片会存入你的私有服务器。结果只是估算，保存前请复核。"
                         : "照片和文字会发送到你配置的 AI 服务商。当前未配置私有同步，照片不会长期保存；营养记录仍可正常保存。")
                }

                Section("记录") {
                    Picker("餐次", selection: $kind) {
                        ForEach(MealKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("时间", selection: $date)
                    TextField("餐食名称", text: $draft.name)
                        .focused($focusedField, equals: .name)
                }

                Section("营养估算") {
                    numberField("热量", value: $draft.calories, unit: "kcal")
                    numberField("蛋白质", value: $draft.protein, unit: "g")
                    numberField("碳水", value: $draft.carbs, unit: "g")
                    numberField("脂肪", value: $draft.fat, unit: "g")
                    numberField("膳食纤维", value: $draft.fiber, unit: "g")
                }

                Section("备注") {
                    TextField("份量、烹饪方式或训练感受", text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .note)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissControl()
            .navigationTitle("记录餐食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isAnalyzing || isLoadingPhotos || isSaving)
                }
            }
            .alert("无法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraImagePicker { image in
                    Task { await addCameraPhoto(image) }
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if !imageData.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(imageData.enumerated()), id: \.offset) { index, data in
                        if let image = UIImage(data: data) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Button {
                                    imageData.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.65))
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func numberField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .focused($focusedField, equals: .nutrition)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func analyze() async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            draft = try await AIClient(settings: settings).analyzeMeal(description: description, images: imageData, mode: scanMode)
            wasAIAnalyzed = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        let remaining = max(settings.maxPhotos - imageData.count, 0)
        var loaded = imageData
        var failedCount = 0
        for item in items.prefix(remaining) {
            guard let original = try? await item.loadTransferable(type: Data.self) else { continue }
            loaded.append(AIClient.jpegImageData(forSending: original, maxDimension: 1280))
        }
        failedCount = min(items.count, remaining) - (loaded.count - imageData.count)
        imageData = loaded
        photoItems = []
        isLoadingPhotos = false
        if failedCount > 0 { errorMessage = "有 \(failedCount) 张照片无法读取，请重新选择。" }
        if !loaded.isEmpty { await analyze() }
    }

    @MainActor
    private func openCamera() async {
        guard !isRequestingCamera, !showsCamera,
              UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        focusedField = nil
        isRequestingCamera = true
        defer { isRequestingCamera = false }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showsCamera = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                showsCamera = true
            } else {
                errorMessage = "未获得相机权限。请在系统设置中允许生活记录使用相机，或从相册选择照片。"
            }
        case .denied:
            errorMessage = "相机权限已关闭。请在系统设置中允许生活记录使用相机，或从相册选择照片。"
        case .restricted:
            errorMessage = "此设备限制了相机使用，请从相册选择照片。"
        @unknown default:
            errorMessage = "相机暂时不可用，请从相册选择照片。"
        }
    }

    @MainActor
    private func addCameraPhoto(_ image: UIImage) async {
        guard imageData.count < settings.maxPhotos else { return }
        // 先缩小拍摄原图，避免全尺寸 JPEG 编码后再解码造成内存峰值。
        let scale = min(1280 / max(image.size.width, image.size.height), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.8) else {
            errorMessage = "无法读取拍摄的照片，请重新拍摄。"
            return
        }
        imageData.append(data)
        await analyze()
    }

    @MainActor
    private func save() async {
        let typedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let describedName = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typedName.isEmpty ? describedName : typedName
        guard !name.isEmpty else {
            errorMessage = "请填写餐食名称，或先描述这顿吃了什么。"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let hasNutrition = draft.calories > 0 || draft.protein > 0 || draft.carbs > 0 || draft.fat > 0
        guard hasNutrition else {
            errorMessage = "请填写营养数据；也可以先点“用 AI 估算营养”，复核结果后再保存。"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        isSaving = true
        defer { isSaving = false }

        var mealEntry: MealEntry?
        var photoUploadError: Error?
        if hasNutrition {
            let mealID = UUID()
            let photoIDs: [String]
            do {
                photoIDs = try await syncCoordinator.uploadMealPhotos(imageData, mealID: mealID)
            } catch {
                // 照片服务不可用时仍保存已经复核过的营养数据，避免让同步故障看起来像 AI 失效。
                photoIDs = []
                photoUploadError = error
            }
            let entry = MealEntry(
                id: mealID,
                date: date,
                kind: kind,
                name: name,
                calories: draft.calories,
                protein: draft.protein,
                carbs: draft.carbs,
                fat: draft.fat,
                fiber: draft.fiber,
                note: draft.note,
                source: wasAIAnalyzed ? .ai : .manual,
                photoIDs: photoIDs
            )
            mealEntry = entry
            modelContext.insert(entry)
        }
        do {
            try modelContext.save()
            await syncCoordinator.sync(context: modelContext, settings: settings)
            if let photoUploadError {
                syncCoordinator.reportPhotoUploadFailure(photoUploadError)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            if let mealEntry { modelContext.delete(mealEntry) }
            errorMessage = "餐食保存失败：\(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }
    }
}

struct AddWeightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let defaultDate: Date
    let lastWeight: Double?

    @State private var date: Date
    @State private var weight: Double
    @State private var bodyFatText = ""
    @State private var note = ""
    @State private var errorMessage: String?
    private enum Field: Hashable { case weight, bodyFat, note }
    @FocusState private var focusedField: Field?

    init(defaultDate: Date, lastWeight: Double?) {
        self.defaultDate = defaultDate
        self.lastWeight = lastWeight
        _date = State(initialValue: defaultDate)
        _weight = State(initialValue: lastWeight ?? 70)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("体重", value: $weight, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .focused($focusedField, equals: .weight)
                        Text("kg").font(.title3).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    DatePicker("测量时间", selection: $date)
                }
                Section("可选数据") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("体脂率", systemImage: "figure.arms.open").font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            TextField("例如 18.5", text: $bodyFatText)
                                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .bodyFat)
                                .accessibilityLabel("体脂率，百分比，可选")
                                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            Text("%").font(.title2).foregroundStyle(.secondary)
                        }
                        Text("可选，留空表示未测量").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .bodyFat }
                    TextField("备注，例如：晨起空腹", text: $note)
                        .focused($focusedField, equals: .note)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissControl()
            .navigationTitle("记录身体数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                    .fontWeight(.semibold)
                    .disabled(weight < 20 || weight > 400)
                }
            }
            .alert("无法保存身体数据", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func save() {
        let normalized = bodyFatText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let bodyFat = Double(normalized)
        guard weight.isFinite, (20...400).contains(weight), normalized.isEmpty || bodyFat.map({ $0.isFinite && (1...80).contains($0) }) == true else {
            errorMessage = "请输入有效的体重（20–400 kg）和体脂率（1–80%），未测体脂请留空。"
            return
        }
        focusedField = nil
        let entry = BodyMetric(
            date: date,
            weight: weight,
            bodyFat: bodyFat,
            note: note
        )
        modelContext.insert(entry)
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            modelContext.delete(entry)
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

}
