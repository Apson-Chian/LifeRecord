import SwiftUI

struct GoalHistoryView: View {
    @Environment(AppSettings.self) private var settings
    @State private var editing:GoalVersion?
    var body: some View {
        List {
            Section {
                Text("新目标从保存当天起生效。记录有误时，可编辑历史目标和生效日期，对应期间的圆环与达标情况会重新计算。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if settings.goalHistory.isEmpty {
                Section("当前目标") {
                    goalRows(settings.currentGoals)
                    Text("下次修改时会先保存当前目标作为历史基准。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(GoalHistory.active(settings.goalHistory).reversed()) { version in
                    Section(version.effectiveDate==GoalHistory.baselineDay ? "最初保留的目标" : "\(version.effectiveDate) 起生效") {
                        goalRows(version.values)
                        Button("编辑此记录") {editing=version}
                            .accessibilityIdentifier("edit-goal-\(version.effectiveDate)")
                    }
                }
            }
        }
        .navigationTitle("目标历史").navigationBarTitleDisplayMode(.inline)
        .sheet(item:$editing) {version in NavigationStack {GoalHistoryEditor(version:version)}}
    }
    @ViewBuilder private func goalRows(_ goals:GoalValues)->some View {
        LabeledContent("目标",value:goals.fitnessGoal)
        LabeledContent("起始体重",value:"\(goals.baselineWeight.formatted()) kg")
        LabeledContent("目标体重",value:"\(goals.targetWeight.formatted()) kg")
        LabeledContent("每周体重变化",value:"\(goals.weeklyWeightTarget.formatted()) kg")
        LabeledContent("热量",value:"\(goals.calorieGoal.formatted()) kcal")
        LabeledContent("蛋白质",value:"\(goals.proteinGoal.formatted()) g")
        LabeledContent("碳水",value:"\(goals.carbsGoal.formatted()) g")
        LabeledContent("脂肪",value:"\(goals.fatGoal.formatted()) g")
    }
}

private struct GoalHistoryEditor:View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let version:GoalVersion
    @State private var values:GoalValues
    @State private var date:Date
    @State private var textValues:[String:String]=[:]
    @State private var error=""
    @State private var discard=false
    init(version:GoalVersion) {
        self.version=version;_values=State(initialValue:version.values)
        _date=State(initialValue:GoalHistory.date(for:version.effectiveDate) ?? .now)
    }
    private var baseline:Bool {version.effectiveDate==GoalHistory.baselineDay}
    private var day:String {baseline ? GoalHistory.baselineDay : GoalHistory.dayKey(date)}
    private var dirty:Bool {(try? parsedValues()) != version.values || day != version.effectiveDate}
    var body:some View {
        Form {
            if !error.isEmpty {Text(error).foregroundStyle(.red)}
            Section {
                if baseline {LabeledContent("生效范围",value:"最初保留的目标")}
                else {DatePicker("生效日期",selection:$date,in:GoalHistory.date(for:"1970-01-02")!...Date.now,displayedComponents:.date)}
                Text("保存会重新计算此记录生效日起、下一条目标生效前的圆环与达标情况。其他日期仍使用各自目标。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("身体与体重") {
                Picker("目标",selection:$values.fitnessGoal) {ForEach(["增肌","减脂","维持"],id:\.self) {Text($0).tag($0)}}
                number("起始体重",value:$values.baselineWeight,unit:"kg")
                number("目标体重",value:$values.targetWeight,unit:"kg")
                number("每周体重变化",value:$values.weeklyWeightTarget,unit:"kg",signed:true)
            }
            Section("每日营养目标") {
                number("热量",value:$values.calorieGoal,unit:"kcal")
                number("蛋白质",value:$values.proteinGoal,unit:"g")
                number("碳水",value:$values.carbsGoal,unit:"g")
                number("脂肪",value:$values.fatGoal,unit:"g")
            }
        }
        .navigationTitle("编辑目标记录").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.cancellationAction) {Button("取消") {if dirty {discard=true} else {dismiss()}}}
            ToolbarItem(placement:.confirmationAction) {Button("保存") {
                do {try settings.reviseGoal(version,values:parsedValues(),day:day);dismiss()} catch {self.error=error.localizedDescription}
            }}
        }
        .keyboardDoneButton()
        .interactiveDismissDisabled(dirty)
        .confirmationDialog("放弃未保存的修改？",isPresented:$discard,titleVisibility:.visible) {Button("放弃修改",role:.destructive) {dismiss()}}
    }
    private func parsedValues() throws -> GoalValues {
        var result=values
        for (title,text) in textValues {
            guard let number=Double(text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:",",with:".")),number.isFinite else {
                throw NSError(domain:"GoalHistory",code:4,userInfo:[NSLocalizedDescriptionKey:"请为\(title)输入有效数字"])
            }
            switch title {
            case "起始体重":result.baselineWeight=number
            case "目标体重":result.targetWeight=number
            case "每周体重变化":result.weeklyWeightTarget=number
            case "热量":result.calorieGoal=number
            case "蛋白质":result.proteinGoal=number
            case "碳水":result.carbsGoal=number
            case "脂肪":result.fatGoal=number
            default:break
            }
        }
        return result
    }
    private func number(_ title:String,value:Binding<Double>,unit:String,signed:Bool=false)->some View {
        HStack {
            Text(title);Spacer()
            TextField(title,text:Binding(get:{textValues[title] ?? value.wrappedValue.formatted(.number.grouping(.never))},set:{textValues[title]=$0})).multilineTextAlignment(.trailing)
                .keyboardType(signed ? .numbersAndPunctuation : .decimalPad).accessibilityIdentifier("history-\(title)")
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
