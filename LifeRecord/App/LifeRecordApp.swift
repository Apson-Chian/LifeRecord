import SwiftUI
import SwiftData

@main
struct LifeRecordApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .tint(AppTheme.accent)
        }
        .modelContainer(for: [MealEntry.self, BodyMetric.self, WaterEntry.self, CoachMessage.self])
    }
}
