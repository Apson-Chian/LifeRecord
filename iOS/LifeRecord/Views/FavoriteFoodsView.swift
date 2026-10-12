import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import AVFoundation

struct FavoriteFoodsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FavoriteFood.name) private var foods: [FavoriteFood]
    var onSelect: ((FavoriteFood) -> Void)? = nil

    @State private var isAdding = false
    @State private var editing: FavoriteFood?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if foods.isEmpty {
                ContentUnavailableView {
                    Label("还没有常用餐食", systemImage: "fork.knife.circle")
                } description: {
                    Text("添加常喝的牛奶或常吃的面包，保存照片与每份营养，以后在教练里发送固定名称即可查询。")
                } actions: {
                    Button("添加常用餐食", systemImage: "plus") { isAdding = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(foods) { food in
                            Button {
                                if let onSelect { onSelect(food); dismiss() }
                                else { editing = food }
                            } label: {
                                HStack(spacing: 12) {
                                    if let data = food.photoData, let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
                                    } else {
                                        Image(systemName: "fork.knife").frame(width: 56, height: 56)
                                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(food.name).font(.body.weight(.semibold))
                                        Text("\(food.portion) · \(food.calories.formatted()) kcal")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: onSelect == nil ? "chevron.right" : "plus.circle")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("删除", role: .destructive) { delete(food) }
                            }
                            .contextMenu {
                                Button("编辑") { editing = food }
                                Button("删除", role: .destructive) { delete(food) }
                            }
                        }
                    } footer: {
                        Text("按固定名称查询的是已复核的每份营养。常用餐食及其照片保存在本机。")
                    }
                }
            }
        }
        .navigationTitle(onSelect == nil ? "常用餐食" : "选择常用餐食")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("添加", systemImage: "plus") { isAdding = true } }
            if onSelect != nil {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .sheet(isPresented: $isAdding) { FavoriteFoodEditor() }
        .sheet(item: $editing) { FavoriteFoodEditor(food: $0) }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func delete(_ food: FavoriteFood) {
        context.delete(food)
        do { try context.save() }
        catch { context.rollback(); errorMessage = error.localizedDescription }
    }
}

private struct FavoriteFoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var foods: [FavoriteFood]
    let food: FavoriteFood?

    @State private var name: String
    @State private var portion: String
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var fiber: Double
    @State private var note: String
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var scanMode: MealScanMode = .nutritionLabel
    @State private var showsCamera = false
    @State private var isAnalyzing = false
    @State private var isLoadingPhoto = false
    @State private var isSavingPhoto = false
    @State private var photoNotice: String?
    @State private var errorMessage: String?

    init(food: FavoriteFood? = nil) {
        self.food = food
        _name = State(initialValue: food?.name ?? "")
        _portion = State(initialValue: food?.portion ?? "1份")
        _calories = State(initialValue: food?.calories ?? 0)
        _protein = State(initialValue: food?.protein ?? 0)
        _carbs = State(initialValue: food?.carbs ?? 0)
        _fat = State(initialValue: food?.fat ?? 0)
        _fiber = State(initialValue: food?.fiber ?? 0)
        _note = State(initialValue: food?.note ?? "")
        _photoData = State(initialValue: food?.photoData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("固定名称与份量") {
                    TextField("例如：早餐纯牛奶", text: $name)
                    TextField("例如：1盒 250 ml", text: $portion)
                }
                Section {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity).frame(height: 190)
                            .accessibilityLabel("常用餐食照片")
                        Button(isSavingPhoto ? "保存中…" : "保存照片到相册", systemImage: "square.and.arrow.down") {
                            Task { await savePhoto(photoData) }
                        }.disabled(isSavingPhoto)
                        Button("移除照片", role: .destructive) { self.photoData = nil }
                    }
                    HStack {
                        Button("拍照", systemImage: "camera") { Task { await openCamera() } }
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("从相册选择", systemImage: "photo.on.rectangle")
                        }
                    }.buttonStyle(.borderless)
                    Picker("识别类型", selection: $scanMode) {
                        ForEach(MealScanMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    Button {
                        Task { await analyze() }
                    } label: {
                        HStack {
                            Label("AI 估算每份营养", systemImage: "sparkles")
                            Spacer()
                            if isAnalyzing { ProgressView() }
                        }
                    }.disabled(photoData == nil || isAnalyzing || isLoadingPhoto)
                } header: { Text("照片") } footer: {
                    Text("拍下产品或营养成分表后，可让 AI 估算；请按实际份量核对数值。")
                }
                Section("每份营养") {
                    numberField("热量", value: $calories, unit: "kcal")
                    numberField("蛋白质", value: $protein, unit: "g")
                    numberField("碳水", value: $carbs, unit: "g")
                    numberField("脂肪", value: $fat, unit: "g")
                    numberField("膳食纤维", value: $fiber, unit: "g")
                }
                Section("备注") {
                    TextField("例如：每盒 250 ml，营养表按整盒换算", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissControl()
            .navigationTitle(food == nil ? "添加常用餐食" : "编辑常用餐食")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(isAnalyzing || isLoadingPhoto) }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraImagePicker { image in
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        photoData = preparedPhoto(data)
                    }
                }.ignoresSafeArea()
            }
            .alert("无法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .alert("照片", isPresented: Binding(get: { photoNotice != nil }, set: { if !$0 { photoNotice = nil } })) {
                Button("好") { photoNotice = nil }
            } message: { Text(photoNotice ?? "") }
        }
    }

    private func numberField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false; selectedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "无法读取照片，请重新选择。"
            return
        }
        guard let prepared = preparedPhoto(data) else {
            errorMessage = "这张照片无法解码，请重新选择。"
            return
        }
        photoData = prepared
    }

    private func preparedPhoto(_ data: Data) -> Data? {
        let resized = AIClient.jpegImageData(forSending: data, maxDimension: 1280)
        guard let image = UIImage(data: resized) else { return nil }
        return image.jpegData(compressionQuality: 0.8)
    }

    @MainActor
    private func savePhoto(_ data: Data) async {
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        do { try await PhotoLibrarySaver.save(data); photoNotice = "已保存到系统相册。" }
        catch { photoNotice = "保存失败：\(error.localizedDescription)" }
    }

    @MainActor
    private func openCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showsCamera = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) { showsCamera = true }
            else { errorMessage = "未获得相机权限，请在系统设置中允许拍照。" }
        case .denied, .restricted: errorMessage = "相机不可用，请在系统设置中检查权限或从相册选择。"
        @unknown default: errorMessage = "相机暂时不可用。"
        }
    }

    @MainActor
    private func analyze() async {
        guard let photoData else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let description = [name, portion].filter { !$0.isEmpty }.joined(separator: "，")
            let draft = try await AIClient(settings: settings).analyzeMeal(description: description, images: [photoData], mode: scanMode)
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = draft.name }
            calories = draft.calories
            protein = draft.protein
            carbs = draft.carbs
            fat = draft.fat
            fiber = draft.fiber
            note = draft.note
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPortion = portion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 100, !cleanPortion.isEmpty, cleanPortion.count <= 100 else {
            errorMessage = "请填写 100 字以内的固定名称和每份份量。"; return
        }
        guard !foods.contains(where: { $0.id != food?.id && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            errorMessage = "已有同名常用餐食，请换一个名称。"; return
        }
        guard calories.isFinite, calories > 0, calories <= 20_000,
              [protein, carbs, fat, fiber].allSatisfy({ $0.isFinite && (0...3_000).contains($0) }),
              note.count <= 10_000 else {
            errorMessage = "请核对每份营养数值；热量需要大于 0。"; return
        }
        let record = food ?? FavoriteFood(name: cleanName)
        if food == nil { context.insert(record) }
        record.name = cleanName
        record.portion = cleanPortion
        record.calories = calories
        record.protein = protein
        record.carbs = carbs
        record.fat = fat
        record.fiber = fiber
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        record.photoData = photoData
        record.updatedAt = .now
        do { try context.save(); dismiss() }
        catch { context.rollback(); errorMessage = error.localizedDescription }
    }
}
