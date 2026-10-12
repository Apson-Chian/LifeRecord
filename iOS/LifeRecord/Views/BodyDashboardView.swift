import SwiftUI
import SwiftData
import Charts

/// 「身体」总览：趋势体重、今日中位数、近 7/30 天变化、增重速度，
/// 每日中位数 vs 趋势体重曲线，以及身体组成（体脂率、脂肪量、瘦体重）。
struct BodyDashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]

    private var calendar: Calendar { .current }
    private var todayStart: Date { calendar.startOfDay(for: .now) }

    // MARK: - 数据准备

    /// 当天所有测量，按时间升序。
    private var todayMetrics: [BodyMetric] {
        bodyMetrics.filter { calendar.isDate($0.date, inSameDayAs: todayStart) }
            .sorted { $0.date < $1.date }
    }

    /// 今日中位数：当天最早的一次测量（通常是晨起空腹值）。
    private var todayBaseline: BodyMetric? { todayMetrics.first }

    private var trendSeries: [BodyTrendPoint] {
        BodyTrend.series(bodyMetrics.map { .init(date: $0.date, value: $0.weight) })
            .map { BodyTrendPoint(date: $0.date, raw: $0.value, trend: $0.trend) }
    }

    private var currentTrend: BodyTrendPoint? { trendSeries.last }

    // MARK: - 指标

    private var trendWeightText: String {
        currentTrend?.trend.formatted(.number.precision(.fractionLength(1))) ?? "—"
    }

    private var baselineWeightText: String {
        trendSeries.first(where: { calendar.isDate($0.date, inSameDayAs: todayStart) })?.raw.formatted(.number.precision(.fractionLength(1))) ?? "—"
    }

    private var todayCountText: String {
        todayMetrics.isEmpty ? "—" : "\(todayMetrics.count) 次"
    }

    private func trendWeight(aroundDaysAgo days: Int) -> Double? {
        guard !trendSeries.isEmpty,
              let cutoff = calendar.date(byAdding: .day, value: -days, to: todayStart) else { return nil }
        return trendSeries.last(where: { $0.date <= cutoff })?.trend
    }

    private func trendChange(days: Int) -> Double? {
        guard let current = currentTrend?.trend,
              let anchor = trendWeight(aroundDaysAgo: days) else { return nil }
        return current - anchor
    }

    /// 近 30 天趋势体重的线性回归斜率，换算成 kg/周。
    private var weeklyGainRate: Double? {
        guard trendSeries.count >= 3 else { return nil }
        let cutoff = calendar.date(byAdding: .day, value: -30, to: todayStart) ?? .distantPast
        let recent = trendSeries.filter { $0.date >= cutoff }
        let sample = recent.count >= 3 ? recent : trendSeries
        guard sample.count >= 3 else { return nil }

        let n = Double(sample.count)
        let meanX = sample.reduce(0.0) { $0 + $1.date.timeIntervalSinceReferenceDate } / n
        let meanY = sample.reduce(0.0) { $0 + $1.trend } / n
        var numerator = 0.0
        var denominator = 0.0
        for point in sample {
            let dx = point.date.timeIntervalSinceReferenceDate - meanX
            numerator += dx * (point.trend - meanY)
            denominator += dx * dx
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator * 86_400 * 7
    }

    private var rateTitle: String {
        switch settings.fitnessGoal {
        case .gainMuscle: "增重速度"
        case .loseFat: "减重速度"
        case .maintain: "体重变化"
        }
    }

    private var gainRateText: String {
        guard let rate = weeklyGainRate else { return "—" }
        return "\(rate >= 0 ? "+" : "")\(rate.formatted(.number.precision(.fractionLength(2)))) kg/周"
    }

    private var gainRateBadge: (symbol: String, color: Color, label: String) {
        guard let rate = weeklyGainRate else { return ("ellipsis.circle", Color.secondary, "记录不足") }
        let target = settings.weeklyWeightTarget
        switch settings.fitnessGoal {
        case .gainMuscle:
            if rate >= 0 && rate <= target + 0.1 {
                return ("checkmark.circle.fill", AppTheme.recorded, "符合目标节奏")
            }
            if rate > target + 0.1 {
                return ("exclamationmark.triangle.fill", .orange, "增得偏快")
            }
            return ("arrow.triangle.swap", .red, "方向相反 · 在掉重")
        case .loseFat:
            if rate <= 0 && rate >= target - 0.1 {
                return ("checkmark.circle.fill", AppTheme.recorded, "符合目标节奏")
            }
            if rate < target - 0.1 {
                return ("exclamationmark.triangle.fill", .orange, "减得偏快")
            }
            return ("arrow.triangle.swap", .red, "方向相反 · 在增重")
        case .maintain:
            if abs(rate) <= 0.12 {
                return ("checkmark.circle.fill", AppTheme.recorded, "维持平稳")
            }
            return ("exclamationmark.triangle.fill", .orange, "波动偏大")
        }
    }

    // MARK: - 身体组成

    private var compositionMetric: BodyMetric? {
        if let baseline = todayMetrics.first(where: { $0.bodyFat != nil }) { return baseline }
        return bodyMetrics.reversed().first(where: { $0.bodyFat != nil })
    }

    private var bodyFatText: String {
        compositionMetric?.bodyFat.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—"
    }

    private var fatMassText: String {
        guard let metric = compositionMetric, let bodyFat = metric.bodyFat else { return "—" }
        return (metric.weight * bodyFat / 100).formatted(.number.precision(.fractionLength(1)))
    }

    private var leanMassText: String {
        guard let metric = compositionMetric, let bodyFat = metric.bodyFat else { return "—" }
        return (metric.weight - metric.weight * bodyFat / 100).formatted(.number.precision(.fractionLength(1)))
    }

    private var compositionBasisText: String {
        guard let metric = compositionMetric else { return "暂无体脂数据" }
        if calendar.isDate(metric.date, inSameDayAs: todayStart) {
            return "依据今日 \(metric.date.formatted(.dateTime.hour().minute())) 的测量计算"
        }
        return "依据 \(metric.date.formatted(.dateTime.month().day().hour().minute())) 的最近体脂测量计算"
    }

    // MARK: - 图表

    private var chartDomain: ClosedRange<Double> {
        let values = trendSeries.flatMap { [$0.raw, $0.trend] }
        guard let low = values.min(), let high = values.max() else { return 40...100 }
        let padding = max((high - low) * 0.25, 1.0)
        return max(0, low - padding)...(high + padding)
    }

    // MARK: - 视图

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                LazyVStack(spacing: 16) {
                    weightSummaryCard
                    weightTrendChartCard
                    bodyCompositionCard
                    todayMeasurementsCard
                }
                .padding(16)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("身体")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weightSummaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(trendWeightText)
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("kg").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text("趋势体重").font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    KeyValueStat(title: "今日中位数", value: baselineWeightText, unit: "kg", symbol: "scalemass", tint: AppTheme.protein)
                    KeyValueStat(title: "今日测量", value: todayCountText, unit: "", symbol: "clock", tint: AppTheme.accent)
                }

                Divider()

                changeRow("近 7 天", trendChange(days: 7))
                changeRow("近 30 天", trendChange(days: 30))

                HStack(alignment: .center) {
                    Text(rateTitle).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(gainRateText).font(.subheadline.weight(.semibold)).monospacedDigit()
                    Label(gainRateBadge.label, systemImage: gainRateBadge.symbol)
                        .font(.caption)
                        .foregroundStyle(gainRateBadge.color)
                }
            }
        }
    }

    private func changeRow(_ title: String, _ value: Double?) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(signed(value, unit: "kg"))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(value == nil ? .tertiary : .primary)
        }
    }

    private func signed(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        return "\(value >= 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }

    private var weightTrendChartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("体重走势").font(.headline)
                    Spacer()
                    LegendItem(title: "每日中位数", dashed: true, color: Color.secondary)
                    LegendItem(title: "趋势体重", dashed: false, color: AppTheme.accent)
                }

                if trendSeries.isEmpty {
                    ContentUnavailableView("暂无体重记录", systemImage: "scalemass", description: Text("记录后即可查看原始与趋势曲线。"))
                } else {
                    Chart {
                        ForEach(trendSeries) { point in
                            LineMark(x: .value("日期", point.date), y: .value("每日中位数", point.raw), series: .value("序列", "每日中位数"))
                                .foregroundStyle(Color.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .interpolationMethod(.linear)
                            PointMark(x: .value("日期", point.date), y: .value("每日中位数", point.raw))
                                .foregroundStyle(Color.secondary)
                                .symbolSize(18)
                        }
                        ForEach(trendSeries) { point in
                            LineMark(x: .value("日期", point.date), y: .value("趋势体重", point.trend), series: .value("序列", "趋势体重"))
                                .foregroundStyle(AppTheme.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.linear)
                        }
                    }
                    .chartYScale(domain: chartDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                    }
                    .frame(height: 220)
                    .accessibilityLabel("体重走势，虚线为每日中位数，实线为趋势体重")

                    Text("每天所有测量先取中位数，再做指数平滑（每日权重 10%，按间隔天数调整）。缺测不补零。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var bodyCompositionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("身体组成").font(.headline)
                HStack(spacing: 10) {
                    CompositionStat(title: "体脂率", value: bodyFatText, symbol: AppSymbol.bodyFat, tint: AppTheme.fat)
                    CompositionStat(title: "脂肪量", value: fatMassText, unit: "kg", symbol: AppSymbol.fat, tint: AppTheme.fat)
                    CompositionStat(title: "瘦体重", value: leanMassText, unit: "kg", symbol: AppSymbol.weight, tint: AppTheme.protein)
                }
                Text(compositionBasisText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var todayMeasurementsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("今日测量").font(.headline)
                if todayMetrics.isEmpty {
                    Text("今天还没有身体测量。").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(todayMetrics.reversed().enumerated()), id: \.element.id) { index, metric in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Text(metric.date.formatted(.dateTime.hour().minute()))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(metric.weight.formatted(.number.precision(.fractionLength(1)))) kg")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            Text(metric.bodyFat.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if metric.id == todayBaseline?.id {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                    Text("最早记录")
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.carbs)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 辅助类型

private struct BodyTrendPoint: Identifiable {
    let date: Date
    let raw: Double
    var trend: Double

    var id: Date { date }
}

private struct KeyValueStat: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            IconBadge(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.headline.monospacedDigit())
                    if !unit.isEmpty {
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct CompositionStat: View {
    let title: String
    let value: String
    var unit: String = ""
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(height: 22)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LegendItem: View {
    let title: String
    let dashed: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 4, height: 2)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 18, height: 3)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
