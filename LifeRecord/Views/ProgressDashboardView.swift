import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]

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

    private var filteredMetrics: [BodyMetric] {
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return bodyMetrics }
        return bodyMetrics.filter { $0.date >= cutoff }
    }

    private var dailyCalories: [(date: Date, value: Double)] {
        let grouped = Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.calories }) }.sorted { $0.date < $1.date }.suffix(14)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 18) {
                        Picker("时间范围", selection: $range) {
                            ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        summaryGrid
                        weightChart
                        calorieChart
                        aiReportCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("身体趋势")
            .alert("生成失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryMetric(title: "最近体重", value: latestWeight, detail: weightChangeText, symbol: "scalemass", tint: AppTheme.protein)
            SummaryMetric(title: "目标体重", value: "\(settings.targetWeight.formatted(.number.precision(.fractionLength(1)))) kg", detail: distanceToGoal, symbol: "flag.checkered", tint: AppTheme.accent)
            SummaryMetric(title: "日均热量", value: averageCalories, detail: "最近 14 天记录", symbol: "flame", tint: .orange)
            SummaryMetric(title: "记录连续性", value: consistencyText, detail: "最近 7 天", symbol: "calendar.badge.checkmark", tint: AppTheme.fat)
        }
    }

    private var latestWeight: String {
        bodyMetrics.last.map { "\($0.weight.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "—"
    }

    private var weightChangeText: String {
        guard filteredMetrics.count >= 2, let first = filteredMetrics.first, let last = filteredMetrics.last else { return "至少记录两次" }
        let delta = last.weight - first.weight
        return "区间 \(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private var distanceToGoal: String {
        guard let current = bodyMetrics.last?.weight else { return "等待首次记录" }
        let delta = settings.targetWeight - current
        if abs(delta) < 0.2 { return "已接近目标" }
        return "还差 \(abs(delta).formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private var averageCalories: String {
        guard !dailyCalories.isEmpty else { return "—" }
        return "\((dailyCalories.reduce(0) { $0 + $1.value } / Double(dailyCalories.count)).formatted(.number.precision(.fractionLength(0)))) kcal"
    }

    private var consistencyText: String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let days = Set(meals.filter { $0.date >= cutoff }.map { Calendar.current.startOfDay(for: $0.date) })
        return "\(days.count) / 7 天"
    }

    private var weightChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("体重趋势").font(.headline)
                if filteredMetrics.isEmpty {
                    ContentUnavailableView("暂无体重数据", systemImage: "chart.line.uptrend.xyaxis", description: Text("记录两次以上后即可看到变化趋势。"))
                        .frame(height: 190)
                } else {
                    Chart(filteredMetrics) { metric in
                        LineMark(x: .value("日期", metric.date), y: .value("体重", metric.weight))
                            .foregroundStyle(AppTheme.protein)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("日期", metric.date), y: .value("体重", metric.weight))
                            .foregroundStyle(LinearGradient(colors: [AppTheme.protein.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("日期", metric.date), y: .value("体重", metric.weight))
                            .foregroundStyle(AppTheme.protein)
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 220)
                    .accessibilityLabel("体重趋势图")
                }
            }
        }
    }

    private var calorieChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("热量记录").font(.headline)
                if dailyCalories.isEmpty {
                    ContentUnavailableView("暂无饮食数据", systemImage: "fork.knife", description: Text("记录餐食后会显示每日总热量。"))
                        .frame(height: 170)
                } else {
                    Chart(dailyCalories, id: \.date) { item in
                        BarMark(x: .value("日期", item.date, unit: .day), y: .value("热量", item.value))
                            .foregroundStyle(item.value > settings.calorieGoal ? Color.orange : AppTheme.accent)
                            .cornerRadius(4)
                        RuleMark(y: .value("目标", settings.calorieGoal))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 200)
                    .accessibilityLabel("每日热量图")
                }
            }
        }
    }

    private var aiReportCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("AI 周报", systemImage: "sparkles").font(.headline).foregroundStyle(AppTheme.accent)
                Text(report.isEmpty ? "结合近期体重与饮食记录，生成一份短小、可执行的复盘。" : report)
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
                .disabled(isGenerating || (bodyMetrics.isEmpty && meals.isEmpty))
            }
        }
    }

    @MainActor
    private func generateReport() async {
        isGenerating = true
        defer { isGenerating = false }
        let recentWeights = bodyMetrics.suffix(8).map { "\($0.date.formatted(date: .numeric, time: .omitted)): \($0.weight)kg" }.joined(separator: ", ")
        let calories = dailyCalories.map { "\($0.date.formatted(date: .numeric, time: .omitted)): \(Int($0.value))kcal" }.joined(separator: ", ")
        let context = "目标体重 \(settings.targetWeight)kg，热量目标 \(settings.calorieGoal)kcal。体重：\(recentWeights)。每日热量：\(calories)。"
        do {
            report = try await AIClient(settings: settings).coachText(
                system: "你是克制、循证的健身记录教练。根据有限数据指出趋势和不确定性，用中文给出 3 条可执行建议，不做医疗诊断，不鼓励极端热量缺口。",
                messages: [AIChatMessage(role: "user", content: context)]
            )
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
