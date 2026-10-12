import SwiftUI
import SwiftData

struct RecordQualityView: View {
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]
    @AppStorage("recordQuality.acknowledged") private var acknowledgedRaw = "[]"
    @State private var filter = "待核对"
    @State private var confirming: RecordQuality.Issue?

    private var acknowledged: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(acknowledgedRaw.utf8))) ?? [])
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let all = RecordQuality.issues(meals: meals.map { InsightRecords.Meal($0) }, body: bodyMetrics.map { InsightRecords.Body($0) }, workouts: workouts.map { InsightRecords.Workout($0) }, now: timeline.date)
            let visible = all.filter { acknowledged.contains($0.id) == (filter == "已确认") }
            List {
                Section {
                    Text("检查全部真实记录：疑似重复餐食、营养数值、AI 信息不足、身体数值及短期跳变、训练时长和未来时间。提示是核对线索，不代表记录错误。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("检查结果", selection: $filter) {
                        Text("待核对").tag("待核对")
                        Text("已确认").tag("已确认")
                    }.pickerStyle(.segmented)
                }
                if visible.isEmpty {
                    Section {
                        ContentUnavailableView(filter == "待核对" ? "暂无待核对记录" : "暂无已确认记录", systemImage: "checkmark.shield", description: Text("检查不自动修改或删除数据，也不保证发现所有问题。示例数据不参与检查。"))
                    }
                } else {
                    Section("\(visible.count) 项\(filter)") {
                        ForEach(visible) { issue in
                            VStack(alignment: .leading, spacing: 10) {
                                Label(issue.title, systemImage: "exclamationmark.circle").font(.headline).foregroundStyle(filter == "待核对" ? .orange : .secondary)
                                Text("\(issue.category.rawValue) · \(issue.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                Text(issue.detail).font(.subheadline)
                                ForEach(issue.recordIDs, id: \.self) { id in
                                    recordLink(id, category: issue.category)
                                }
                                Button(filter == "待核对" ? "确认记录无误" : "重新核对") {
                                    if filter == "待核对" { confirming = issue }
                                    else { setAcknowledged(issue, false) }
                                }.font(.caption).buttonStyle(.borderless)
                            }.padding(.vertical, 8)
                        }
                    }
                }
                Section {
                    Text("“确认无误”仅隐藏当前版本的提示，保存在本机；记录被修改或同步更新后会重新检查。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
        }
        .navigationTitle("记录质量检查")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确认记录无误？", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            Button("确认无误") { if let confirming { setAcknowledged(confirming, true) }; confirming = nil }
            Button("取消", role: .cancel) { confirming = nil }
        } message: { Text("只隐藏这条核对提示，原始记录保持不变。") }
    }

    private func setAcknowledged(_ issue: RecordQuality.Issue, _ value: Bool) {
        var ids = acknowledged
        if value { ids.insert(issue.id) } else { ids.remove(issue.id) }
        acknowledgedRaw = String(decoding: (try? JSONEncoder().encode(ids.sorted())) ?? Data(), as: UTF8.self)
    }
    @ViewBuilder
    private func recordLink(_ id: UUID, category: RecordQuality.Category) -> some View {
        switch category {
        case .meal:
            if let entry = meals.first(where: { $0.id == id }) {
                NavigationLink { MealDetailView(meal: entry) } label: {
                    recordLabel(entry.name, detail: "\(entry.date.formatted(.dateTime.hour().minute())) · 查看详情\(entry.photoIDs.isEmpty ? "" : " · \(entry.photoIDs.count) 张照片")", symbol: entry.kind.symbol)
                }.buttonStyle(.borderless)
            }
        case .body:
            if let entry = bodyMetrics.first(where: { $0.id == id }) {
                NavigationLink { QualityBodyDetailView(entry: entry) } label: {
                    recordLabel("\(entry.weight.formatted()) kg", detail: "\(entry.date.formatted(date: .abbreviated, time: .shortened)) · 查看详情", symbol: AppSymbol.weight)
                }.buttonStyle(.borderless)
            }
        case .workout:
            if let entry = workouts.first(where: { $0.id == id }) {
                NavigationLink { QualityWorkoutDetailView(entry: entry) } label: {
                    recordLabel("训练记录", detail: "\(entry.date.formatted(date: .abbreviated, time: .shortened)) · 查看详情", symbol: AppSymbol.workout)
                }.buttonStyle(.borderless)
            }
        }
    }
    private func recordLabel(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
        }.frame(minHeight: 44, alignment: .leading)
    }
}

private struct QualityBodyDetailView: View {
    let entry: BodyMetric
    @State private var isEditing = false

    var body: some View {
        List {
            Section("测量数据") {
                LabeledContent("时间", value: entry.date.formatted(date: .long, time: .shortened))
                LabeledContent("体重", value: "\(entry.weight.formatted()) kg")
                if let bodyFat = entry.bodyFat { LabeledContent("体脂率", value: "\(bodyFat.formatted()) %") }
                if let waist = entry.waist { LabeledContent("腰围", value: "\(waist.formatted()) cm") }
            }
            if !entry.note.isEmpty { Section("备注") { Text(entry.note).textSelection(.enabled) } }
        }
        .navigationTitle("测量详情").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("编辑") { isEditing = true } } }
        .sheet(isPresented: $isEditing) { AddWeightView(defaultDate: entry.date, lastWeight: entry.weight, editing: entry) }
    }
}

private struct QualityWorkoutDetailView: View {
    let entry: WorkoutEntry
    @State private var isEditing = false

    var body: some View {
        List {
            Section("训练时间") {
                LabeledContent("开始", value: entry.date.formatted(date: .long, time: .shortened))
                LabeledContent("结束", value: entry.endDate?.formatted(date: .long, time: .shortened) ?? "尚未结束")
                LabeledContent("时长", value: "\(entry.minutes.formatted(.number.precision(.fractionLength(0)))) 分钟")
            }
            if !entry.contentSummary.isEmpty { Section("训练内容") { Text(entry.contentSummary).textSelection(.enabled) } }
        }
        .navigationTitle("训练详情").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("编辑") { isEditing = true } } }
        .sheet(isPresented: $isEditing) { WorkoutEditor(entry: entry, date: entry.date) }
    }
}
