import SwiftUI

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

struct WorkoutBodyPartsPicker: View {
    @Binding var selection: [String]
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(WorkoutBodyParts.choices, id: \.self) { part in
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
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(WorkoutExercise.bodyParts, id: \.self) { part in
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
