import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WaterEntry.date) private var waterEntries: [WaterEntry]

    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]

    @State private var selectedRecordDay = Calendar.current.startOfDay(for: Date.now)
    @State private var range: TrendRange = .month
    @State private var report = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private enum TrendRange: String, CaseIterable, Identifiable {
        case week = "7 天"
        case month = "30 天"
        case all = "全部"

        var id: String { rawValue }
        var days: Int? { self == .week ? 7 : (self == .month ? 30 : nil) }
    }

    private var cutoff: Date? {
        guard let days = range.days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now))
    }

    private var filteredMetrics: [BodyMetric] {
        guard let cutoff else { return bodyMetrics }
        return bodyMetrics.filter { $0.date >= cutoff }
    }

    private var filteredMeals: [MealEntry] {
        guard let cutoff else { return meals }
        return meals.filter { $0.date >= cutoff }
    }

    private var filteredWater: [WaterEntry] {
        guard let cutoff else { return waterEntries }
        return waterEntries.filter { $0.date >= cutoff }
    }

    private var weightSeries: [BodyTrend.Point] {
        BodyTrend.series(bodyMetrics.map { .init(date: $0.date, value: $0.weight) })
    }

    private var fatSeries: [BodyTrend.Point] {
        BodyTrend.series(bodyMetrics.compactMap { metric in
            metric.bodyFat.map { .init(date: metric.date, value: $0) }
        })
    }

    private var dailyMetrics: [BodyTrend.Point] {
        weightSeries.filter { cutoff == nil || $0.date >= cutoff! }
    }

    private var bodyFatPoints: [BodyTrend.Point] {
        fatSeries.filter { cutoff == nil || $0.date >= cutoff! }
    }

    private var dailyNutrition: [(date: Date, calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double)] {
        let grouped = Dictionary(grouping: filteredMeals) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.map { date, items in
            (
                date: date,
                calories: items.reduce(0) { $0 + $1.calories },
                protein: items.reduce(0) { $0 + $1.protein },
                carbs: items.reduce(0) { $0 + $1.carbs },
                fat: items.reduce(0) { $0 + $1.fat },
                fiber: items.reduce(0) { $0 + $1.fiber }
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var dailyWater: [(date: Date, value: Double)] {
        let grouped = Dictionary(grouping: filteredWater) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.milliliters }) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 16) {
                        rangeCard
                        weightChart
                        bodyCompositionCard
                        calorieChart
                        waterChart
                        workoutChart
                        aiReportCard
                    }
                    .padding(16)
                    .padding(.bottom, 26)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("趋势")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ScrollView {
                            VStack(spacing: 16) {
                                bodyOverviewLink
                                measurementList
                                recordHeatmap
                                macroCard
                            }.padding(16)
                        }.navigationTitle("数据详情").background(AppBackground())
                    } label: { Image(systemName: "list.bullet.rectangle") }
                    .accessibilityLabel("查看全部数据详情")
                }
            }
            .alert("生成失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private var bodyOverviewLink: some View {
        NavigationLink {
            BodyDashboardView()
        } label: {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "figure.arms.open")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.accent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("身体总览").font(.headline)
                        Text("趋势体重 · 今日基准 · 身体组成").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rangeCard: some View {
        Picker("时间范围", selection: $range) {
            ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var summaryStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                SummaryMetric(title: "最近体重", value: latestWeight, detail: weightChangeText, symbol: "scalemass", tint: AppTheme.protein)
                SummaryMetric(title: "体脂率", value: latestBodyFat, detail: bodyFatChangeText, symbol: "figure.arms.open", tint: AppTheme.fat)
                SummaryMetric(title: "日均热量", value: averageCalories, detail: "\(dailyNutrition.count) 天记录", symbol: "flame", tint: .orange)
                SummaryMetric(title: "日均蛋白", value: averageProtein, detail: goalText(settings.proteinGoal), symbol: "bolt.fill", tint: .red)
                SummaryMetric(title: "日均碳水", value: averageCarbs, detail: goalText(settings.carbsGoal), symbol: "leaf.fill", tint: AppTheme.carbs)
                SummaryMetric(title: "日均脂肪", value: averageFat, detail: goalText(settings.fatGoal), symbol: "drop.triangle.fill", tint: AppTheme.fat)
                SummaryMetric(title: "日均纤维", value: averageFiber, detail: "建议 30 g", symbol: "leaf.circle.fill", tint: AppTheme.accent)
                SummaryMetric(title: "日均饮水", value: averageWater, detail: goalText(settings.waterGoal / 1000, unit: "L"), symbol: "drop.fill", tint: AppTheme.water)
                SummaryMetric(title: "有记录天数", value: consistencyText, detail: "最近 7 天", symbol: "calendar.badge.checkmark", tint: AppTheme.carbs)
                SummaryMetric(title: "距目标", value: distanceToGoal, detail: "目标 \(settings.targetWeight.formatted(.number.precision(.fractionLength(1)))) kg", symbol: "flag.checkered", tint: AppTheme.accent)
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private var weightChart: some View {
        InspectableTrendCard(title: "体重趋势", unit: "kg", tint: AppTheme.accent,
            points: dailyMetrics.map { TrendPoint(id: $0.date.description, date: $0.date, value: $0.value, note: "当日中位数 \($0.value.formatted(.number.precision(.fractionLength(1)))) kg · \($0.count) 次测量") },
            goal: settings.targetWeight, samples: bodyMetrics.map { .init(date: $0.date, value: $0.weight) }, cutoff: cutoff)
    }

    private var bodyCompositionCard: some View {
        InspectableTrendCard(title: "体脂趋势", unit: "%", tint: AppTheme.fat,
            points: bodyFatPoints.map { TrendPoint(id: $0.date.description, date: $0.date, value: $0.value, note: "当日中位数 \($0.value.formatted(.number.precision(.fractionLength(1))))% · \($0.count) 次测量") }, samples: bodyMetrics.compactMap { metric in metric.bodyFat.map { .init(date: metric.date, value: $0) } }, cutoff: cutoff)
    }

    private var measurementList: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("身体测量明细").font(.headline)
                Text("时间从新到旧 · 包含同一天的每次测量").font(.caption).foregroundStyle(.secondary)
                if filteredMetrics.isEmpty { Text("当前范围暂无测量").foregroundStyle(.secondary) }
                ForEach(Array(filteredMetrics.reversed().prefix(10))) { metric in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.date.formatted(.dateTime.month().day().hour().minute())).font(.subheadline)
                            if !metric.note.isEmpty { Text(metric.note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(metric.weight.formatted(.number.precision(.fractionLength(1)))) kg").font(.headline.monospacedDigit())
                            Text(metric.bodyFat.map { "体脂 \($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "体脂未测量")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
                if filteredMetrics.count > 10 {
                    NavigationLink("查看全部 \(filteredMetrics.count) 次测量") {
                        List(filteredMetrics.reversed()) { metric in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(metric.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                                Text("体重 \(metric.weight.formatted()) kg · 体脂 \(metric.bodyFat.map { $0.formatted() + "%" } ?? "未测量")").font(.headline)
                                if !metric.note.isEmpty { Text(metric.note).foregroundStyle(.secondary) }
                            }.padding(.vertical, 6)
                        }.navigationTitle("测量明细")
                    }
                }
            }
        }
    }

    private var calorieChart: some View {
        InspectableTrendCard(title: "每日热量", unit: "kcal", tint: .orange,
            points: dailyNutrition.map { TrendPoint(id: $0.date.description, date: $0.date, value: $0.calories, note: "当日餐食总量 · 蛋白质 \(Int($0.protein)) g · 碳水 \(Int($0.carbs)) g") }, goal: settings.calorieGoal, bars: true)
    }

    private var macroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                Text("宏量营养均值").font(.headline)
                MacroProgressView(title: "蛋白质", value: averageProteinValue, goal: settings.proteinGoal, color: AppTheme.protein)
                MacroProgressView(title: "碳水", value: averageCarbsValue, goal: settings.carbsGoal, color: AppTheme.carbs)
                MacroProgressView(title: "脂肪", value: averageFatValue, goal: settings.fatGoal, color: AppTheme.fat)
                MacroProgressView(title: "膳食纤维", value: averageFiberValue, goal: 30, color: AppTheme.accent)
            }
        }
    }

    private var waterChart: some View {
        InspectableTrendCard(title: "每日饮水", unit: "ml", tint: AppTheme.water,
            points: dailyWater.map { TrendPoint(id: $0.date.description, date: $0.date, value: $0.value, note: "当天所有饮水记录合计") }, goal: settings.waterGoal, bars: true)
    }

    private var workoutChart: some View {
        WorkoutTrendCard(workouts: workouts.filter { cutoff == nil || $0.date >= cutoff! }, cutoff: cutoff)
    }

    private var calendarDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -29, to: today)!
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -leading, to: first)!
        let count = leading + 30
        return (0..<((count + 6) / 7 * 7)).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private func dayCounts(_ day: Date) -> (meal: Int, body: Int, water: Int) {
        let c = Calendar.current
        return (meals.filter { c.isDate($0.date, inSameDayAs: day) }.count,
                bodyMetrics.filter { c.isDate($0.date, inSameDayAs: day) }.count,
                waterEntries.filter { c.isDate($0.date, inSameDayAs: day) }.count)
    }

    private var recordHeatmap: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("记录日历 · 最近 30 天").font(.headline)
                Text("从左到右周一至周日，从上到下由早到晚。颜色表示已记录的类型数，不代表是否达标。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(Calendar.current.date(byAdding: .day, value: -29, to: Date.now)!.formatted(.dateTime.month().day())) — \(Date.now.formatted(.dateTime.month().day()))")
                    .font(.subheadline.weight(.medium))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 6) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text("周" + $0).font(.caption).foregroundStyle(.secondary) }
                    ForEach(calendarDays, id: \.self) { day in
                        let counts = dayCounts(day)
                        let count = (counts.meal > 0 ? 1 : 0) + (counts.body > 0 ? 1 : 0) + (counts.water > 0 ? 1 : 0)
                        Button { selectedRecordDay = day } label: {
                            Text(day.formatted(.dateTime.day()))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(count >= 2 ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(recordColor(Double(count) / 3), in: RoundedRectangle(cornerRadius: 9))
                                .overlay { RoundedRectangle(cornerRadius: 9).stroke(Calendar.current.isDate(day, inSameDayAs: selectedRecordDay) ? AppTheme.accent : .clear, lineWidth: 2) }
                        }
                        .buttonStyle(.plain)
                        .disabled(day > Date.now || day < Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now))!)
                        .opacity(day > Date.now || day < Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now))! ? 0.25 : 1)
                        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted))，饮食 \(counts.meal) 条，身体 \(counts.body) 条，饮水 \(counts.water) 条")
                    }
                }
                HStack {
                    ForEach(0..<4) { count in
                        RoundedRectangle(cornerRadius: 3).fill(recordColor(Double(count) / 3)).frame(width: 12, height: 12)
                        Text("\(count) 类").font(.caption2)
                    }
                }
                let counts = dayCounts(selectedRecordDay)
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedRecordDay.formatted(.dateTime.year().month().day().weekday())).font(.subheadline.weight(.semibold))
                    Text("饮食 \(counts.meal) 条 · 身体 \(counts.body) 条 · 饮水 \(counts.water) 条").font(.subheadline).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var aiReportCard: some View {
        GlassCard(tint: AppTheme.accent) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.title2).foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 16))
                    Spacer()
                    Text("最近 7 天").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("把记录，变成下一步").font(.title2.bold())
                    Text(report.isEmpty ? "一份属于你的 AI 周报，发现变化，找到节奏。" : "本周复盘已就绪，查看趋势解读与行动建议。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !report.isEmpty {
                    NavigationLink {
                        ScrollView { Text(report).textSelection(.enabled).padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                            .navigationTitle("AI 周报")
                    } label: {
                        HStack { Text("阅读本周报告"); Spacer(); Image(systemName: "arrow.up.right") }
                            .font(.headline).padding(16)
                            .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                Button { Task { await generateReport() } } label: {
                    HStack {
                        if isGenerating { ProgressView() }
                        Text(isGenerating ? "正在整理这一周…" : (report.isEmpty ? "生成本周报告" : "重新生成"))
                        Spacer()
                        if !isGenerating { Image(systemName: "arrow.right") }
                    }.padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(isGenerating || (bodyMetrics.isEmpty && meals.isEmpty && waterEntries.isEmpty && workouts.isEmpty))
            }
        }
    }

    private var latestWeight: String {
        bodyMetrics.last.map { $0.weight.formatted(.number.precision(.fractionLength(1))) + " kg" } ?? "—"
    }

    private var weightChangeText: String {
        guard dailyMetrics.count >= 2, let first = dailyMetrics.first, let last = dailyMetrics.last else { return "至少记录两次" }
        let delta = last.trend - first.trend
        return "区间 \(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private var latestBodyFat: String {
        bodyMetrics.reversed().compactMap(\.bodyFat).first.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—"
    }

    private var bodyFatChangeText: String {
        let values = bodyFatPoints.map(\.value)
        guard values.count >= 2, let first = values.first, let last = values.last else { return "至少记录两次" }
        let delta = last - first
        return "区间 \(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) 个百分点"
    }

    private var averageCalories: String {
        guard !dailyNutrition.isEmpty else { return "—" }
        let value = dailyNutrition.reduce(0) { $0 + $1.calories } / Double(dailyNutrition.count)
        return "\(Int(value)) kcal"
    }

    private var averageProtein: String {
        guard !dailyNutrition.isEmpty else { return "—" }
        let value = dailyNutrition.reduce(0) { $0 + $1.protein } / Double(dailyNutrition.count)
        return "\(Int(value)) g"
    }

    private var averageCarbs: String {
        dailyNutrition.isEmpty ? "—" : "\(Int(averageCarbsValue)) g"
    }

    private var averageFat: String {
        dailyNutrition.isEmpty ? "—" : "\(Int(averageFatValue)) g"
    }

    private var averageFiber: String {
        dailyNutrition.isEmpty ? "—" : "\(Int(averageFiberValue)) g"
    }

    private var averageWater: String {
        guard !dailyWater.isEmpty else { return "—" }
        let value = dailyWater.reduce(0) { $0 + $1.value } / Double(dailyWater.count) / 1000
        return value.formatted(.number.precision(.fractionLength(1))) + " L"
    }

    private var averageProteinValue: Double {
        dailyNutrition.isEmpty ? 0 : dailyNutrition.reduce(0) { $0 + $1.protein } / Double(dailyNutrition.count)
    }

    private var averageCarbsValue: Double {
        dailyNutrition.isEmpty ? 0 : dailyNutrition.reduce(0) { $0 + $1.carbs } / Double(dailyNutrition.count)
    }

    private var averageFatValue: Double {
        dailyNutrition.isEmpty ? 0 : dailyNutrition.reduce(0) { $0 + $1.fat } / Double(dailyNutrition.count)
    }

    private var averageFiberValue: Double {
        dailyNutrition.isEmpty ? 0 : dailyNutrition.reduce(0) { $0 + $1.fiber } / Double(dailyNutrition.count)
    }

    private var distanceToGoal: String {
        guard let current = bodyMetrics.last?.weight else { return "—" }
        let delta = settings.targetWeight - current
        if abs(delta) < 0.2 { return "已接近" }
        return abs(delta).formatted(.number.precision(.fractionLength(1))) + " kg"
    }

    private var weightDomain: ClosedRange<Double> {
        let values = dailyMetrics.map(\.trend) + [settings.targetWeight]
        guard let minimum = values.min(), let maximum = values.max() else { return 40...100 }
        let padding = max((maximum - minimum) * 0.18, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    private var bodyFatDomain: ClosedRange<Double> {
        let values = bodyFatPoints.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else { return 5...40 }
        let padding = max((maximum - minimum) * 0.2, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }

    private var consistencyText: String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let days = Set((meals.map(\.date) + bodyMetrics.map(\.date) + waterEntries.map(\.date)).filter { $0 >= cutoff && $0 <= .now }.map { Calendar.current.startOfDay(for: $0) })
        return "\(days.count) / 7 天"
    }

    private var recordDays: [(date: Date, score: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let hasMeal = meals.contains { calendar.isDate($0.date, inSameDayAs: day) }
            let hasMetric = bodyMetrics.contains { calendar.isDate($0.date, inSameDayAs: day) }
            let hasWater = waterEntries.contains { calendar.isDate($0.date, inSameDayAs: day) }
            let score = (hasMeal ? 0.5 : 0) + (hasMetric ? 0.3 : 0) + (hasWater ? 0.2 : 0)
            return (day, score)
        }
    }

    private func recordColor(_ score: Double) -> Color {
        switch score {
        case ..<0.01: Color(.tertiarySystemFill)
        case ..<0.5: AppTheme.accent.opacity(0.24)
        case ..<0.8: AppTheme.accent.opacity(0.52)
        default: AppTheme.accent.opacity(0.82)
        }
    }

    private func goalText(_ value: Double, unit: String = "g") -> String {
        "目标 \(value.formatted(.number.precision(.fractionLength(0)))) \(unit)"
    }

    @MainActor
    private func generateReport() async {
        isGenerating = true
        defer { isGenerating = false }
        let weekStart = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now))!
        let recentWeights = weightSeries.filter { $0.date >= weekStart && $0.date <= .now }.map {
            "\($0.date.formatted(date: .numeric, time: .omitted)): 中位数\($0.value)kg，趋势\($0.trend)kg，\($0.count)次"
        }.joined(separator: ", ")
        let fat = fatSeries.filter { $0.date >= weekStart && $0.date <= .now }.map {
            "\($0.date.formatted(date: .numeric, time: .omitted)): 中位数\($0.value)%，趋势\($0.trend)%"
        }.joined(separator: ", ")
        let weekMeals = meals.filter { $0.date >= weekStart && $0.date <= .now }
        let nutrition = Dictionary(grouping: weekMeals) { Calendar.current.startOfDay(for: $0.date) }
        let calories = nutrition.keys.sorted().map { day in
            let entries = nutrition[day]!
            return "\(day.formatted(date: .numeric, time: .omitted)): \(Int(entries.reduce(0) { $0 + $1.calories }))kcal / P\(Int(entries.reduce(0) { $0 + $1.protein }))g"
        }.joined(separator: ", ")
        let weekWater = waterEntries.filter { $0.date >= weekStart && $0.date <= .now }
        let waterGroups = Dictionary(grouping: weekWater) { Calendar.current.startOfDay(for: $0.date) }
        let water = waterGroups.keys.sorted().map { day in
            "\(day.formatted(date: .numeric, time: .omitted)): \(Int(waterGroups[day]!.reduce(0) { $0 + $1.milliliters }))ml"
        }.joined(separator: ", ")
        let workoutContext = WorkoutSummary.context(workouts.filter { $0.date >= weekStart }.map {
            .init(date: $0.date, endDate: $0.endDate, note: $0.note)
        })
        let context = "健身记录：\(workoutContext)。最近7天（含今天）。目标体重 \(settings.targetWeight)kg，热量目标 \(settings.calorieGoal)kcal，饮水目标 \(settings.waterGoal)ml。体重：\(recentWeights)。体脂：\(fat)。每日营养：\(calories)。每日饮水：\(water)。身体数据每日中位数后指数平滑；无记录不代表零，不要把日内波动解释为脂肪变化。"
        do {
            report = try await AIClient(settings: settings).coachText(
                system: "你是克制、循证的健身记录教练。根据有限数据指出趋势和不确定性，用中文给出 3 条可执行建议，不做医疗诊断，不鼓励极端热量缺口。",
                messages: [AIChatMessage(role: "user", content: context)]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.11), in: Circle())
                Spacer()
            }
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(13)
        .frame(width: 154, height: 132, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}


private struct TrendPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let note: String
}

private struct InspectableTrendCard: View {
    let title: String
    let unit: String
    let tint: Color
    let points: [TrendPoint]
    var goal: Double? = nil
    var bars = false
    var samples: [BodyTrend.Sample]? = nil
    var cutoff: Date? = nil
    var isDetail = false
    var smoothed = false
    @State private var selection: Date?

    private var selected: TrendPoint? {
        guard let selection else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }
    private var domain: ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.25, unit == "kg" || unit == "%" ? 0.8 : 1)
        return (bars ? 0 : max(0, low - pad))...(bars ? max(high, goal ?? 0) * 1.15 + 1 : high + pad)
    }
    private var dates: ClosedRange<Date> {
        let first = points.first?.date ?? .now, last = points.last?.date ?? .now
        return first.addingTimeInterval(-43200)...last.addingTimeInterval(43200)
    }
    var body: some View {
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: bars ? "chart.bar.fill" : "waveform.path.ecg")
                        .foregroundStyle(tint).frame(width: 36, height: 36)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    Text(title).font(.headline)
                    Spacer()
                    if !isDetail {
                        NavigationLink { detail } label: { Image(systemName: "arrow.up.right").frame(width: 44, height: 44) }
                            .accessibilityLabel("查看\(title)详情")
                    }
                }
                if let selected {
                    HStack(alignment: .firstTextBaseline) {
                        Text(selected.value.formatted(.number.precision(.fractionLength(bars ? 0 : 1))))
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text(unit).foregroundStyle(.secondary)
                        Spacer()
                        Text(selection == nil ? "最新" : "已选中").font(.caption).foregroundStyle(tint)
                    }
                    Chart {
                        ForEach(points) { point in
                            if bars {
                                BarMark(x: .value("日期", point.date, unit: .day), y: .value(unit, point.value))
                                    .foregroundStyle(tint.opacity(point.id == selected.id ? 1 : 0.4)).cornerRadius(4)
                            } else {
                                AreaMark(x: .value("日期", point.date), yStart: .value("基线", domain.lowerBound), yEnd: .value(unit, point.value))
                                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.linear)
                                LineMark(x: .value("日期", point.date), y: .value(unit, point.value))
                                    .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.linear)
                                PointMark(x: .value("日期", point.date), y: .value(unit, point.value))
                                    .foregroundStyle(tint).symbolSize(point.id == selected.id ? 75 : 22)
                            }
                        }
                        if let goal, domain.contains(goal) {
                            RuleMark(y: .value("目标", goal)).foregroundStyle(.secondary.opacity(0.45)).lineStyle(StrokeStyle(dash: [4, 4]))
                        }
                        RuleMark(x: .value("所选日期", selected.date)).foregroundStyle(tint.opacity(0.35)).lineStyle(StrokeStyle(dash: [3, 3]))
                    }
                    .chartXScale(domain: dates)
                    .chartYScale(domain: domain)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day()) } }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                    .chartXSelection(value: $selection)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onTapGesture { location in
                                    guard let frame = proxy.plotFrame else { return }
                                    let x = location.x - geometry[frame].origin.x
                                    selection = proxy.value(atX: x, as: Date.self)
                                }
                        }
                    }
                    .frame(height: 210)
                    .accessibilityLabel("\(title)，横轴日期，纵轴\(unit)。点击查看数据，或进入数据详情。")
                    if selection != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selected.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.medium))
                            if !selected.note.isEmpty { Text(selected.note).font(.subheadline).foregroundStyle(.secondary) }
                            if let goal { Text("目标 \(goal.formatted()) \(unit)").font(.caption).foregroundStyle(.secondary) }
                            Button("收起详情") { selection = nil }.font(.caption)
                        }
                    }
                    HStack {
                        Text(bars ? "每日合计" : (smoothed ? "每日中位数 · 指数平滑" : "每日中位数"))
                        Spacer()
                        if isDetail {
                            Button("查看数据") { selection = points.last?.date }
                        } else {
                            NavigationLink("查看详情") { detail }
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("暂无数据", systemImage: "chart.xyaxis.line", description: Text("记录后即可查看数值和变化。"))
                }
            }
        }
        .onChange(of: points.map(\.id)) { _, _ in selection = nil }
    }
    private var detail: some View {
        TrendDetailView(title: title, unit: unit, tint: tint, points: points, goal: goal, bars: bars, samples: samples, cutoff: cutoff)
    }
    private func move(_ step: Int) {
        guard let selected, let index = points.firstIndex(where: { $0.id == selected.id }) else { return }
        selection = points[min(max(index + step, 0), points.count - 1)].date
    }
}

private struct TrendDetailView: View {
    let title: String
    let unit: String
    let tint: Color
    let points: [TrendPoint]
    let goal: Double?
    let bars: Bool
    let samples: [BodyTrend.Sample]?
    let cutoff: Date?
    @State private var period: BodyTrend.Period = .all
    @State private var smooth = false

    private var matching: [BodyTrend.Sample] {
        (samples ?? []).filter { period.includes($0.date) }
    }
    private var visibleSamples: [BodyTrend.Sample] {
        matching.filter { cutoff == nil || $0.date >= cutoff! }.sorted { $0.date > $1.date }
    }
    private var displayed: [TrendPoint] {
        guard samples != nil else { return points }
        return BodyTrend.series(matching).filter { cutoff == nil || $0.date >= cutoff! }.map {
            TrendPoint(id: $0.date.description, date: $0.date, value: smooth ? $0.trend : $0.value,
                       note: "中位数 \($0.value.formatted()) \(unit) · \($0.count) 次测量")
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if samples != nil {
                    GlassCard(tint: tint) {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("测量时段", selection: $period) {
                                ForEach(BodyTrend.Period.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                            Text("早上 05–12 时 · 下午 12–18 时 · 晚上 18–24 时 · 凌晨 00–05 时")
                                .font(.caption).foregroundStyle(.secondary)
                            Toggle("平滑趋势", isOn: $smooth)
                            Text("默认展示每天的中位数，减少单次极端值影响。筛选时段后重新计算；缺测不补零。平滑趋势仅供观察长期变化。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                InspectableTrendCard(title: smooth ? "平滑趋势" : title, unit: unit, tint: tint, points: displayed, goal: goal, bars: bars, isDetail: true, smoothed: smooth)
                GlassCard(tint: tint) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(samples == nil ? "每日明细" : "原始测量").font(.headline)
                        if samples != nil {
                            if visibleSamples.isEmpty { Text("此时段暂无测量").foregroundStyle(.secondary) }
                            ForEach(Array(visibleSamples.enumerated()), id: \.offset) { _, sample in
                                HStack {
                                    Text(sample.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                                    Spacer()
                                    Text("\(sample.value.formatted()) \(unit)").monospacedDigit()
                                }
                                Divider()
                            }
                        } else {
                            if points.isEmpty { Text("当前范围暂无记录").foregroundStyle(.secondary) }
                            ForEach(points.reversed()) { point in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                        Spacer()
                                        Text("\(point.value.formatted(.number.precision(.fractionLength(0)))) \(unit)").monospacedDigit()
                                    }
                                    Text(point.note).font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
                    }
                }
            }.padding(16)
        }.background(AppBackground()).navigationTitle(title)
    }
}
