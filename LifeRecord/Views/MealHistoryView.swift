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
                                        MealPhotoView(imageID: imageID)
                                            .frame(width: 210, height: 180)
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

struct MealPhotoView: View {
    @Environment(SyncCoordinator.self) private var syncCoordinator
    let imageID: String

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .task(id: imageID) {
            image = nil
            failed = false
            do {
                let data = try await syncCoordinator.mealPhotoData(imageID: imageID)
                guard let decoded = UIImage(data: data) else {
                    failed = true
                    return
                }
                image = decoded
            } catch {
                failed = true
            }
        }
        .accessibilityLabel("餐食照片")
    }
}

struct MealPhotoGalleryView: View {
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
                            NavigationLink {
                                MealDetailView(meal: item.meal)
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
