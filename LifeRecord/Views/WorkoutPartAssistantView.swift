import SwiftUI
import SwiftData

struct WorkoutPartAssistantView: View {
    let focusedPart: String?
    let recordIDs: Set<UUID>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]

    @State private var input = ""
    @State private var messages: [AIChatMessage] = []
    @State private var modelHistory: [AIChatMessage] = []
    @State private var proposal: WorkoutPartReviewReply?
    @State private var originals: [UUID: WorkoutPartReviewRecord] = [:]
    @State private var isSending = false
    @State private var requestTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private var eligibleWorkouts: [WorkoutEntry] {
        workouts.filter { entry in
            !entry.isDeleted && recordIDs.contains(entry.id) && (focusedPart.map { entry.bodyParts.contains($0) } ?? true)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text(focusedPart.map { "正在调整当前范围内「\($0)」分组的训练" } ?? "描述你想怎样调整当前范围的训练部位")
                            .font(.headline)
                        Text("AI 会先列出要改的记录和新部位。核对预览后点“应用修改”，才会写入训练记录。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if eligibleWorkouts.isEmpty {
                            Text("当前范围没有可调整的训练记录。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(messages.indices, id: \.self) { index in
                            let message = messages[index]
                            Text(message.content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(message.role == "user" ? Color.teal.opacity(0.12) : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if isSending { ProgressView("正在整理修改预览…") }
                        if let proposal, !proposal.changes.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("修改预览").font(.headline)
                                ForEach(proposal.changes, id: \.id) { change in
                                    if let id = UUID(uuidString: change.id), let entry = workouts.first(where: { $0.id == id }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                                            Text("\(partNames(originals[id]?.bodyParts ?? [])) → \(partNames(change.bodyParts))")
                                                .font(.subheadline)
                                            if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                            if !entry.exercises.isEmpty {
                                                Text(entry.exercises.map(\.name).joined(separator: "、"))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                Button("应用 \(proposal.changes.count) 条修改", action: applyProposal)
                                    .buttonStyle(.borderedProminent)
                                    .tint(.teal)
                                    .disabled(isSending || !settings.aiCanWrite)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    }
                    .padding(16)
                }
                Divider()
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("例如：把这条手臂训练改为二头、三头、小臂", text: $input, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($inputFocused)
                    Button("发送", action: send)
                        .disabled(isSending || eligibleWorkouts.isEmpty || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !settings.aiCanWrite)
                }
                .padding(14)
            }
            .background(AppBackground())
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("AI 调整训练部位")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onDisappear {
                requestTask?.cancel()
                isSending = false
            }
            .overlay(alignment: .top) {
                if !settings.aiCanWrite {
                    Text("请先在设置中开启“允许 AI 修改记录”。")
                        .font(.caption)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                }
            }
        }
    }

    private func partNames(_ parts: [String]) -> String {
        parts.isEmpty ? "未分类" : parts.joined(separator: "、")
    }

    private func snapshot(_ entry: WorkoutEntry) -> WorkoutPartReviewRecord {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return WorkoutPartReviewRecord(id: entry.id.uuidString, date: formatter.string(from: entry.date),
                                       bodyParts: entry.bodyParts, note: String(entry.note.prefix(600)),
                                       exerciseNames: Array(entry.exercises.map(\.name).prefix(50)), updatedAt: entry.updatedAt)
    }

    @MainActor
    private func send() {
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isSending, settings.aiCanWrite, !eligibleWorkouts.isEmpty else { return }
        input = ""
        errorMessage = nil
        if proposal != nil {
            modelHistory.append(AIChatMessage(role: "assistant", content: "上一份预览已被新请求替代，未应用到记录。"))
        }
        proposal = nil
        messages.append(AIChatMessage(role: "user", content: request))
        modelHistory.append(AIChatMessage(role: "user", content: request))
        let records = eligibleWorkouts.map(snapshot)
        let history = modelHistory
        isSending = true
        inputFocused = false
        requestTask = Task {
            do {
                let reply = try await AIClient(settings: settings).reviewWorkoutParts(messages: history, records: records, focusedPart: focusedPart)
                guard !Task.isCancelled else { return }
                originals = Dictionary(uniqueKeysWithValues: records.compactMap { record in
                    UUID(uuidString: record.id).map { ($0, record) }
                })
                proposal = reply
                messages.append(AIChatMessage(role: "assistant", content: reply.answer.isEmpty ? (reply.changes.isEmpty ? "没有需要应用的部位修改。请补充要调整的日期和部位。" : "请核对下方修改预览。") : reply.answer))
                if let data = try? JSONEncoder().encode(reply) {
                    modelHistory.append(AIChatMessage(role: "assistant", content: String(decoding: data, as: UTF8.self)))
                }
            } catch {
                if !Task.isCancelled { errorMessage = "生成预览失败：\(error.localizedDescription)" }
            }
            if !Task.isCancelled { isSending = false }
        }
    }

    @MainActor
    private func applyProposal() {
        guard settings.aiCanWrite, !isSending, let proposal, !proposal.changes.isEmpty else { return }
        let updates: [(WorkoutEntry, [String])] = proposal.changes.compactMap { change in
            guard let id = UUID(uuidString: change.id),
                  let entry = workouts.first(where: { $0.id == id && !$0.isDeleted }),
                  recordIDs.contains(id), let original = originals[id],
                  WorkoutPartReview.canApply(original: original, current: snapshot(entry), focusedPart: focusedPart) else { return nil }
            return (entry, change.bodyParts)
        }
        guard updates.count == proposal.changes.count else {
            errorMessage = "训练记录已变化，请重新生成预览。"
            self.proposal = nil
            modelHistory.append(AIChatMessage(role: "assistant", content: "训练记录已变化，预览没有保存，需要根据最新记录重新生成。"))
            return
        }
        for (entry, parts) in updates {
            entry.bodyParts = parts
            entry.updatedAt = .now
        }
        do { try context.save() }
        catch { context.rollback(); errorMessage = "保存失败：\(error.localizedDescription)"; return }
        self.proposal = nil
        errorMessage = nil
        let confirmation = AIChatMessage(role: "assistant", content: "已保存 \(updates.count) 条训练的部位修改。")
        messages.append(confirmation)
        modelHistory.append(confirmation)
        Task { await sync.sync(context: context, settings: settings) }
    }
}
