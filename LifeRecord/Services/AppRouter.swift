import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct CoachRoute: Identifiable, Equatable {
    let id = UUID()
    let conversationID: UUID?
    let draft: String?
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published private(set) var coachRoute: CoachRoute?

    private init() {}

    func openCoach(conversationID: UUID? = nil, draft: String? = nil) {
        coachRoute = CoachRoute(conversationID: conversationID, draft: draft)
    }
}

@MainActor
final class AIAnswerNotificationCenter {
    static let shared = AIAnswerNotificationCenter()

    private let center = UNUserNotificationCenter.current()
    var isCoachVisible = false

    private init() {}

    func requestAuthorizationIfNeeded() {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func notifyAnswerReady(conversationID: UUID) {
        guard !isCoachVisible else { return }

        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "AI 回答已完成"
            content.body = "打开生活记录查看新回复。"
            content.sound = .default
            content.threadIdentifier = "ai-coach"
            content.userInfo = ["conversationID": conversationID.uuidString]

            let request = UNNotificationRequest(
                identifier: "ai-answer-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let value = response.notification.request.content.userInfo["conversationID"] as? String
        if let value, let conversationID = UUID(uuidString: value) {
            Task { @MainActor in
                AppRouter.shared.openCoach(conversationID: conversationID)
            }
        }
        completionHandler()
    }
}
