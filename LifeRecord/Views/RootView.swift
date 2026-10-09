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
    @AppStorage(ReminderPreferences.key) private var reminderRaw = ""
    @Query private var workouts: [WorkoutEntry]
    @Query private var tombstones: [SyncTombstone]
    @State private var showsOnboarding = !OnboardingState.hasSeenOnboarding

    private var syncFingerprint: String {
        let mealStamp = meals.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let bodyStamp = bodyMetrics.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let workoutStamp = workouts.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let deletionStamp = tombstones.map(\.deletedAt.timeIntervalSince1970).max() ?? 0
        return "\(workouts.count):\(workoutStamp):\(meals.count):\(mealStamp):\(bodyMetrics.count):\(bodyStamp):\(tombstones.count):\(deletionStamp)"
    }

    var body: some View {
        tabs
        .environmentObject(coachTaskCenter)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            DemoDataService.installIfNeeded(context: modelContext)
            refreshReminders()
            await syncCoordinator.sync(context: modelContext, settings: settings)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
                guard !Task.isCancelled, scenePhase == .active else { return }
                await syncCoordinator.sync(context: modelContext, settings: settings)
            }
        }
        .onChange(of: syncFingerprint) { _, _ in
            refreshReminders()
            syncWhenActive()
        }
        .onChange(of: settings.profileUpdatedAt) { _, _ in
            syncWhenActive()
        }
        .onChange(of: scenePhase) { _, phase in
            updateCoachVisibility(for: phase)
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

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("今日", systemImage: AppSymbol.today, value: 0) { TodayView() }
                Tab("趋势", systemImage: AppSymbol.trends, value: 1) { ProgressDashboardView() }
                Tab("教练", systemImage: AppSymbol.coach, value: 2) { CoachView() }
                Tab("设置", systemImage: AppSymbol.settings, value: 3) { SettingsView() }
            }
        } else {
            legacyTabs
        }
    }

    private var legacyTabs: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("今日", systemImage: AppSymbol.today) }
                .tag(0)
            ProgressDashboardView()
                .tabItem { Label("趋势", systemImage: AppSymbol.trends) }
                .tag(1)
            CoachView()
                .tabItem { Label("教练", systemImage: AppSymbol.coach) }
                .tag(2)
            SettingsView()
                .tabItem { Label("设置", systemImage: AppSymbol.settings) }
                .tag(3)
        }
    }

    private func syncWhenActive() {
        guard scenePhase == .active else { return }
        Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
    }

    private func refreshReminders() {
        RecordReminderCenter.shared.refresh(preferences: .decode(reminderRaw), records: .init(
            meals: meals.filter { !$0.isDemo }.map(\.date),
            body: bodyMetrics.filter { !$0.isDemo }.map(\.date), workouts: workouts.map(\.date)))
    }

    private func updateCoachVisibility(for phase: ScenePhase) {
        AIAnswerNotificationCenter.shared.isCoachVisible = selectedTab == 2 && phase == .active
    }
}
