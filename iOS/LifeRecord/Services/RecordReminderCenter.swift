import Foundation
import UserNotifications
import Combine

@MainActor
final class RecordReminderCenter: ObservableObject {
    static let shared = RecordReminderCenter()
    @Published private(set) var status = ""
    @Published private(set) var denied = false
    private let center = UNUserNotificationCenter.current()
    private var nextPlan: [ReminderPlan.Item]?
    private var updating = false

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            denied = !granted
            if !granted { status = "通知权限未开启，请在系统设置中允许通知。" }
            return granted
        } catch { status = error.localizedDescription; return false }
    }

    func refresh(preferences: ReminderPreferences, records: ReminderPlan.Records) {
        nextPlan = ReminderPlan.items(preferences: preferences, records: records, now: .now)
        guard !updating else { return }
        updating = true
        Task {
            // Serialize asynchronous scheduling so an old save cannot overwrite a newer plan.
            while let plan = nextPlan {
                nextPlan = nil
                let pending = await center.pendingNotificationRequests()
                center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlan.prefix) })
                let authorization = await center.notificationSettings()
                denied = authorization.authorizationStatus == .denied
                guard authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional else {
                    status = denied ? "通知权限未开启，请在系统设置中允许通知。" : "开启提醒时将请求通知权限。"
                    continue
                }
                do {
                    for item in plan {
                        // A newer edit supersedes the remainder of this plan.
                        if nextPlan != nil { break }
                        let content = UNMutableNotificationContent()
                        content.title = "今天还有记录没补齐"
                        content.body = "\(item.missing.joined(separator: "、"))还没有记录，方便时补记一下。"
                        content.sound = .default
                        content.threadIdentifier = "record-reminders"
                        content.userInfo = ["recordReminder": true]
                        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                        try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                    }
                    status = plan.isEmpty ? "当前没有待提醒事项。" : "提醒已安排，记录后会自动更新。"
                } catch { status = "提醒安排失败：\(error.localizedDescription)" }
            }
            updating = false
        }
    }
}
