import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \BodyMetric.date, order: .reverse) private var bodyMetrics: [BodyMetric]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waterEntries: [WaterEntry]

    @State private var selectedDate = Date.now
    @State private var activeSheet: SheetDestination?
    @State private var lifeTrackActivity = SharedProfileStore.lifeTrackActivity()
    @State private var errorMessage: String?

    private enum SheetDestination: String, Identifiable {
        case meal, weight, water
        var id: String { rawValue }
    }

    private var selectedMeals: [MealEntry] {
        meals.filter { Calendar.current.isSameDay($0.date, selectedDate) }
    }

    private var nutrition: DailyNutrition {
        selectedMeals.reduce(into: DailyNutrition()) { $0.add($1) }
    }

    private var water: Double {
        waterEntries
            .filter { Calendar.current.isSameDay($0.date, selectedDate) }
            .reduce(0) { $0 + $1.milliliters }
    }

    private var recordedDates: Set<Date> {
        let calendar = Calendar.current
        return Set(
            (meals.map(\.date) + bodyMetrics.map(\.date) + waterEntries.map(\.date))
                .map(calendar.startOfDay(for:))
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 18) {
                        DateNavigator(selectedDate: $selectedDate, recordedDates: recordedDates)
                        demoDataBanner
                        goalHero
                        quickActions
                        lifeTrackCard
                        macroCard
                        mealLog
                        insightCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { activeSheet = .meal } label: {
                            Label("记一餐", systemImage: "fork.knife")
                        }
                        Button { activeSheet = .weight } label: {
                            Label("记体重", systemImage: "scalemass")
                        }
                        Menu {
                            ForEach(WaterEntry.commonAmounts, id: \.self) { amount in
                                Button("\(Int(amount)) ml") { addQuickWater(amount) }
                            }
                        } label: {
                            Label("记录饮水", systemImage: "drop")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(AppTheme.accent)
                            .background(.regularMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(AppTheme.accent.opacity(0.24), lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("添加记录")
                }
            }
            .onAppear {
                publishSharedDailySummary()
                lifeTrackActivity = SharedProfileStore.lifeTrackActivity()
            }
            .onChange(of: selectedMeals.count) { _, _ in publishSharedDailySummary() }
            .onChange(of: waterEntries.count) { _, _ in publishSharedDailySummary() }
            .onChange(of: selectedDate) { _, _ in publishSharedDailySummary() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    lifeTrackActivity = SharedProfileStore.lifeTrackActivity()
                }
            }
            .sheet(item: $activeSheet) { destination in
                switch destination {
                case .meal: AddMealView(defaultDate: selectedDate)
                case .weight: AddWeightView(defaultDate: selectedDate, lastWeight: bodyMetrics.first?.weight ?? settings.baselineWeight)
                case .water: AddWaterView(defaultDate: selectedDate)
                }
            }
            .alert("无法保存记录", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let prefix = hour < 11 ? "早上好" : (hour < 18 ? "今天状态如何" : "晚上好")
        return settings.displayName.isEmpty ? prefix : "\(prefix)，\(settings.displayName)"
    }

    @ViewBuilder
    private var demoDataBanner: some View {
        if selectedMeals.contains(where: \.isDemo) || bodyMetrics.contains(where: \.isDemo) || waterEntries.contains(where: \.isDemo) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("完整示例数据已写入")
                        .font(.caption.weight(.semibold))
                    Text("首页、趋势、教练都会展示对应效果")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("清除") {
                    DemoDataService.clear(context: modelContext)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var goalHero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(settings.fitnessGoal.rawValue, systemImage: settings.fitnessGoal.symbol)
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                        Text(settings.fitnessGoal.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(settings.height)) cm")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 20) {
                    NutritionActivityRings(
                        mealCount: selectedMeals.count,
                        protein: nutrition.protein,
                        proteinGoal: settings.proteinGoal,
                        carbs: nutrition.carbs,
                        carbsGoal: settings.carbsGoal
                    )
                    .frame(width: 132, height: 132)

                    VStack(alignment: .leading, spacing: 12) {
                        RingLegend(title: "用餐", value: "\(selectedMeals.count) / 4 次", color: AppTheme.meals)
                        RingLegend(
                            title: "碳水",
                            value: "\(Int(nutrition.carbs)) / \(Int(settings.carbsGoal)) g",
                            color: AppTheme.carbs
                        )
                        RingLegend(
                            title: "蛋白质",
                            value: "\(Int(nutrition.protein)) / \(Int(settings.proteinGoal)) g",
                            color: AppTheme.protein
                        )
                    }
                }

                Label(calorieStatusText, systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var calorieStatusText: String {
        let remaining = settings.calorieGoal - nutrition.calories
        if remaining >= 0 { return "还差 \(Int(remaining)) 千卡" }
        return "超出 \(Int(abs(remaining))) 千卡"
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            ActionTile(title: "记一餐", subtitle: "多图/配料表", symbol: "fork.knife.circle.fill", tint: AppTheme.accent) {
                activeSheet = .meal
            }
            ActionTile(title: "记体重", subtitle: "追踪趋势", symbol: "scalemass.fill", tint: AppTheme.protein) {
                activeSheet = .weight
            }
            ActionTile(title: "喝水", subtitle: "选择常用容量", symbol: "drop.fill", tint: AppTheme.water) {
                activeSheet = .water
            }
        }
    }

    private func addQuickWater(_ amount: Double) {
        let entry = WaterEntry(date: selectedDate, milliliters: amount)
        modelContext.insert(entry)
        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            modelContext.delete(entry)
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @ViewBuilder
    private var lifeTrackCard: some View {
        if let activity = lifeTrackActivity, Calendar.current.isDateInToday(activity.date) {
            GlassCard {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "figure.run")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.accent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("LifeTrack 今日运动").font(.headline)
                            Spacer()
                            Button {
                                _ = LifeLink.openLifeTrack()
                            } label: {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("打开 LifeTrack")
                        }
                        Text("\(activity.distance / 1000, specifier: "%.2f") km · \(Int(activity.duration / 60)) 分钟 · \(activity.sessionCount) 次记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func publishSharedDailySummary() {
        SharedProfileStore.publishDailySummary(
            date: selectedDate,
            nutrition: nutrition,
            water: water
        )
    }

    private var macroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("营养目标").font(.headline)
                MacroProgressView(title: "蛋白质", value: nutrition.protein, goal: settings.proteinGoal, color: AppTheme.protein)
                MacroProgressView(title: "碳水", value: nutrition.carbs, goal: settings.carbsGoal, color: AppTheme.carbs)
                MacroProgressView(title: "脂肪", value: nutrition.fat, goal: settings.fatGoal, color: AppTheme.fat)
                MacroProgressView(title: "饮水", value: water / 1000, goal: settings.waterGoal / 1000, color: AppTheme.water, unit: "L")
            }
        }
    }

    private var mealLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("饮食记录").font(.title3.bold())
                Spacer()
                NavigationLink("查看全部") {
                    MealHistoryView()
                }
                .font(.subheadline.weight(.semibold))
            }
            if selectedMeals.isEmpty {
                GlassCard {
                    ContentUnavailableView {
                        Label("还没有餐食", systemImage: "fork.knife.circle")
                    } description: {
                        Text("用文字、照片或手动方式记录第一餐。")
                    } actions: {
                        Button("添加餐食") { activeSheet = .meal }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ForEach(MealKind.allCases) { kind in
                    let group = selectedMeals.filter { $0.kind == kind }
                    if !group.isEmpty {
                        MealSection(kind: kind, meals: group)
                    }
                }
            }
        }
    }

    private var insightCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "wand.and.sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日提示").font(.headline)
                    Text(localInsight)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var localInsight: String {
        guard !selectedMeals.isEmpty else {
            return settings.fitnessGoal == .gainMuscle
                ? "你目前偏瘦，增肌期优先保证持续的热量盈余和力量训练。先记录真实摄入，连续两周再根据体重均值调整。"
                : "先记录真实情况，不追求完美。连续记录比单日数字更有分析价值。"
        }
        if nutrition.protein < settings.proteinGoal * 0.55 {
            return settings.fitnessGoal == .gainMuscle
                ? "蛋白质进度偏慢。下一餐先补一份 30–40g 蛋白质，同时搭配足量主食，增肌期不要只吃蛋白而忽略总热量。"
                : "蛋白质进度偏慢。下一餐可以优先安排一份易估量的优质蛋白。"
        }
        if nutrition.calories > settings.calorieGoal {
            return "今天已超过设定热量，但无需用极端节食补偿。保持正常训练与作息，关注一周平均值。"
        }
        return "今天的宏量营养进度比较平稳。晚些时候结合饥饿感和训练安排决定是否需要加餐。"
    }
}

private struct DateNavigator: View {
    @Binding var selectedDate: Date
    let recordedDates: Set<Date>
    private let calendar = Calendar.current
    @State private var isShowingCalendar = false

    var body: some View {
        HStack(spacing: 10) {
            Button { moveDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressScaleButtonStyle())

            Button {
                isShowingCalendar = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(selectedDate.formatted(.dateTime.year().month().day().weekday()))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !calendar.isDateInToday(selectedDate) {
                Button("今天") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 1)) { selectedDate = .now }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }

            Button { moveDay(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .sheet(isPresented: $isShowingCalendar) {
            RecordCalendarView(selectedDate: $selectedDate, recordedDates: recordedDates)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func moveDay(_ value: Int) {
        guard let next = calendar.date(byAdding: .day, value: value, to: selectedDate) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 1)) { selectedDate = next }
    }
}

private struct NutritionActivityRings: View {
    let mealCount: Int
    let protein: Double
    let proteinGoal: Double
    let carbs: Double
    let carbsGoal: Double

    var body: some View {
        ZStack {
            ActivityRing(progress: Double(mealCount) / 4, color: AppTheme.meals, lineWidth: 12)
                .padding(2)
            ActivityRing(progress: carbs / max(carbsGoal, 1), color: AppTheme.carbs, lineWidth: 11)
                .padding(19)
            ActivityRing(progress: protein / max(proteinGoal, 1), color: AppTheme.protein, lineWidth: 10)
                .padding(35)
            VStack(spacing: 0) {
                Text("\(mealCount)")
                    .font(.title3.bold().monospacedDigit())
                Text("餐")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日营养圆环")
        .accessibilityValue("用餐 \(mealCount) 次，蛋白质 \(Int(protein)) 克，碳水 \(Int(carbs)) 克")
    }
}

private struct ActivityRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.72), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.22), radius: 4, y: 2)
                .animation(.spring(response: 0.5, dampingFraction: 0.88), value: progress)
        }
    }
}

private struct RingLegend: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.3), radius: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct RecordCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let recordedDates: Set<Date>

    private let calendar = Calendar.current
    @State private var visibleMonth: Date

    init(selectedDate: Binding<Date>, recordedDates: Set<Date>) {
        _selectedDate = selectedDate
        self.recordedDates = recordedDates
        _visibleMonth = State(
            initialValue: Calendar.current.dateInterval(of: .month, for: selectedDate.wrappedValue)?.start
                ?? selectedDate.wrappedValue
        )
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leading) + dates
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack {
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 40, height: 40)
                    }
                    Spacer()
                    Text(visibleMonth.formatted(.dateTime.year().month(.wide)))
                        .font(.headline)
                    Spacer()
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 40, height: 40)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 7) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(height: 22)
                    }
                    ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                        if let date {
                            dayButton(date)
                        } else {
                            Color.clear.frame(height: 42)
                        }
                    }
                }

                HStack(spacing: 7) {
                    Circle().fill(AppTheme.recorded).frame(width: 6, height: 6)
                    Text("绿点表示当天已有记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let hasRecord = recordedDates.contains(calendar.startOfDay(for: date))

        return Button {
            selectedDate = date
            dismiss()
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 32, height: 30)
                    .background(isSelected ? AppTheme.accent : Color.clear, in: Circle())
                    .overlay {
                        if isToday && !isSelected {
                            Circle().stroke(AppTheme.accent.opacity(0.65), lineWidth: 1)
                        }
                    }
                Circle()
                    .fill(hasRecord ? AppTheme.recorded : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
        .accessibilityValue(hasRecord ? "已有记录" : "无记录")
    }

    private func moveMonth(_ value: Int) {
        guard let date = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { visibleMonth = date }
    }
}

private struct MealSection: View {
    @Environment(\.modelContext) private var modelContext
    let kind: MealKind
    let meals: [MealEntry]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(kind.rawValue, systemImage: kind.symbol)
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                ForEach(meals) { meal in
                    NavigationLink {
                        MealDetailView(meal: meal)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(meal.name).font(.subheadline.weight(.semibold))
                                    if meal.source == .ai {
                                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(AppTheme.accent)
                                    }
                                    if meal.isDemo {
                                        Text("示例")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppTheme.accent.opacity(0.12), in: Capsule())
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                Text("蛋白 \(meal.protein, specifier: "%.0f")g · 碳水 \(meal.carbs, specifier: "%.0f")g · 脂肪 \(meal.fat, specifier: "%.0f")g")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(meal.calories, specifier: "%.0f")")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            Text("kcal").font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("删除", systemImage: "trash", role: .destructive) {
                            modelContext.delete(meal)
                            try? modelContext.save()
                        }
                    }
                    if meal.id != meals.last?.id { Divider() }
                }
            }
        }
    }
}
