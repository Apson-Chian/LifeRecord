import SwiftUI

struct GoalHistoryView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        List {
            Section {
                Text("修改目标从保存当天起生效，更早日期使用原目标。此前未记录的目标变更无法自动还原。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if settings.goalHistory.isEmpty {
                Section("当前目标") {
                    goalRows(settings.currentGoals)
                    Text("下次修改时会先保存当前目标作为历史基准。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(settings.goalHistory.reversed()) { version in
                    Section(version.effectiveDate==GoalHistory.baselineDay ? "最初保留的目标" : "\(version.effectiveDate) 起生效") {
                        goalRows(version.values)
                    }
                }
            }
        }
        .navigationTitle("目标历史").navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func goalRows(_ goals:GoalValues)->some View {
        LabeledContent("目标",value:goals.fitnessGoal)
        LabeledContent("目标体重",value:"\(goals.targetWeight.formatted()) kg")
        LabeledContent("热量",value:"\(goals.calorieGoal.formatted()) kcal")
        LabeledContent("蛋白质",value:"\(goals.proteinGoal.formatted()) g")
        LabeledContent("碳水",value:"\(goals.carbsGoal.formatted()) g")
        LabeledContent("脂肪",value:"\(goals.fatGoal.formatted()) g")
    }
}
