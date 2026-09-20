import SwiftUI

struct ExerciseLibraryView: View {
    @AppStorage(ExerciseLibrary.key) private var raw = "[]"
    @State private var templates: [ExerciseTemplate] = []
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("新动作名称，例如杠铃划船", text: $newName)
                Button("添加动作", systemImage: "plus") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !templates.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                        message = "动作库已有这个名称。"; return
                    }
                    templates.append(.init(name: name)); newName = ""; save()
                }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newName.count > 100 || templates.count >= 100)
            } header: { Text("添加自定义动作") } footer: { Text("动作库保存在这台设备。修改或删除模板不会改变已保存的训练。") }
            Section("我的动作（\(templates.count)）") {
                ForEach($templates) { $template in
                    TextField("动作名称", text: $template.name).onSubmit { save() }
                }.onDelete { indices in templates.remove(atOffsets: indices); save() }
                if templates.isEmpty { Text("添加常练的动作，记录训练时一键选用。").foregroundStyle(.secondary) }
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

struct WorkoutExerciseFields: View {
    @Binding var exercise: WorkoutExercise
    let remove: () -> Void
    var body: some View {
        DisclosureGroup {
            TextField("动作名称", text: $exercise.name)
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
            Button("移除此动作", role: .destructive, action: remove)
        } label: {
            HStack {
                Text(exercise.name.isEmpty ? "自定义动作（点击填写）" : exercise.name)
                Spacer()
                if !exercise.sets.isEmpty {
                    Text("\(exercise.sets.count) 组").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
