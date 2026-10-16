import SwiftUI

struct GoalFeedbackCard: View {
    let summary: GoalFeedback.Summary
    let goals: GoalFeedback.Goals
    @EnvironmentObject private var router: AppRouter
    @State private var showsDetails = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    IconBadge(symbol: "target", tint: AppTheme.accent)
                    Text("目标反馈").font(.headline)
                    Spacer()
                    Text("\(summary.start.formatted(.dateTime.month().day()))—\(summary.end.formatted(.dateTime.month().day()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(summary.trendWeight.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                    Text("kg").foregroundStyle(.secondary)
                    Spacer()
                    Text("趋势体重").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(summary.headline).font(.subheadline.weight(.medium))
                if let period = summary.periodProgress {
                    VStack(spacing: 8) {
                        HStack {
                            Text("阶段变化 \(signed(period.change)) kg")
                            Spacer()
                            Text("参考 \(signed(period.targetChange)) kg").foregroundStyle(.secondary)
                        }.font(.caption).monospacedDigit()
                        ProgressView(value: period.fraction).tint(AppTheme.accent)
                            .accessibilityLabel("所选历史时段的体重变化相对于阶段目标")
                            .accessibilityValue("\(Int(period.fraction * 100))%")
                    }
                }
                HStack(spacing: 10) {
                    metric("饮食记录", value: "\(summary.mealDays)", unit: "天")
                    metric("身体测量", value: "\(summary.measurementDays)", unit: "天")
                    metric("完成训练", value: "\(summary.completedWorkouts)", unit: "次")
                }
                DisclosureGroup("记录与解读", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let date = summary.latestMeasurement { row("最近测量", date.formatted(.dateTime.month().day())) }
                        if let distance = summary.distance { row("距目标体重", "\(distance.formatted(.number.precision(.fractionLength(1)))) kg") }
                        if let period = summary.periodProgress {
                            Text("比较 \(period.baselineDate.formatted(.dateTime.month().day())) 至最近测量的趋势体重；参考值按设定的每周目标和实际测量跨度换算。")
                        }
                        if let change = summary.weeklyChange { row("平均每周变化", "\(signed(change)) kg") }
                        row("热量在目标 ±10% 内", goals.calories.isFinite && goals.calories > 0 ? "\(summary.calorieGoalDays) / \(summary.mealDays) 个记录日" : "请核对目标")
                        row("蛋白质达到目标", goals.protein.isFinite && goals.protein > 0 ? "\(summary.proteinGoalDays) / \(summary.mealDays) 个记录日" : "请核对目标")
                        if let calories = summary.averageCalories, let protein = summary.averageProtein {
                            row("记录日均热量", "\(calories.formatted(.number.precision(.fractionLength(0)))) kcal")
                            row("记录日均蛋白质", "\(protein.formatted(.number.precision(.fractionLength(0)))) g")
                        }
                        Text("仅统计真实有效记录，缺失日期不按零计算。体重变化不等同于增肌或减脂成果。")
                        Divider()
                        ForEach(summary.actions, id: \.self) { action in Text(action) }
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                }
                .font(.subheadline).tint(AppTheme.accent)
                Button {
                    router.openCoach(draft: "请依据以下截至今天的历史记录，帮我回顾这段时间的身体、饮食和训练变化。先说明记录不足，再给出简短解读，不把体重变化当作脂肪或肌肉变化，不自动调整目标。\n\(summary.context)")
                } label: { Label("和教练复盘", systemImage: AppSymbol.coach).frame(maxWidth: .infinity) }
                .buttonStyle(AppButtonStyle(prominent: false))
            }
        }
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(AppTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func signed(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }
}
