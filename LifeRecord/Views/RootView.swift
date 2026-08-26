import SwiftUI

struct RootView: View {
    @SceneStorage("selectedTab") private var selectedTab = 0

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
    }
}
