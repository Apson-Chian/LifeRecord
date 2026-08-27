import SwiftUI
import SwiftData
import PhotosUI

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

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
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: settings.maxPhotos,
                        selectionBehavior: .ordered,
                        matching: .images
                    ) {
                        HStack {
                            Label(imageData.isEmpty ? "选择多张照片" : "已选择 \(imageData.count) 张", systemImage: "photo.stack")
                            Spacer()
                            if isLoadingPhotos { ProgressView().controlSize(.small) }
                        }
                    }
                    .onChange(of: photoItems) { _, items in
                        Task { await loadPhotos(items) }
                    }
                    photoPreview
                    Button {
                        Task { await analyze() }
                    } label: {
                        HStack {
                            Label("用 AI 估算营养", systemImage: "sparkles")
                            Spacer()
                            if isAnalyzing { ProgressView() }
                        }
                    }
                    .disabled(isAnalyzing || isLoadingPhotos || (description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData.isEmpty))
                } header: {
                    Text("这顿吃了什么")
                } footer: {
                    Text("照片和文字会直接发送到你配置的 AI 服务商。结果只是估算，保存前请复核。")
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
                    numberField("计入饮水", value: $draft.waterML, unit: "ml")
                    if draft.waterML > 0 {
                        Label("保存后会同时增加一条饮水记录", systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.water)
                    }
                }

                Section("备注") {
                    TextField("份量、烹饪方式或训练感受", text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .note)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("记录餐食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(isAnalyzing || isLoadingPhotos)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
            .alert("无法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
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
                                    if photoItems.indices.contains(index) { photoItems.remove(at: index) }
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
        defer { isLoadingPhotos = false }
        var loaded: [Data] = []
        for item in items.prefix(settings.maxPhotos) {
            guard let original = try? await item.loadTransferable(type: Data.self) else { continue }
            loaded.append(AIClient.jpegImageData(forSending: original, maxDimension: 1280))
        }
        imageData = loaded
        if loaded.count < items.count { errorMessage = "有 \(items.count - loaded.count) 张照片无法读取，请重新选择。" }
    }

    private func save() {
        let typedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let describedName = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typedName.isEmpty ? describedName : typedName
        guard !name.isEmpty else {
            errorMessage = "请填写餐食名称，或先描述这顿吃了什么。"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let hasNutrition = draft.calories > 0 || draft.protein > 0 || draft.carbs > 0 || draft.fat > 0
        let hasWater = draft.waterML > 0
        guard hasNutrition || hasWater else {
            errorMessage = "请填写营养或饮水数据；也可以先点“用 AI 估算营养”，复核结果后再保存。"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        var mealEntry: MealEntry?
        var waterEntry: WaterEntry?
        if hasNutrition {
            let entry = MealEntry(
                date: date,
                kind: kind,
                name: name,
                calories: draft.calories,
                protein: draft.protein,
                carbs: draft.carbs,
                fat: draft.fat,
                fiber: draft.fiber,
                note: draft.note,
                source: wasAIAnalyzed ? .ai : .manual
            )
            mealEntry = entry
            modelContext.insert(entry)
        }
        if hasWater {
            let entry = WaterEntry(
                date: date,
                milliliters: min(draft.waterML, 10_000),
                note: "来自\(wasAIAnalyzed ? " AI 识别" : "餐食记录")：\(name)"
            )
            waterEntry = entry
            modelContext.insert(entry)
        }
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            if let mealEntry { modelContext.delete(mealEntry) }
            if let waterEntry { modelContext.delete(waterEntry) }
            errorMessage = "餐食保存失败：\(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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
    @State private var bodyFat = 0.0
    @State private var note = ""
    @State private var errorMessage: String?
    @FocusState private var isEditing: Bool

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
                            .focused($isEditing)
                        Text("kg").font(.title3).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    DatePicker("测量时间", selection: $date)
                }
                Section("可选数据") {
                    metricField("体脂率", value: $bodyFat, unit: "%")
                    TextField("备注，例如：晨起空腹", text: $note)
                        .focused($isEditing)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("记录身体数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                    .fontWeight(.semibold)
                    .disabled(weight < 20 || weight > 400)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { isEditing = false }.fontWeight(.semibold)
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
        let entry = BodyMetric(
            date: date,
            weight: weight,
            bodyFat: bodyFat > 0 ? bodyFat : nil,
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

    private func metricField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("未填写", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isEditing)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct AddWaterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let defaultDate: Date
    @State private var amount = 250.0
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(AppTheme.water)
                    .padding(.top, 28)
                Text("\(amount, specifier: "%.0f") ml")
                    .font(.largeTitle.bold().monospacedDigit())
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(WaterEntry.commonAmounts, id: \.self) { value in
                        Button {
                            amount = value
                        } label: {
                            Text("\(Int(value)) ml")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(amount == value ? Color.white : AppTheme.water)
                                .background(
                                    amount == value ? AppTheme.water : AppTheme.water.opacity(0.11),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .buttonStyle(PressScaleButtonStyle())
                    }
                }
                .padding(.horizontal)
                Text("选择常见杯量或瓶装容量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle("记录饮水")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.semibold)
                }
            }
            .alert("无法保存饮水记录", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func save() {
        let entry = WaterEntry(date: defaultDate, milliliters: amount)
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
