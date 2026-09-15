import SwiftUI
import SwiftData

struct WorkoutDayCard: View {
    let date: Date
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @State private var editing: WorkoutEntry?
    @State private var adding = false
    @State private var error: String?
    private var entries: [WorkoutEntry] { workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: date) } }
    private var active: WorkoutEntry? { workouts.first { $0.endDate == nil } }

    var body: some View {
        GlassCard(tint: .teal) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("健身记录", systemImage: "figure.strengthtraining.traditional").font(.headline).foregroundStyle(.teal)
                    Spacer()
                    Button("补记") { adding = true }.font(.subheadline)
                }
                if let active {
                    Text("训练进行中").font(.subheadline).foregroundStyle(.secondary)
                    Text(active.date, style: .timer).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    Text("开始于 \(active.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    Button("结束训练") {
                        active.endDate = .now
                        active.updatedAt = .now
                        persist()
                        editing = active
                    }.buttonStyle(.borderedProminent).tint(.teal)
                } else if Calendar.current.isDateInToday(date) {
                    Text("留一点时间，给更好的自己").font(.subheadline).foregroundStyle(.secondary)
                    Button { context.insert(WorkoutEntry()); persist() } label: {
                        Label("开始训练", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent).tint(.teal)
                }
                if entries.isEmpty && active == nil {
                    Text("当天还没有训练记录").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.endDate == nil ? "timer" : "checkmark.circle.fill").foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.note.isEmpty ? "健身训练" : entry.note).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text("\(entry.date.formatted(date: .omitted, time: .shortened)) → \(entry.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "进行中")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.endDate != nil { Text("\(Int(entry.minutes)) 分钟").font(.subheadline.monospacedDigit()) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $editing) { WorkoutEditor(entry: $0, date: date) }
        .sheet(isPresented: $adding) { WorkoutEditor(entry: nil, date: date) }
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") {} } message: { Text(error ?? "") }
    }
    private func persist() {
        do { try context.save(); Task { await sync.sync(context: context, settings: settings) } }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct WorkoutEditor: View {
    let entry: WorkoutEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @State private var start: Date
    @State private var end: Date
    @State private var finished: Bool
    @State private var note: String
    @State private var error: String?
    @State private var confirmDelete = false

    init(entry: WorkoutEntry?, date: Date) {
        self.entry = entry
        let start = entry?.date ?? min(date, .now)
        _start = State(initialValue: start)
        _end = State(initialValue: entry?.endDate ?? min(start.addingTimeInterval(3600), .now))
        _finished = State(initialValue: entry == nil || entry?.endDate != nil)
        _note = State(initialValue: entry?.note ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("训练时间") {
                    DatePicker("开始", selection: $start, in: ...Date.now)
                    if entry?.endDate == nil && entry != nil { Toggle("训练已结束", isOn: $finished) }
                    if finished {
                        DatePicker("结束", selection: $end, in: ...Date.now)
                        if end < start { Text("结束时间不能早于开始时间").foregroundStyle(.red) }
                        else { LabeledContent("时长", value: "\(Int(end.timeIntervalSince(start) / 60)) 分钟") }
                    }
                }
                Section("健身内容") {
                    TextField("例如：深蹲 4 组 × 8 次，慢跑 20 分钟", text: $note, axis: .vertical).lineLimit(4...10)
                }
                if entry != nil { Section { Button("删除记录", role: .destructive) { confirmDelete = true } } }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissControl()
            .navigationTitle(entry == nil ? "补记训练" : "训练详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(finished && end < start) }
            }
            .confirmationDialog("删除这次训练？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let entry {
                        context.insert(SyncTombstone(recordID: entry.id, recordType: "workout"))
                        context.delete(entry)
                        persist()
                    }
                }
            }
            .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") {} } message: { Text(error ?? "") }
        }
    }
    private func save() {
        let record = entry ?? WorkoutEntry()
        if entry == nil { context.insert(record) }
        record.date = start
        record.endDate = finished ? end : nil
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = .now
        persist()
    }
    private func persist() {
        do { try context.save(); Task { await sync.sync(context: context, settings: settings) }; dismiss() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}
