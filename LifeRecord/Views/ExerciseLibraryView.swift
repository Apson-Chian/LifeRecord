import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @AppStorage(ExerciseLibrary.key) private var raw = "[]"
    @State private var templates: [ExerciseTemplate] = []
    @State private var newName = ""
    @State private var newPart: String?
    @State private var message: String?

    init(initialBodyPart: String? = nil) {
        _newPart = State(initialValue: initialBodyPart)
    }

    var body: some View {
        Form {
            Section {
                TextField("新动作名称，例如杠铃划船", text: $newName)
                TrainingBodyPartPicker(title: "归属部位", selection: $newPart)
                Button("添加动作", systemImage: "plus") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !templates.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                        message = "动作库已有这个名称。"; return
                    }
                    templates.append(.init(name: name, bodyPart: newPart)); newName = ""; save()
                }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newName.count > 100 || templates.count >= 100)
            } header: { Text("添加自定义动作") } footer: { Text("动作库保存在这台设备。修改或删除模板不会改变已保存的训练。") }
            Section("我的动作（\(templates.count)）") {
                ForEach($templates) { $template in
                    DisclosureGroup {
                        TextField("动作名称", text: $template.name).onSubmit { save() }
                        TrainingBodyPartPicker(title: "默认训练部位", selection: $template.bodyPart)
                    } label: {
                        HStack {
                            Text(template.name)
                            Spacer()
                            Text(template.bodyPart ?? "未分类").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }.onDelete { indices in templates.remove(atOffsets: indices); save() }
                if templates.isEmpty { Text("添加常练的动作，并设置默认部位。记录训练时会自动带入，仍可按当天训练修改。").foregroundStyle(.secondary) }
            }
            if let message { Text(message).foregroundStyle(.red) }
        }
        .navigationTitle("我的动作库")
        .keyboardDoneButton()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onAppear { templates = ExerciseLibrary.decode(raw) }
        .onDisappear { save() }
    }
    private func save() {
        let values = templates.map { item in
            var item = item; item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines); return item
        }
        guard values.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 100 }),
              Set(values.map { $0.name.lowercased() }).count == values.count else {
            message = "动作名称不能为空、超过 100 字或重复。"; return
        }
        raw = ExerciseLibrary.encode(values); message = nil
    }
}

struct WorkoutBodyPartManagerView: View {
    var onRename: ((String, String) -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Query private var workouts: [WorkoutEntry]
    @AppStorage(WorkoutBodyParts.key) private var catalogRaw = ""
    @AppStorage(ExerciseLibrary.key) private var libraryRaw = "[]"
    @State private var newName = ""
    @State private var editedName = ""
    @State private var renameTarget: PartName?
    @State private var message: String?

    init(initialRename: String? = nil, onRename: ((String, String) -> Void)? = nil) {
        self.onRename = onRename
        _renameTarget = State(initialValue: initialRename.map(PartName.init))
        _editedName = State(initialValue: initialRename ?? "")
    }

    private var historicalParts: [String] {
        Array(Set(workouts.flatMap(\.bodyParts)).subtracting(choices)).sorted()
    }
    private var choices: [String] { WorkoutBodyParts.decodedChoices(catalogRaw) }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("例如：二头、三头、小臂", text: $newName)
                        .submitLabel(.done)
                        .onSubmit(addPart)
                    Button("添加", action: addPart)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: { Text("新增训练部位") }
            if choices.contains("手臂") {
                Section {
                    Button("将手臂细分为二头、三头、小臂", systemImage: "square.split.3x1") {
                        store(WorkoutBodyParts.splittingArms(in: choices))
                        message = "已加入三个细分部位。旧的手臂训练仍保留，可逐条改成对应部位。"
                    }
                }
            }
            Section {
                ForEach(choices, id: \.self) { part in
                    HStack {
                        Text(part)
                        Spacer()
                        Menu {
                            Button("改名", systemImage: "pencil") { editedName = part; message = nil; renameTarget = PartName(part) }
                            Button("从可选部位移除", systemImage: "minus.circle", role: .destructive) {
                                store(choices.filter { $0 != part })
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(width: 44, height: 36)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("管理\(part)")
                    }
                }
            } header: { Text("以后训练可选的部位") }
            footer: { Text("可自由添加、改名或移除。移除只影响以后选择，已有训练记录不会丢失。") }
            if !historicalParts.isEmpty {
                Section("历史记录中的其他部位") {
                    ForEach(historicalParts, id: \.self) { part in
                        HStack {
                            Text(part)
                            Spacer()
                            Button("加入可选部位") { store(choices + [part]) }
                                .font(.caption)
                        }
                    }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("管理训练部位")
        .keyboardDoneButton()
        .sheet(item: $renameTarget) { target in
            NavigationStack {
                Form {
                    TextField("部位名称", text: $editedName)
                    Text("改名会同时更新全部历史训练和动作库中的对应部位。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let message { Text(message).foregroundStyle(.red) }
                }
                .navigationTitle("部位改名")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { renameTarget = nil; message = nil } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { rename(target.name) } }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func store(_ values: [String]) {
        WorkoutBodyParts.saveChoices(values)
        catalogRaw = UserDefaults.standard.string(forKey: WorkoutBodyParts.key) ?? ""
    }

    private func addPart() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WorkoutBodyParts.isValid(name),
              !choices.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            message = "名称需在 30 字以内，且不能与可选部位重复。"; return
        }
        store(choices + [name])
        newName = ""; message = nil
    }

    private func rename(_ oldName: String) {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WorkoutBodyParts.isValid(name),
              name == oldName || !choices.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
                && !workouts.contains(where: { $0.bodyParts.contains(name) }) else {
            message = "请输入不重复且不超过 30 字的名称。"; return
        }
        guard name != oldName else { renameTarget = nil; message = nil; return }
        for entry in workouts where entry.bodyParts.contains(oldName) {
            entry.bodyParts = entry.bodyParts.map { $0 == oldName ? name : $0 }
            var exercises = entry.exercises
            for index in exercises.indices where exercises[index].bodyPart == oldName { exercises[index].bodyPart = name }
            entry.exercises = exercises
            entry.updatedAt = .now
        }
        do { try context.save() }
        catch { context.rollback(); message = error.localizedDescription; return }
        var updatedChoices = choices
        if let index = updatedChoices.firstIndex(of: oldName) { updatedChoices[index] = name }
        else { updatedChoices.append(name) }
        store(updatedChoices)
        var templates = ExerciseLibrary.decode(libraryRaw)
        for index in templates.indices where templates[index].bodyPart == oldName { templates[index].bodyPart = name }
        libraryRaw = ExerciseLibrary.encode(templates)
        onRename?(oldName, name)
        Task { await sync.sync(context: context, settings: settings) }
        renameTarget = nil; message = nil
    }

    private struct PartName: Identifiable {
        let name: String
        var id: String { name }
        nonisolated init(_ name: String) { self.name = name }
    }
}

struct WorkoutBodyPartsPicker: View {
    @Binding var selection: [String]
    @AppStorage(WorkoutBodyParts.key) private var catalogRaw = ""
    @State private var newPart = ""
    @State private var error: String?
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(WorkoutBodyParts.normalized(WorkoutBodyParts.decodedChoices(catalogRaw) + selection), id: \.self) { part in
                    let selected = selection.contains(part)
                    Button {
                        if selected { selection.removeAll { $0 == part } }
                        else { selection = WorkoutBodyParts.normalized(selection + [part]) }
                    } label: {
                        Text(part)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(selected ? Color.teal.opacity(0.16) : Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Color.teal : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? Color.teal : Color.primary)
                    .accessibilityValue(selected ? "已选择" : "未选择")
                }
            }
            HStack {
                TextField("自定义部位名称", text: $newPart)
                    .textInputAutocapitalization(.never)
                Button("添加") { addPart() }
                    .disabled(newPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func addPart() {
        let name = newPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WorkoutBodyParts.isValid(name), !WorkoutBodyParts.choices.contains(name) else {
            error = "部位名称需在 30 字以内，且不能重复。"; return
        }
        WorkoutBodyParts.saveChoices(WorkoutBodyParts.choices + [name])
        catalogRaw = UserDefaults.standard.string(forKey: WorkoutBodyParts.key) ?? ""
        selection = WorkoutBodyParts.normalized(selection + [name])
        newPart = ""; error = nil
    }
}

struct WorkoutExerciseFields: View {
    @Binding var exercise: WorkoutExercise
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                TextField("动作名称", text: $exercise.name)
                    .font(.body.weight(.medium))
                Menu {
                    Button("移除此动作", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("动作选项")
            }
            TrainingBodyPartPicker(title: "训练部位", selection: $exercise.bodyPart)
            DisclosureGroup {
                ForEach(Array(exercise.sets.indices), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("第 \(index + 1) 组").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("删除组", role: .destructive) { exercise.sets.remove(at: index) }
                        }
                        HStack {
                            Text("次数").frame(width: 60, alignment: .leading)
                            TextField("未填写", value: $exercise.sets[index].reps, format: .number).keyboardType(.numberPad)
                        }
                        HStack {
                            Text("kg").frame(width: 60, alignment: .leading)
                            TextField("自重可填 0", value: $exercise.sets[index].weight, format: .number).keyboardType(.decimalPad)
                        }
                        HStack {
                            Text("秒").frame(width: 60, alignment: .leading)
                            TextField("计时动作选填", value: $exercise.sets[index].durationSeconds, format: .number).keyboardType(.numberPad)
                        }
                    }.padding(.vertical, 6)
                }
                Button("增加一组", systemImage: "plus") {
                    var set = exercise.sets.last ?? WorkoutSet(); set.id = UUID(); exercise.sets.append(set)
                }.disabled(exercise.sets.count >= 100)
            } label: {
                Label(exercise.sets.isEmpty ? "添加组数和训练数据（选填）" : "训练数据 · \(exercise.sets.count) 组",
                      systemImage: "list.number")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TrainingBodyPartPicker: View {
    let title: String
    @Binding var selection: String?
    @AppStorage(WorkoutBodyParts.key) private var catalogRaw = ""
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(WorkoutBodyParts.normalized(WorkoutBodyParts.decodedChoices(catalogRaw) + [selection ?? ""]) + ["未分类"], id: \.self) { part in
                    let selected = (selection ?? "未分类") == part
                    Button {
                        selection = part == "未分类" ? nil : part
                    } label: {
                        Text(part)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(selected ? Color.teal.opacity(0.16) : Color(.tertiarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Color.teal : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? Color.teal : Color.primary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}
