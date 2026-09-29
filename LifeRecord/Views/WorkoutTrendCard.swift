import SwiftUI
import Charts
import SwiftData

struct WorkoutTrendCard: View {
    let workouts: [WorkoutEntry]
    let cutoff: Date?
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @AppStorage(ExerciseLibrary.key) private var libraryRaw = "[]"
    @State private var selectedDate: Date?
    @State private var editing: WorkoutEntry?
    @State private var detailCategory = "训练记录"
    @State private var isClassifying = false
    @State private var classificationMessage: String?
    @State private var renamingPart: PartToRename?
    @State private var renamedPart = ""
    @State private var renameError: String?
    @AppStorage(WorkoutBodyParts.key) private var catalogRaw = ""
    private let tint = Color.teal
    private var completed: [WorkoutEntry] { workouts.filter { $0.endDate != nil && $0.date <= .now } }
    private var days: [Day] {
        Dictionary(grouping: completed) { Calendar.current.startOfDay(for: $0.date) }
            .map { Day(date: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }
    private var total: Double { completed.reduce(0) { $0 + $1.minutes } }
    private var selected: Day? {
        guard let selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
    private var domain: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        let minimum = Calendar.current.date(byAdding: .day, value: -6, to: today)!
        let first = min(cutoff ?? days.first?.date ?? minimum, minimum)
        return first.addingTimeInterval(-43200)...today.addingTimeInterval(43200)
    }
    var body: some View {
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3.weight(.semibold)).foregroundStyle(tint)
                        .frame(width: 42, height: 42).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("训练节奏").font(.headline)
                        Text("每一次投入，都算数").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink { detail } label: {
                        Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                    }.tint(tint).accessibilityLabel("查看健身记录详情")
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(total > 0 && total < 1 ? "<1" : total.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    Text("分钟").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(completed.count) 次训练").font(.subheadline.weight(.semibold))
                        Text("\(days.count) 天有记录").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !days.isEmpty {
                    Chart(days) { day in
                        BarMark(x: .value("日期", day.date, unit: .day), y: .value("分钟", day.minutes), width: .fixed(8))
                            .foregroundStyle(LinearGradient(colors: [tint, tint.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                            .cornerRadius(4)
                            .opacity(selectedDate == nil || selected?.id == day.id ? 1 : 0.3)
                        if day.minutes < 1 {
                            PointMark(x: .value("日期", day.date), y: .value("分钟", day.minutes))
                                .foregroundStyle(tint).symbolSize(18)
                        }
                    }
                    .chartXScale(domain: domain)
                    .chartYScale(domain: 0...max(30, (days.map(\.minutes).max() ?? 0) * 1.2))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                    .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(.secondary.opacity(0.2)); AxisValueLabel() } }
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 140)
                    .accessibilityLabel("每日训练时长，\(completed.count) 次训练，共 \(Int(total)) 分钟")
                    if let selectedDate {
                        HStack {
                            Text(selectedDate.formatted(.dateTime.month().day()))
                            Spacer()
                            Text(selected.map { "\($0.minutes.formatted(.number.precision(.fractionLength(1)))) 分钟 · \($0.count) 次" } ?? "当天无已完成训练记录")
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("从一次训练开始").font(.subheadline.weight(.medium))
                        Text("在今日页开始训练，结束后这里会留下你的节奏。").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
                if workouts.contains(where: { $0.endDate == nil }) {
                    Label("有训练进行中，结束后计入统计", systemImage: "timer").font(.caption).foregroundStyle(tint)
                }
                Divider().overlay(tint.opacity(0.06))
                NavigationLink { detail } label: {
                    HStack {
                        Text("训练内容与明细")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }.font(.subheadline.weight(.medium)).foregroundStyle(tint).padding(.vertical, 4)
                }
            }
        }
        .onChange(of: cutoff) { _, _ in selectedDate = nil }
    }
    private var detail: some View {
        VStack(spacing: 12) {
            Picker("分类", selection: $detailCategory) {
                Text("训练记录").tag("训练记录")
                Text("按部位").tag("按部位")
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                LazyVStack(spacing: 16) {
                    if detailCategory == "按部位" {
                        bodyPartSummaries
                    } else if workouts.isEmpty {
                        ContentUnavailableView("暂无训练记录", systemImage: "figure.strengthtraining.traditional", description: Text("在今日页开始训练或补记。"))
                    } else {
                        ForEach(workouts.sorted { $0.date > $1.date }) { entry in
                            Button { editing = entry } label: {
                                GlassCard(tint: tint) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text(entry.date.formatted(.dateTime.month().day().weekday())).font(.headline)
                                            Spacer()
                                            Text(entry.endDate == nil ? "进行中" : "\(entry.minutes.formatted(.number.precision(.fractionLength(1)))) 分钟").font(.subheadline.monospacedDigit()).foregroundStyle(tint)
                                        }
                                        Text(entry.overviewSummary.isEmpty ? "未填写训练部位或内容" : entry.overviewSummary).font(.subheadline).foregroundStyle(.secondary)
                                        HStack {
                                            Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) → \(entry.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "尚未结束")").font(.caption).foregroundStyle(.secondary)
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(tint)
                                        }
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(16)
            }
        }.background(AppBackground()).navigationTitle("训练明细")
            .sheet(item: $editing) { WorkoutEditor(entry: $0, date: $0.date) }
            .sheet(item: $renamingPart) { target in
                NavigationStack {
                    Form {
                        TextField("训练部位名称", text: $renamedPart)
                        if let renameError { Text(renameError).foregroundStyle(.red) }
                        Text("保存后，所有使用这个部位的训练记录和动作库会一起更名。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .navigationTitle("编辑训练部位")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { renamingPart = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("保存") { renamePart(target.name) } }
                    }
                }
                .presentationDetents([.medium])
            }
    }

    private var bodyPartSummaries: some View {
        let finished = workouts.filter { $0.endDate != nil && $0.date <= .now }
        let parts = Array(Set(finished.flatMap(\.bodyParts))).sorted()
        let unclassified = workouts.filter { $0.bodyParts.isEmpty && (!$0.note.isEmpty || !$0.exercises.isEmpty) }
        return Group {
            NavigationLink { ExerciseLibraryView() } label: {
                Label("管理和添加动作", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !unclassified.isEmpty {
                Button(isClassifying ? "AI 正在归类…" : "AI 归类 \(unclassified.count) 条未分类训练", systemImage: "sparkles") {
                    classifyUncategorized(unclassified)
                }
                .disabled(isClassifying)
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let classificationMessage {
                Text(classificationMessage).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if parts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ContentUnavailableView(
                        "还没有训练部位记录",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("在训练详情直接选择训练部位；也可以让 AI 根据已有记录归类。")
                    )
                    let editable = finished.filter {
                        $0.bodyParts.isEmpty
                    }.sorted { $0.date > $1.date }
                    if !editable.isEmpty {
                        Text("选择一条已有训练来分类")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                        ForEach(editable.prefix(8)) { entry in
                            Button { editing = entry } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundStyle(tint)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.date.formatted(.dateTime.month().day().weekday()))
                                            .font(.subheadline.weight(.medium))
                                        Text(entry.overviewSummary.isEmpty ? "尚未标记部位" : entry.overviewSummary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            } else {
                ForEach(parts, id: \.self) { part in
                    let entries = finished.filter { $0.bodyParts.contains(part) }.sorted { $0.date > $1.date }
                    GlassCard(tint: tint) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(part).font(.headline)
                                Spacer()
                                Text("\(entries.count) 次").font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                            }
                            WorkoutPartTimeline(entries: entries) { editing = $0 }
                            HStack {
                                Menu {
                                    ForEach(entries) { entry in
                                        Button(entry.date.formatted(date: .abbreviated, time: .shortened)) { editing = entry }
                                    }
                                } label: {
                                    Label("选择训练记录", systemImage: "calendar")
                                }
                                Spacer()
                                Button("部位改名", systemImage: "pencil") {
                                    renamedPart = part; renameError = nil; renamingPart = PartToRename(name: part)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func classifyUncategorized(_ records: [WorkoutEntry]) {
        isClassifying = true
        classificationMessage = nil
        let examples = workouts.filter { !$0.bodyParts.isEmpty }.prefix(24).map {
            WorkoutPartExample(note: $0.note, exerciseNames: $0.exercises.map(\.name), bodyParts: $0.bodyParts)
        }
        Task {
            do {
                var classified = 0
                for start in stride(from: 0, to: records.count, by: 12) {
                    let batch = Array(records[start..<min(start + 12, records.count)])
                    let candidates = batch.map { WorkoutPartCandidate(id: $0.id.uuidString, note: $0.note, exerciseNames: $0.exercises.map(\.name)) }
                    let suggestions = try await AIClient(settings: settings).classifyWorkoutParts(records: candidates, examples: examples)
                    for suggestion in suggestions where !suggestion.bodyParts.isEmpty {
                        guard let record = batch.first(where: { $0.id.uuidString == suggestion.id }), record.bodyParts.isEmpty else { continue }
                        record.bodyParts = suggestion.bodyParts
                        record.updatedAt = .now
                        classified += 1
                    }
                }
                if classified > 0 {
                    try context.save()
                    await sync.sync(context: context, settings: settings)
                }
                classificationMessage = "已归类 \(classified) 条；证据不足的记录仍可手动选择部位。"
            } catch {
                context.rollback()
                classificationMessage = "AI 归类失败：\(error.localizedDescription)"
            }
            isClassifying = false
        }
    }

    private func renamePart(_ oldName: String) {
        let name = renamedPart.trimmingCharacters(in: .whitespacesAndNewlines)
        let allEntries: [WorkoutEntry]
        do { allEntries = try context.fetch(FetchDescriptor<WorkoutEntry>()) }
        catch { renameError = error.localizedDescription; return }
        guard WorkoutBodyParts.isValid(name),
              name == oldName || !WorkoutBodyParts.choices.contains(name) && !allEntries.contains(where: { $0.bodyParts.contains(name) }) else {
            renameError = "请输入不重复且不超过 30 字的名称。"; return
        }
        if name != oldName {
            for entry in allEntries where entry.bodyParts.contains(oldName) {
                entry.bodyParts = entry.bodyParts.map { $0 == oldName ? name : $0 }
                var exercises = entry.exercises
                for index in exercises.indices where exercises[index].bodyPart == oldName { exercises[index].bodyPart = name }
                entry.exercises = exercises
                entry.updatedAt = .now
            }
            var catalog = WorkoutBodyParts.choices
            if let index = catalog.firstIndex(of: oldName) { catalog[index] = name }
            else { catalog.append(name) }
            var templates = ExerciseLibrary.decode(libraryRaw)
            for index in templates.indices where templates[index].bodyPart == oldName { templates[index].bodyPart = name }
            do { try context.save() } catch { context.rollback(); renameError = error.localizedDescription; return }
            WorkoutBodyParts.saveChoices(catalog)
            catalogRaw = UserDefaults.standard.string(forKey: WorkoutBodyParts.key) ?? ""
            libraryRaw = ExerciseLibrary.encode(templates)
            Task { await sync.sync(context: context, settings: settings) }
        }
        renamingPart = nil
    }
    private struct Day: Identifiable {
        let date: Date
        let minutes: Double
        let count: Int
        var id: Date { date }
    }
    private struct PartToRename: Identifiable {
        let name: String
        var id: String { name }
    }
}

private struct WorkoutPartTimeline: View {
    let entries: [WorkoutEntry]
    let onEdit: (WorkoutEntry) -> Void
    @State private var selectedDate: Date?
    private let tint = Color.teal

    private var domain: ClosedRange<Date> {
        let dates = entries.map(\.date)
        let first = dates.min() ?? .now
        let last = dates.max() ?? first
        let padding = max(86_400, last.timeIntervalSince(first) * 0.05)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }

    private var selectedEntry: WorkoutEntry? {
        guard let selectedDate else { return nil }
        return entries.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                RuleMark(y: .value("训练时间轴", 0))
                    .foregroundStyle(.secondary.opacity(0.35))
                ForEach(entries) { entry in
                    PointMark(x: .value("训练日期", entry.date), y: .value("训练", 0))
                        .symbolSize(selectedEntry?.id == entry.id ? 110 : 65)
                        .foregroundStyle(tint)
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: -1...1)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
            .chartYAxis(.hidden)
            .chartXSelection(value: $selectedDate)
            .frame(height: 82)
            .accessibilityLabel("训练时间轴，共 \(entries.count) 次；下方可选择训练记录编辑")
            if let selectedEntry {
                Button {
                    onEdit(selectedEntry)
                } label: {
                    Label("\(selectedEntry.date.formatted(date: .abbreviated, time: .shortened)) · 编辑此次训练", systemImage: "pencil")
                        .font(.caption)
                }
            } else {
                Text("点时间点查看并编辑训练")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
