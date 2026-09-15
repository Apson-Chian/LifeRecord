import SwiftUI

struct ReminderSettingsView: View {
    @AppStorage(ReminderPreferences.key) private var raw = ""
    @State private var preferences = ReminderPreferences()
    @State private var requesting = false
    @ObservedObject private var center = RecordReminderCenter.shared
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: .now) ?? .now }, set: {
            preferences.hour = Calendar.current.component(.hour, from: $0)
            preferences.minute = Calendar.current.component(.minute, from: $0)
        })
    }
    var body: some View {
        Form {
            Section {
                Toggle("开启漏记提醒", isOn: Binding(get: { preferences.enabled }, set: { enabled in
                    if !enabled { preferences.enabled = false; return }
                    requesting = true
                    Task {
                        if await center.requestPermission() { preferences.enabled = true }
                        requesting = false
                    }
                })).disabled(requesting)
                DatePicker("提醒时间", selection: time, displayedComponents: .hourAndMinute)
            } footer: { Text("按本机记录判断，每天最多一条汇总提醒。当日已有该类记录就不提醒，不要求达到营养目标。") }
            Section("提醒哪些记录") {
                Toggle("餐食", isOn: $preferences.meals)
                Toggle("饮水", isOn: $preferences.water)
                Toggle("身体数据", isOn: $preferences.body)
                Toggle("训练", isOn: $preferences.workout)
            }
            if preferences.workout {
                Section {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Toggle(["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][day], isOn: Binding(get: { preferences.workoutDays.contains(day) }, set: { selected in
                            preferences.workoutDays.removeAll { $0 == day }
                            if selected { preferences.workoutDays.append(day) }
                        }))
                    }
                } header: { Text("计划训练日") } footer: { Text("只在勾选的星期提醒。当天开始了训练就视为已有记录。") }
            }
            Section {
                Text(center.status).foregroundStyle(.secondary)
                if center.denied {
                    Button("打开系统通知设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } footer: { Text("每次打开 App 更新未来 30 天提醒。其他设备的记录同步到本机后才能取消提醒；长时间未打开 App 时不会继续安排新提醒。") }
        }
        .navigationTitle("漏记提醒")
        .onAppear { preferences = .decode(raw) }
        .onChange(of: preferences) { _, value in raw = value.encoded }
    }
}
