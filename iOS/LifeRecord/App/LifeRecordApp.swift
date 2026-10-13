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
                .tint(settings.accentColor == "blue" ? .blue : settings.accentColor == "green" ? .green : settings.accentColor == "orange" ? .orange : AppTheme.accent)
                .preferredColorScheme(settings.appearance == "light" ? .light : settings.appearance == "dark" ? .dark : nil)
        }
        // WaterEntry remains only as a legacy schema entity for store migration.
        .modelContainer(for: [MealEntry.self, FavoriteFood.self, BodyMetric.self, WaterEntry.self, WorkoutEntry.self, SyncTombstone.self, CoachConversation.self, CoachMessage.self])
    }
}
