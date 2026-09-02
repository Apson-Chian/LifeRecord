import SwiftUI
import SwiftData

@main
struct LifeRecordApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()
    @State private var syncCoordinator = SyncCoordinator()
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(syncCoordinator)
                .environmentObject(router)
                .tint(AppTheme.accent)
        }
        .modelContainer(for: [MealEntry.self, BodyMetric.self, WaterEntry.self, SyncTombstone.self, CoachConversation.self, CoachMessage.self])
    }
}
