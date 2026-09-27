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
                    Button("补记", systemImage: "plus") { adding = true }
                        .buttonStyle(AppButtonStyle(tint: .teal, prominent: false))
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
                    }.buttonStyle(AppButtonStyle(tint: Color(red: 0.05, green: 0.43, blue: 0.43)))
                } else if Calendar.current.isDateInToday(date) {
                    Text("留一点时间，给更好的自己").font(.subheadline).foregroundStyle(.secondary)
                    Button { context.insert(WorkoutEntry()); persist() } label: {
                        Label("开始训练", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(AppButtonStyle(tint: Color(red: 0.05, green: 0.43, blue: 0.43)))
                }
                if entries.isEmpty && active == nil {
                    Text("当天还没有训练记录").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.endDate == nil ? "timer" : "checkmark.circle.fill")
                                .font(.title3).foregroundStyle(.teal)
                                .frame(width: 40, height: 40)
                                .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.contentSummary.isEmpty ? "健身训练" : entry.contentSummary).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text("\(entry.date.formatted(date: .omitted, time: .shortened)) → \(entry.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "进行中")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.endDate != nil { Text("\(Int(entry.minutes)) 分钟").font(.subheadline.monospacedDigit()) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(PressScaleButtonStyle())
                        .foregroundStyle(.primary)
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
    @State private var exercises: [WorkoutExercise]
    @AppStorage(ExerciseLibrary.key) private var libraryRaw = "[]"
    @State private var aiInput = ""
    @State private var aiDraft: WorkoutAIDraft?
    @State private var isGenerating = false
    @State private var aiTask: Task<Void, Never>?


    init(entry: WorkoutEntry?, date: Date) {
        self.entry = entry
        let start = entry?.date ?? min(date, .now)
        _start = State(initialValue: start)
        _end = State(initialValue: entry?.endDate ?? min(start.addingTimeInterval(3600), .now))
        _finished = State(initialValue: entry == nil || entry?.endDate != nil)
        _note = State(initialValue: entry?.note ?? "")
        _exercises = State(initialValue: entry?.exercises ?? [])
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
                Section {
                    Menu("从动作库添加", systemImage: "list.bullet") {
                        ForEach(ExerciseLibrary.decode(libraryRaw)) { template in
                            Button(template.name) { exercises.append(.init(name: template.name, sets: [])) }
                        }
                    }.disabled(ExerciseLibrary.decode(libraryRaw).isEmpty || exercises.count >= 50)
                    Button("添加自定义动作", systemImage: "plus") { exercises.append(.init(name: "", sets: [])) }.disabled(exercises.count >= 50)
                    NavigationLink("管理我的动作库") { ExerciseLibraryView() }
                } header: { Text("训练动作") } footer: { Text("选中动作即可保存；需要记录组数、次数、重量或时长时，展开动作填写。") }
                if !exercises.isEmpty {
                    Section("已选动作") {
                        ForEach($exercises) { $exercise in
                            WorkoutExerciseFields(exercise: $exercise) { exercises.removeAll { $0.id == exercise.id } }
                        }
                    }
                }
                Section {
                    TextField("例如：卧推 3 组，每组 8 次 40 kg；平板支撑 2 组各 60 秒", text: $aiInput, axis: .vertical).lineLimit(3...6)
                    Button(isGenerating ? "正在整理…" : "AI 整理动作", systemImage: "sparkles") { generateDraft() }
                        .disabled(isGenerating || aiInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let draft = aiDraft {
                        Text(draft.explanation).font(.subheadline).foregroundStyle(.secondary)
                        ForEach(draft.exercises) { exercise in Text(exercise.summary).font(.subheadline) }
                        Button("将草稿追加到本次训练") {
                            exercises.append(contentsOf: draft.exercises); aiDraft = nil
                        }.disabled(draft.exercises.isEmpty || exercises.count + draft.exercises.count > 50)
                        Button("放弃草稿", role: .destructive) { aiDraft = nil }
                    }
                } header: { Text("AI 录入") } footer: { Text("AI 使用设置中的接口，只整理你提供的数据；追加后仍可编辑，保存训练后才会写入记录。") }
                Section("健身内容") {
                    TextField("例如：深蹲 4 组 × 8 次，慢跑 20 分钟", text: $note, axis: .vertical).lineLimit(4...10)
                }
                if entry != nil { Section { Button("删除记录", role: .destructive) { confirmDelete = true } } }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissControl()
            .navigationTitle(entry == nil ? "补记训练" : "训练详情")
            .onChange(of: aiInput) { _, _ in aiTask?.cancel(); isGenerating = false; aiDraft = nil }
            .onDisappear { aiTask?.cancel(); isGenerating = false }
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
    private func generateDraft() {
        isGenerating = true; aiDraft = nil
        aiTask = Task {
            do {
                let draft = try await AIClient(settings: settings).workoutDraft(description: aiInput, library: ExerciseLibrary.decode(libraryRaw).map(\.name))
                guard !Task.isCancelled else { return }
                aiDraft = draft
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { isGenerating = false }
        }
    }
    private func save() {
        do { try WorkoutExercise.validate(exercises) } catch { self.error = error.localizedDescription; return }
        guard note.count <= 10000 else { error = "训练备注最多 10000 字。"; return }
        guard start <= .now, !finished || (end >= start && end <= .now) else { error = "请检查训练起止时间。"; return }
        let record = entry ?? WorkoutEntry()
        if entry == nil { context.insert(record) }
        record.exercises = exercises
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
