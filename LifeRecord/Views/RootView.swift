import SwiftUI
import SwiftData

struct RootView: View {
    @SceneStorage("selectedTab") private var selectedTab = 0
    @StateObject private var coachTaskCenter = CoachTaskCenter()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @EnvironmentObject private var router: AppRouter
    @Query private var meals: [MealEntry]
    @Query private var bodyMetrics: [BodyMetric]
    @Query private var waterEntries: [WaterEntry]
    @AppStorage(ReminderPreferences.key) private var reminderRaw = ""
    @Query private var workouts: [WorkoutEntry]
    @Query private var tombstones: [SyncTombstone]
    @State private var showsOnboarding = !OnboardingState.hasSeenOnboarding

    private var syncFingerprint: String {
        let mealStamp = meals.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let bodyStamp = bodyMetrics.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let waterStamp = waterEntries.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let workoutStamp = workouts.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let deletionStamp = tombstones.map(\.deletedAt.timeIntervalSince1970).max() ?? 0
        return "\(workouts.count):\(workoutStamp):\(meals.count):\(mealStamp):\(bodyMetrics.count):\(bodyStamp):\(waterEntries.count):\(waterStamp):\(tombstones.count):\(deletionStamp)"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "house.fill") }
                .tag(0)
            ProgressDashboardView()
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(1)
            CoachView()
                .tabItem { Label("教练", systemImage: "wand.and.sparkles") }
                .tag(2)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .environmentObject(coachTaskCenter)
        .task {
            DemoDataService.installIfNeeded(context: modelContext)
            refreshReminders()
            await syncCoordinator.sync(context: modelContext, settings: settings)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await syncCoordinator.sync(context: modelContext, settings: settings)
            }
        }
        .onChange(of: syncFingerprint) { _, _ in
            refreshReminders()
            Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
        }
        .onChange(of: settings.profileUpdatedAt) { _, _ in
            Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
        }
        .onChange(of: scenePhase) { _, phase in
            updateCoachVisibility(for: phase)
            refreshReminders()
            if phase == .active {
                Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
            }
        }
        .onChange(of: reminderRaw) { _, _ in refreshReminders() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshReminders() }
        .onReceive(router.$reminderRoute.compactMap { $0 }) { _ in selectedTab = 0 }
        .onChange(of: selectedTab) { _, _ in
            updateCoachVisibility(for: scenePhase)
        }
        .onReceive(router.$coachRoute.compactMap { $0 }) { _ in
            selectedTab = 2
        }
        .onAppear {
            updateCoachVisibility(for: scenePhase)
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView()
        }
    }

    private func refreshReminders() {
        RecordReminderCenter.shared.refresh(preferences: .decode(reminderRaw), records: .init(
            meals: meals.filter { !$0.isDemo }.map(\.date), water: waterEntries.filter { !$0.isDemo }.map(\.date),
            body: bodyMetrics.filter { !$0.isDemo }.map(\.date), workouts: workouts.map(\.date)))
    }

    private func updateCoachVisibility(for phase: ScenePhase) {
        AIAnswerNotificationCenter.shared.isCoachVisible = selectedTab == 2 && phase == .active
    }
}
