import SwiftUI
import SwiftData
import UIKit

struct MealHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @State private var errorMessage: String?

    private var groupedMeals: [(date: Date, meals: [MealEntry])] {
        Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if meals.isEmpty {
                ContentUnavailableView(
                    "暂无饮食记录",
                    systemImage: "fork.knife.circle",
                    description: Text("保存餐食后，可以在这里回溯、查看详情或删除。")
                )
            } else {
                List {
                    ForEach(groupedMeals, id: \.date) { group in
                        Section(group.date.formatted(.dateTime.year().month().day().weekday())) {
                            ForEach(group.meals) { meal in
                                NavigationLink {
                                    MealDetailView(meal: meal)
                                } label: {
                                    MealHistoryRow(meal: meal)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("删除", role: .destructive) {
                                        delete(meal)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("饮食记录")
        .navigationBarTitleDisplayMode(.inline)
        .alert("删除失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func delete(_ meal: MealEntry) {
        SyncDeletion.delete(meal, context: modelContext)
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let meal: MealEntry

    @State private var isConfirmingDelete = false
    @State private var isEditing = false
    @State private var selectedPhoto: PhotoSelection?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(meal.name)
                                    .font(.title2.bold())
                                Text(meal.date.formatted(date: .long, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: meal.kind.symbol)
                                .font(.title2)
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 44, height: 44)
                                .background(AppTheme.accent.opacity(0.12), in: Circle())
                        }
                        HStack(spacing: 8) {
                            Label(meal.kind.rawValue, systemImage: "clock")
                            if meal.source == .ai {
                                Label("AI 估算", systemImage: "sparkles")
                            } else {
                                Label("手动记录", systemImage: "hand.tap")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("营养详情").font(.headline)
                        NutritionDetailRow(title: "热量", value: meal.calories, unit: "kcal", color: .orange)
                        NutritionDetailRow(title: "蛋白质", value: meal.protein, unit: "g", color: AppTheme.protein)
                        NutritionDetailRow(title: "碳水", value: meal.carbs, unit: "g", color: AppTheme.carbs)
                        NutritionDetailRow(title: "脂肪", value: meal.fat, unit: "g", color: AppTheme.fat)
                        NutritionDetailRow(title: "膳食纤维", value: meal.fiber, unit: "g", color: AppTheme.accent)
                    }
                }

                if !meal.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注").font(.headline)
                            Text(meal.note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if !meal.photoIDs.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("餐食照片").font(.headline)
                                Spacer()
                                Text("\(meal.photoIDs.count) 张")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ScrollView(.horizontal) {
                                HStack(spacing: 12) {
                                    ForEach(meal.photoIDs, id: \.self) { imageID in
                                        Button {
                                            selectedPhoto = PhotoSelection(id: imageID)
                                        } label: {
                                            MealPhotoView(imageID: imageID)
                                                .frame(width: 210, height: 180)
                                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                                .overlay(alignment: .bottomTrailing) {
                                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                        .padding(9).background(.ultraThinMaterial, in: Circle()).padding(8)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("查看餐食照片")
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("删除这条记录", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("餐食详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("编辑") { isEditing = true } } }
        .sheet(isPresented: $isEditing) { MealEditView(meal: meal) }
        .fullScreenCover(item: $selectedPhoto) { photo in
            MealPhotoViewer(imageIDs: meal.photoIDs, initialID: photo.id)
        }
        .confirmationDialog("确定删除这条饮食记录？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: deleteMeal)
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
        .alert("删除失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func deleteMeal() {
        SyncDeletion.delete(meal, context: modelContext)
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

private struct MealHistoryRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: 12) {
            if let imageID = meal.photoIDs.first {
                MealPhotoView(imageID: imageID)
                    .frame(width: 48, height: 48)
            } else {
                Image(systemName: meal.kind.symbol)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name).font(.subheadline.weight(.semibold))
                Text("\(meal.kind.rawValue) · \(meal.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(meal.calories.formatted(.number.precision(.fractionLength(0)))) kcal")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .padding(.vertical, 3)
    }
}

struct MealPhotoGalleryView: View {
    @State private var selectedPhoto: PhotoSelection?
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]

    private var items: [MealPhotoItem] {
        meals.flatMap { meal in
            meal.photoIDs.map { MealPhotoItem(id: $0, meal: meal) }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "暂无餐食照片",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("拍摄或选择照片并保存餐食后，可以在这里集中查看。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(items) { item in
                            Button {
                                selectedPhoto = PhotoSelection(id: item.id)
                            } label: {
                                MealPhotoView(imageID: item.id)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                }
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            MealPhotoViewer(imageIDs: items.map(\.id), initialID: photo.id)
        }
        .navigationTitle("餐食照片")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MealPhotoItem: Identifiable {
    let id: String
    let meal: MealEntry
}

private struct NutritionDetailRow: View {
    let title: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                .font(.body.weight(.semibold).monospacedDigit())
        }
    }
}


struct MealEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    let meal: MealEntry
    @State private var draft = MealDraft()
    @State private var date = Date.now
    @State private var kind = MealKind.snack
    @State private var instruction = ""
    @State private var originalUpdatedAt = Date.distantPast
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("让 AI 修改") {
                    TextField("例如：米饭只吃了一半，重新计算营养", text: $instruction, axis: .vertical)
                    Button(busy ? "正在修改…" : "生成修改结果") { Task { await revise() } }
                        .disabled(busy || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("AI 结果会填入下方表单，复核并保存后生效。原照片保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("餐食数据") {
                    TextField("名称", text: $draft.name)
                    Picker("餐次", selection: $kind) { ForEach(MealKind.allCases) { Text($0.rawValue).tag($0) } }
                    DatePicker("时间", selection: $date)
                    number("热量 kcal", value: $draft.calories)
                    number("蛋白质 g", value: $draft.protein)
                    number("碳水 g", value: $draft.carbs)
                    number("脂肪 g", value: $draft.fat)
                    number("膳食纤维 g", value: $draft.fiber)
                    TextField("备注", text: $draft.note, axis: .vertical)
                }.disabled(busy)
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissControl()
            .navigationTitle("编辑餐食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(busy) }
            }
            .onAppear {
                draft = MealDraft(name: meal.name, calories: meal.calories, protein: meal.protein, carbs: meal.carbs, fat: meal.fat, fiber: meal.fiber, note: meal.note)
                date = meal.date; kind = meal.kind; originalUpdatedAt = meal.updatedAt
            }
            .alert("无法修改", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .interactiveDismissDisabled(busy)
        }
    }

    private func number(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    @MainActor private func revise() async {
        busy = true
        defer { busy = false }
        do {
            let current = String(data: try JSONEncoder().encode(draft), encoding: .utf8) ?? ""
            draft = try await AIClient(settings: settings).analyzeMeal(
                description: "修改已有餐食，原数据：\(current)。用户要求：\(instruction)。保留未涉及的内容，返回修改后的完整营养数据。", images: [], mode: .meal)
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        guard !meal.isDeleted else { errorMessage = "该记录已被删除，请关闭编辑页。"; return }
        guard meal.updatedAt == originalUpdatedAt else { errorMessage = "该记录已在其他设备更新，请关闭后重新编辑。"; return }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [draft.calories, draft.protein, draft.carbs, draft.fat, draft.fiber].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            errorMessage = "请填写名称和有效的非负营养数值。"; return
        }
        meal.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.date = date; meal.kindRaw = kind.rawValue
        meal.calories = draft.calories; meal.protein = draft.protein; meal.carbs = draft.carbs
        meal.fat = draft.fat; meal.fiber = draft.fiber; meal.note = draft.note; meal.updatedAt = .now
        do { try modelContext.save(); dismiss() }
        catch { modelContext.rollback(); errorMessage = error.localizedDescription }
    }
}
