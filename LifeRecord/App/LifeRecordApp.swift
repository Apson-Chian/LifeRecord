import SwiftUI
import SwiftData

@main
struct LifeRecordApp: App {
    @State private var settings = AppSettings()
    @State private var syncCoordinator = SyncCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(syncCoordinator)
                .tint(AppTheme.accent)
        }
        .modelContainer(for: [MealEntry.self, BodyMetric.self, WaterEntry.self, SyncTombstone.self, CoachConversation.self, CoachMessage.self])
    }
}
