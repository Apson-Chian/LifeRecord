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
    @Query private var tombstones: [SyncTombstone]
    @State private var showsOnboarding = !OnboardingState.hasSeenOnboarding

    private var syncFingerprint: String {
        let mealStamp = meals.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let bodyStamp = bodyMetrics.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let waterStamp = waterEntries.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
        let deletionStamp = tombstones.map(\.deletedAt.timeIntervalSince1970).max() ?? 0
        return "\(meals.count):\(mealStamp):\(bodyMetrics.count):\(bodyStamp):\(waterEntries.count):\(waterStamp):\(tombstones.count):\(deletionStamp)"
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
            await syncCoordinator.sync(context: modelContext, settings: settings)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await syncCoordinator.sync(context: modelContext, settings: settings)
            }
        }
        .onChange(of: syncFingerprint) { _, _ in
            Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
        }
        .onChange(of: settings.profileUpdatedAt) { _, _ in
            Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
        }
        .onChange(of: scenePhase) { _, phase in
            updateCoachVisibility(for: phase)
            if phase == .active {
                Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
            }
        }
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

    private func updateCoachVisibility(for phase: ScenePhase) {
        AIAnswerNotificationCenter.shared.isCoachVisible = selectedTab == 2 && phase == .active
    }
}
