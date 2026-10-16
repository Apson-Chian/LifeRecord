import SwiftUI
import SwiftData

struct WorkoutCalendarView: View {
    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]
    @State private var displayedMonth = WorkoutCalendar.startOfMonth(containing: .now)
    @State private var selectedDay = WorkoutCalendar.calendar().startOfDay(for: .now)
    @State private var editing: WorkoutEntry?
    @State private var showsDayDetails = false
    @State private var now = Date.now
    @ScaledMetric(relativeTo: .caption2) private var cellHeight: CGFloat = 88
    private let calendar = WorkoutCalendar.calendar()
    private let tint = Color.green
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4, alignment: .top), count: 7)

    private var sessions: [WorkoutCalendar.Session] {
        workouts.filter { !$0.isDeleted }.map {
            .init(id: $0.id, date: $0.date, endDate: $0.endDate,
                  bodyParts: $0.bodyParts, note: $0.note, exercises: $0.exercises)
        }
    }

    private var selectedEntries: [WorkoutEntry] {
        workouts.filter { !$0.isDeleted && calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        let month = WorkoutCalendar.month(containing: displayedMonth, sessions: sessions, now: now, calendar: calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monthHeader
                Text("本月 \(month.recordedDays) 天 · \(month.completedCount) 次训练 · \(month.minutes.formatted(.number.precision(.fractionLength(0)))) 分钟")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                            Text(weekday).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Divider()
                    LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
                        ForEach(month.days) { day in dayCell(day) }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Label("绿色数字：记录训练量（kg·次）", systemImage: "square.fill")
                        .foregroundStyle(tint)
                    Text("按已填写的负重 × 次数累加；未填写数值不估算。点击日期查看完整内容，跨午夜训练归入开始日。")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("训练日历")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsDayDetails) {
            NavigationStack {
                ScrollView { selectedDayDetails.padding(16) }
                    .background(AppBackground())
                    .navigationTitle("当天训练")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showsDayDetails = false }
                        }
                    }
                    .sheet(item: $editing) { WorkoutEditor(entry: $0, date: $0.date) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear { now = .now }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("上个月")
            VStack(alignment: .leading, spacing: 2) {
                Text(String(calendar.component(.year, from: displayedMonth)))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(calendar.component(.month, from: displayedMonth))月")
                    .font(.title.bold())
            }
            .accessibilityElement(children: .combine)
            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("下个月")
            Spacer(minLength: 0)
            Button("回到本月") {
                now = .now
                displayedMonth = WorkoutCalendar.startOfMonth(containing: now, calendar: calendar)
                selectedDay = calendar.startOfDay(for: now)
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.bordered)
        }
        .tint(.primary)
    }

    private func dayCell(_ day: WorkoutCalendar.Day) -> some View {
        let selected = calendar.isDate(day.date, inSameDayAs: selectedDay)
        let today = calendar.isDate(day.date, inSameDayAs: now)
        return Button {
            selectedDay = day.date
            if !day.isInMonth { displayedMonth = WorkoutCalendar.startOfMonth(containing: day.date, calendar: calendar) }
            showsDayDetails = true
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day.date))")
                    .font(.subheadline.weight(today ? .bold : .regular))
                    .foregroundStyle(today ? Color.white : Color.primary)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(today ? tint : .clear, in: Circle())
                if day.completedCount > 0 {
                    Text(day.volume.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) } ?? "已训练")
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .foregroundStyle(Color.black)
                        .background(tint.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                } else if !day.sessions.isEmpty {
                    Text(day.sessions.contains { $0.endDate == nil && $0.date <= now } ? "进行中" : "待完成")
                        .font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .foregroundStyle(.orange)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }
                ForEach(day.sessions.prefix(2)) { session in
                    Text(session.title)
                        .font(.caption2).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 3))
                }
                if day.sessions.count > 2 {
                    Text("+\(day.sessions.count - 2) 条").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .top)
            .padding(.horizontal, 2).padding(.vertical, 4)
            .background(selected ? tint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(selected ? tint : .clear, lineWidth: 1) }
            .opacity(day.isInMonth ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted))，\(day.sessions.count) 条训练，已完成 \(day.completedCount) 次" + (day.volume.map { "，记录训练量 \($0.formatted()) 千克次" } ?? ""))
        .accessibilityValue(selected ? "已选择" : "")
        .accessibilityHint("查看当天的完整训练记录")
    }

    private var selectedDayDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDay.formatted(.dateTime.year().month().day().weekday()))
                .font(.headline)
            if selectedEntries.isEmpty {
                Text("当天没有训练记录").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
            }
            ForEach(selectedEntries) { entry in
                Button { editing = entry } label: {
                    GlassCard(tint: .teal) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(entry.date.formatted(.dateTime.hour().minute()))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                            Text(entry.contentSummary.isEmpty ? "未填写训练内容" : entry.contentSummary)
                                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            if let session = sessions.first(where: { $0.id == entry.id }), session.isCompleted(at: now) {
                                HStack {
                                    Text("\(entry.minutes.formatted(.number.precision(.fractionLength(0...1)))) 分钟")
                                    if let volume = session.volume {
                                        Text("· \(volume.formatted(.number.precision(.fractionLength(0...1)))) kg·次")
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(entry.endDate == nil && entry.date <= now ? "训练进行中，结束后计入统计" : "尚未计入已完成训练")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("编辑这次训练")
            }
        }
    }

    private func moveMonth(by offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = WorkoutCalendar.startOfMonth(containing: next, calendar: calendar)
        selectedDay = displayedMonth
    }
}
