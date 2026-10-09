import SwiftUI
import SwiftData

struct RecordQualityView: View {
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]
    @AppStorage("recordQuality.acknowledged") private var acknowledgedRaw = "[]"
    @State private var editingMeal: MealEntry?
    @State private var editingBody: BodyMetric?
    @State private var editingWorkout: WorkoutEntry?
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
                                    Button { edit(id, category: issue.category) } label: {
                                        Label(recordLabel(id, category: issue.category), systemImage: "square.and.pencil")
                                            .font(.subheadline).frame(minHeight: 44, alignment: .leading)
                                    }.buttonStyle(.borderless)
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
        .sheet(item: $editingMeal) { MealEditView(meal: $0) }
        .sheet(item: $editingBody) { AddWeightView(defaultDate: $0.date, lastWeight: $0.weight, editing: $0) }
        .sheet(item: $editingWorkout) { WorkoutEditor(entry: $0, date: $0.date) }
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
    private func edit(_ id: UUID, category: RecordQuality.Category) {
        switch category {
        case .meal: editingMeal = meals.first { $0.id == id }
        case .body: editingBody = bodyMetrics.first { $0.id == id }
        case .workout: editingWorkout = workouts.first { $0.id == id }
        }
    }
    private func recordLabel(_ id: UUID, category: RecordQuality.Category) -> String {
        switch category {
        case .meal:
            guard let entry = meals.first(where: { $0.id == id }) else { return "记录已删除" }
            return "编辑 \(entry.name) · \(entry.date.formatted(.dateTime.hour().minute()))"
        case .body:
            guard let entry = bodyMetrics.first(where: { $0.id == id }) else { return "记录已删除" }
            return "编辑 \(entry.weight.formatted()) kg · \(entry.date.formatted(.dateTime.month().day().hour().minute()))"
        case .workout: return "编辑训练起止时间"
        }
    }
}
