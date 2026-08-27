import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WaterEntry.date) private var waterEntries: [WaterEntry]

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
        return Calendar.current.date(byAdding: .day, value: -days, to: .now)
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

    /// 同一天只展示最后一次测量，避免晨重、午重在图上挤成一条竖线。
    private var dailyMetrics: [BodyMetric] {
        Dictionary(grouping: filteredMetrics) { Calendar.current.startOfDay(for: $0.date) }
            .compactMap { $0.value.max(by: { $0.date < $1.date }) }
            .sorted { $0.date < $1.date }
    }

    private var bodyFatPoints: [(date: Date, value: Double)] {
        dailyMetrics.compactMap { metric in
            metric.bodyFat.map { (metric.date, $0) }
        }
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
                        summaryStrip
                        weightChart
                        bodyCompositionCard
                        calorieChart
                        waterChart
                        recordHeatmap
                        aiReportCard
                    }
                    .padding(16)
                    .padding(.bottom, 26)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("身体趋势")
            .alert("生成失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private var rangeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("数据范围", systemImage: "calendar")
                        .font(.headline)
                    Spacer()
                    if bodyMetrics.contains(where: \.isDemo) || meals.contains(where: \.isDemo) {
                        Text("示例")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                Picker("时间范围", selection: $range) {
                    ForEach(TrendRange.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Text("当前范围包含 \(dailyNutrition.count) 天饮食记录、\(dailyMetrics.count) 天身体测量、\(dailyWater.count) 天饮水记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                SummaryMetric(title: "记录连续性", value: consistencyText, detail: "最近 7 天", symbol: "calendar.badge.checkmark", tint: AppTheme.carbs)
                SummaryMetric(title: "距目标", value: distanceToGoal, detail: "目标 \(settings.targetWeight.formatted(.number.precision(.fractionLength(1)))) kg", symbol: "flag.checkered", tint: AppTheme.accent)
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private var weightChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("体重趋势").font(.headline)
                    Spacer()
                    Label(weightChangeText, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                if dailyMetrics.isEmpty {
                    ContentUnavailableView("暂无体重数据", systemImage: "chart.line.uptrend.xyaxis", description: Text("记录两次以上后即可看到变化趋势。"))
                        .frame(height: 190)
                } else {
                    Chart(dailyMetrics) { metric in
                        AreaMark(x: .value("日期", metric.date), y: .value("体重", metric.weight))
                            .foregroundStyle(AppTheme.accent.opacity(0.15))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("日期", metric.date), y: .value("体重", metric.weight))
                            .foregroundStyle(AppTheme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("日期", metric.date), y: .value("体重", metric.weight))
                            .foregroundStyle(AppTheme.accent)
                            .symbolSize(16)
                        RuleMark(y: .value("目标", settings.targetWeight))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    }
                    .chartYScale(domain: weightDomain)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 210)
                    .accessibilityLabel("体重趋势图")
                }
            }
        }
    }

    private var bodyCompositionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("体脂趋势").font(.headline)
                if bodyFatPoints.isEmpty {
                    ContentUnavailableView("暂无体脂数据", systemImage: "figure.arms.open", description: Text("记录体脂率后会在这里显示变化。"))
                        .frame(height: 160)
                } else {
                    Chart(bodyFatPoints, id: \.date) { point in
                        AreaMark(x: .value("日期", point.date), y: .value("体脂率", point.value))
                            .foregroundStyle(AppTheme.fat.opacity(0.12))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("日期", point.date), y: .value("体脂率", point.value))
                            .foregroundStyle(AppTheme.fat)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: bodyFatDomain)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 175)
                }
            }
        }
    }

    private var calorieChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("每日热量").font(.headline)
                    Spacer()
                    Text("目标 \(Int(settings.calorieGoal)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if dailyNutrition.isEmpty {
                    ContentUnavailableView("暂无饮食数据", systemImage: "fork.knife", description: Text("记录餐食后会显示每日总热量。"))
                        .frame(height: 170)
                } else {
                    Chart(dailyNutrition, id: \.date) { item in
                        BarMark(x: .value("日期", dayLabel(item.date)), y: .value("热量", item.calories))
                            .foregroundStyle(item.calories > settings.calorieGoal ? Color.orange : AppTheme.accent)
                            .cornerRadius(4)
                        RuleMark(y: .value("目标", settings.calorieGoal))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 185)
                    .accessibilityLabel("每日热量图")
                }
            }
        }
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
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("每日饮水").font(.headline)
                    Spacer()
                    Text("目标 \(settings.waterGoal.formatted(.number.precision(.fractionLength(0)))) ml")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if dailyWater.isEmpty {
                    ContentUnavailableView("暂无饮水数据", systemImage: "drop", description: Text("记录饮水后显示每日总量。"))
                        .frame(height: 150)
                } else {
                    Chart(dailyWater, id: \.date) { item in
                        BarMark(x: .value("日期", dayLabel(item.date)), y: .value("饮水", item.value))
                            .foregroundStyle(LinearGradient(colors: [AppTheme.water.opacity(0.75), AppTheme.water], startPoint: .bottom, endPoint: .top))
                            .cornerRadius(4)
                        RuleMark(y: .value("目标", settings.waterGoal))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 155)
                }
            }
        }
    }

    private var recordHeatmap: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("记录连续性").font(.headline)
                Text("按饮食、体重和饮水综合计算，颜色越深代表当天记录越完整。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                    ForEach(recordDays, id: \.date) { item in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(recordColor(item.score))
                            .frame(height: 24)
                            .overlay {
                                if item.score == 0 {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                }
                            }
                            .accessibilityLabel("\(item.date.formatted(date: .abbreviated, time: .omitted))，完整度 \(Int(item.score * 100))%")
                    }
                }
            }
        }
    }

    private var aiReportCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("AI 周报", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                Text(report.isEmpty ? "结合近期体重、身体成分、饮食、饮水记录，生成一份短小、可执行的复盘。" : report)
                    .font(.subheadline)
                    .foregroundStyle(report.isEmpty ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await generateReport() }
                } label: {
                    HStack {
                        Text(report.isEmpty ? "生成本周分析" : "重新生成")
                        Spacer()
                        if isGenerating { ProgressView() } else { Image(systemName: "arrow.right") }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || (bodyMetrics.isEmpty && meals.isEmpty && waterEntries.isEmpty))
            }
        }
    }

    private var latestWeight: String {
        bodyMetrics.last.map { $0.weight.formatted(.number.precision(.fractionLength(1))) + " kg" } ?? "—"
    }

    private var weightChangeText: String {
        guard dailyMetrics.count >= 2, let first = dailyMetrics.first, let last = dailyMetrics.last else { return "至少记录两次" }
        let delta = last.weight - first.weight
        return "区间 \(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private var latestBodyFat: String {
        bodyMetrics.reversed().compactMap(\.bodyFat).first.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—"
    }

    private var bodyFatChangeText: String {
        let values = bodyFatPoints.map(\.value)
        guard values.count >= 2, let first = values.first, let last = values.last else { return "至少记录两次" }
        let delta = last - first
        return "区间 \(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1))))%"
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
        let values = dailyMetrics.map(\.weight) + [settings.targetWeight]
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
        let days = Set(meals.filter { $0.date >= cutoff }.map { Calendar.current.startOfDay(for: $0.date) })
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
        let recentWeights = bodyMetrics.suffix(10).map { "\($0.date.formatted(date: .numeric, time: .omitted)): \($0.weight)kg" }.joined(separator: ", ")
        let calories = dailyNutrition.map { "\($0.date.formatted(date: .numeric, time: .omitted)): \(Int($0.calories))kcal / P\(Int($0.protein))g" }.joined(separator: ", ")
        let water = dailyWater.map { "\($0.date.formatted(date: .numeric, time: .omitted)): \(Int($0.value))ml" }.joined(separator: ", ")
        let context = "目标体重 \(settings.targetWeight)kg，热量目标 \(settings.calorieGoal)kcal，饮水目标 \(settings.waterGoal)ml。体重：\(recentWeights)。每日营养：\(calories)。每日饮水：\(water)。"
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
