import SwiftUI
import SwiftData

struct RootView: View {
    @SceneStorage("selectedTab") private var selectedTab = 0
    @StateObject private var coachTaskCenter = CoachTaskCenter()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Query private var meals: [MealEntry]
    @Query private var bodyMetrics: [BodyMetric]
    @Query private var waterEntries: [WaterEntry]
    @Query private var tombstones: [SyncTombstone]
    @State private var showsOnboarding = !OnboardingState.hasSeenOnboarding

    private var syncFingerprint: Int {
        meals.count &* 31 &+ bodyMetrics.count &* 17 &+ waterEntries.count &* 13 &+ tombstones.count
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if coachTaskCenter.isGenerating && selectedTab != 2 {
                Button {
                    selectedTab = 2
                } label: {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 教练正在生成回答")
                                .font(.subheadline.weight(.semibold))
                            Text("可以继续使用其他功能，完成后回到教练页查看")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.primary)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 0.5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            DemoDataService.installIfNeeded(context: modelContext)
            await syncCoordinator.sync(context: modelContext, settings: settings)
        }
        .onChange(of: syncFingerprint) { _, _ in
            Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
        }
        .onChange(of: settings.profileUpdatedAt) { _, _ in
            Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await syncCoordinator.sync(context: modelContext, settings: settings) }
            }
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView()
        }
    }
}
