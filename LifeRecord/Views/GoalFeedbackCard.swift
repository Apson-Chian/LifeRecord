import SwiftUI

struct GoalFeedbackCard: View {
    let summary: GoalFeedback.Summary
    let goals: GoalFeedback.Goals
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    IconBadge(symbol: "target", tint: AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("目标反馈").font(.headline)
                        Text("\(summary.start.formatted(.dateTime.month().day())) — \(summary.end.formatted(.dateTime.month().day()))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(summary.headline).font(.title3.weight(.semibold))
                if let weight = summary.trendWeight, let date = summary.latestMeasurement {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(weight.formatted(.number.precision(.fractionLength(1)))) kg").font(.title2.weight(.semibold)).monospacedDigit()
                        Spacer()
                        Text(summary.distance == nil ? "请核对目标" : "目标 \(goals.targetWeight.formatted(.number.precision(.fractionLength(1)))) kg").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("最近趋势体重 · \(date.formatted(.dateTime.month().day())) · 由真实测量每日中位数平滑计算")
                        .font(.caption).foregroundStyle(.secondary)
                    if let progress = summary.progress {
                        ProgressView(value: progress).tint(AppTheme.accent)
                            .accessibilityLabel("从起始体重到目标的进度")
                            .accessibilityValue("\(Int(progress * 100))%")
                        HStack {
                            Text("完成 \(Int(progress * 100))%")
                            Spacer()
                            if let distance = summary.distance { Text("距目标 \(distance.formatted(.number.precision(.fractionLength(1)))) kg") }
                        }.font(.caption).foregroundStyle(.secondary)
                        Text("以设置中的起始体重为基准；更改目标后重新计算，体重进度不等同于增肌或减脂成果。")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if let distance = summary.distance {
                        Text("与目标相差 \(distance.formatted(.number.precision(.fractionLength(1)))) kg")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let change = summary.weeklyChange {
                        Text("区间趋势折算 \(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2)))) kg/周 · 设定 \(goals.weeklyWeightChange.formatted(.number.precision(.fractionLength(2)))) kg/周")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 10) {
                    row("饮食记录覆盖", "\(summary.mealDays) / \(summary.days) 天")
                    row("热量在设定目标 ±10% 内", goals.calories.isFinite && goals.calories > 0 ? "\(summary.calorieGoalDays) / \(summary.mealDays) 个记录日" : "请核对目标")
                    row("蛋白质达到设定目标", goals.protein.isFinite && goals.protein > 0 ? "\(summary.proteinGoalDays) / \(summary.mealDays) 个记录日" : "请核对目标")
                    if let calories = summary.averageCalories, let protein = summary.averageProtein {
                        row("已记录日均热量 / 蛋白质", "\(calories.formatted(.number.precision(.fractionLength(0)))) kcal / \(protein.formatted(.number.precision(.fractionLength(0)))) g")
                    }
                    row("身体测量 / 完成训练", "\(summary.measurementDays) 天 / \(summary.completedWorkouts) 次")
                }
                Text("只统计真实、非未来且数值有效的记录；有记录不代表记全。缺失日期不按零计算，今日结果仍可能变化。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("下一步").font(.subheadline.weight(.semibold))
                ForEach(Array(summary.actions.enumerated()), id: \.offset) { index, action in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                            .frame(width: 22, height: 22).background(AppTheme.accent.opacity(0.1), in: Circle()).accessibilityHidden(true)
                        Text(action).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    router.openCoach(draft: "请依据我的设定目标与以下本机统计，帮我复盘执行情况并给出下一周 2–3 条具体行动。先指出记录不足，不把体重变化直接当成脂肪或肌肉变化，也不要自动改动目标。\n\(summary.context)")
                } label: { Label("和教练制定下一周计划", systemImage: AppSymbol.coach).frame(maxWidth: .infinity) }
                .buttonStyle(AppButtonStyle(prominent: false))
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.caption)
    }
}
