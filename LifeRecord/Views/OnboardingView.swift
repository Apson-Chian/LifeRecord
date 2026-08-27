import SwiftUI
import SwiftData
import Charts

enum OnboardingState {
    private static let hasSeenKey = "hasSeenLifeRecordOnboarding"

    static var hasSeenOnboarding: Bool {
        UserDefaults.standard.bool(forKey: hasSeenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: hasSeenKey)
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BodyMetric.date) private var bodyMetrics: [BodyMetric]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \WaterEntry.date) private var waterEntries: [WaterEntry]
    @Query(sort: \CoachConversation.updatedAt, order: .reverse) private var conversations: [CoachConversation]

    @State private var page = OnboardingTopic.home

    private let pages = OnboardingTopic.allCases

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages) { topic in
                    OnboardingPageView(
                        topic: topic,
                        bodyMetrics: bodyMetrics,
                        meals: meals,
                        waterEntries: waterEntries,
                        conversations: conversations,
                        onReinstallDemoData: {
                            DemoDataService.reinstall(context: modelContext)
                        }
                    )
                    .tag(topic)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            VStack(spacing: 12) {
                Button {
                    if let index = pages.firstIndex(of: page), index + 1 < pages.count {
                        withAnimation(.spring(response: 0.36, dampingFraction: 1)) {
                            page = pages[index + 1]
                        }
                    } else {
                        finish()
                    }
                } label: {
                    Text(page == pages.last ? "开始使用" : "继续")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("跳过引导") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .background(AppBackground())
        .interactiveDismissDisabled()
        .task {
            DemoDataService.installIfNeeded(context: modelContext)
        }
    }

    private func finish() {
        OnboardingState.markSeen()
        dismiss()
    }
}

private enum OnboardingTopic: String, CaseIterable, Identifiable {
    case home
    case trends
    case coach
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "今日概览"
        case .trends: "身体趋势"
        case .coach: "AI 助手"
        case .privacy: "隐私与联动"
        }
    }

    var detail: String {
        switch self {
        case .home:
            "首页会汇总体重、热量、蛋白质、饮水和 LifeTrack 今日运动。示例数据已经写入，你可以直接在对应栏目查看效果。"
        case .trends:
            "趋势页顶部横向展示体重、体脂、营养和饮水摘要，下方展示对应图表与记录连续性。示例数据覆盖最近 30 天。"
        case .coach:
            "教练页支持多个独立对话，可围绕增肌、饮食、训练或配料表连续追问。示例对话已经写入，用于展示上下文和 Markdown 排版。"
        case .privacy:
            "健康数据默认保存在本机 SwiftData；仅在发起 AI 请求时发送所选文字和图片。与 LifeTrack 通过 App Group 共享摘要，不上传服务器。"
        }
    }
}

private struct OnboardingPageView: View {
    let topic: OnboardingTopic
    let bodyMetrics: [BodyMetric]
    let meals: [MealEntry]
    let waterEntries: [WaterEntry]
    let conversations: [CoachConversation]
    let onReinstallDemoData: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            preview
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                Text(topic.title)
                    .font(.title2.bold())
                Text(topic.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Label("示例数据已写入本机", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.success)

            Spacer(minLength: 4)
        }
        .padding(.top, 28)
    }

    @ViewBuilder
    private var preview: some View {
        switch topic {
        case .home: TodayPreview(bodyMetrics: bodyMetrics, meals: meals, waterEntries: waterEntries)
        case .trends: TrendsPreview(
            bodyMetrics: bodyMetrics,
            meals: meals,
            waterEntries: waterEntries,
            onReinstall: onReinstallDemoData
        )
        case .coach: CoachPreview(conversations: conversations)
        case .privacy: PrivacyPreview()
        }
    }
}

private struct TodayPreview: View {
    let bodyMetrics: [BodyMetric]
    let meals: [MealEntry]
    let waterEntries: [WaterEntry]

    private var latestWeight: Double { bodyMetrics.last?.weight ?? 0 }
    private var todayCalories: Double {
        let today = Calendar.current.startOfDay(for: .now)
        return meals
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.calories }
    }
    private var todayProtein: Double {
        let today = Calendar.current.startOfDay(for: .now)
        return meals
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.protein }
    }
    private var todayWater: Double {
        let today = Calendar.current.startOfDay(for: .now)
        return waterEntries
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.milliliters }
    }

    var body: some View {
        VStack(spacing: 12) {
            GlassCard {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(AppTheme.accent.opacity(0.13), lineWidth: 9)
                        Circle()
                            .trim(from: 0, to: 0.22)
                            .stroke(AppTheme.accent.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(latestWeight.formatted(.number.precision(.fractionLength(1))))
                                .font(.headline.monospacedDigit())
                            Text("kg")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 78, height: 78)

                    VStack(alignment: .leading, spacing: 7) {
                        Label("热量 \(Int(todayCalories)) kcal", systemImage: "flame.fill")
                        Label("蛋白质 \(Int(todayProtein)) g", systemImage: "bolt.fill")
                        Label("饮水 \(Int(todayWater)) ml", systemImage: "drop.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                demoMetric("体重", latestWeight.formatted(.number.precision(.fractionLength(1))), "scalemass")
                demoMetric("热量", "\(Int(todayCalories))", "flame")
                demoMetric("饮水", "\(Int(todayWater))", "drop")
            }

            if let latest = bodyMetrics.last {
                GlassCard {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最近体重记录").font(.caption.weight(.semibold))
                            Text(latest.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(latest.weight.formatted(.number.precision(.fractionLength(1))) + " kg")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func demoMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct TrendsPreview: View {
    let bodyMetrics: [BodyMetric]
    let meals: [MealEntry]
    let waterEntries: [WaterEntry]
    let onReinstall: () -> Void

    private var weightData: [(date: Date, value: Double)] {
        bodyMetrics.map { ($0.date, $0.weight) }
    }

    private var calorieData: [(date: Date, value: Double)] {
        groupedDaily(meals) { $0.calories }
    }

    private var proteinData: [(date: Date, value: Double)] {
        groupedDaily(meals) { $0.protein }
    }

    private var waterData: [(date: Date, value: Double)] {
        let grouped = Dictionary(grouping: waterEntries) { Calendar.current.startOfDay(for: $0.date) }
        return grouped
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.milliliters }) }
            .sorted { $0.date < $1.date }
    }

    private var hasData: Bool {
        !weightData.isEmpty && !calorieData.isEmpty && !waterData.isEmpty
    }

    var body: some View {
        if hasData {
            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    metric("体重", latestWeightText, "scalemass")
                    metric("体脂", latestBodyFatText, "figure.arms.open")
                    metric("日均热量", String(format: "%.0f kcal", averageText(calorieData)), "flame")
                }

                chartCard("体重趋势") {
                    Chart(weightData, id: \.date) { item in
                        AreaMark(x: .value("日期", item.date), y: .value("体重", item.value))
                            .foregroundStyle(AppTheme.accent.opacity(0.16))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("日期", item.date), y: .value("体重", item.value))
                            .foregroundStyle(AppTheme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                }

                HStack(spacing: 7) {
                    metric("日均热量", String(format: "%.0f kcal", averageText(calorieData)), "flame")
                    metric("日均蛋白", String(format: "%.0f g", averageText(proteinData)), "bolt.fill")
                    metric("日均饮水", String(format: "%.1f L", averageText(waterData) / 1000), "drop.fill")
                }

                GlassCard {
                    HStack(spacing: 10) {
                        miniChart("热量", calorieData, AppTheme.accent, goal: 2600)
                        miniChart("饮水", waterData, AppTheme.water, goal: 2800)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image(systemName: "calendar.badge.checkmark")
                                .foregroundStyle(AppTheme.accent)
                            Text("记录连续性 7 / 7 天")
                                .font(.caption.weight(.semibold))
                        }
                        Text("30 天身体测量 · 30 天饮食 · 29 天完整晚餐 · 每日 4 次饮水")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("正在准备示例数据", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Text("如果这里仍为空，说明示例数据没有成功写入。点击下方按钮会重新生成 30 天体重、体脂、饮食、饮水和教练对话数据。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重新写入完整示例数据", action: onReinstall)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func groupedDaily(_ items: [MealEntry], value: (MealEntry) -> Double) -> [(date: Date, value: Double)] {
        let grouped = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }
        return grouped
            .map { ($0.key, $0.value.reduce(0) { $0 + value($1) }) }
            .sorted { $0.date < $1.date }
    }

    private var latestWeightText: String {
        bodyMetrics.last.map { $0.weight.formatted(.number.precision(.fractionLength(1))) + " kg" } ?? "—"
    }

    private var latestBodyFatText: String {
        bodyMetrics.last?.bodyFat.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—"
    }

    private func averageText(_ data: [(date: Date, value: Double)]) -> Double {
        guard !data.isEmpty else { return 0 }
        return data.reduce(0) { $0 + $1.value } / Double(data.count)
    }

    private func miniChart(_ title: String, _ data: [(date: Date, value: Double)], _ color: Color, goal: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Chart(data, id: \.date) { item in
                BarMark(x: .value("日期", item.date, unit: .day), y: .value(title, item.value))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(2)
                RuleMark(y: .value("目标", goal))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
            }
            .chartYAxis(.hidden)
            .frame(height: 58)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chartCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                content()
                    .frame(height: title == "体重趋势" ? 88 : 64)
            }
        }
    }
}

private struct CoachPreview: View {
    let conversations: [CoachConversation]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sidebar.left")
                Text("对话")
                    .font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            if conversations.isEmpty {
                GlassCard {
                    Text("示例对话生成中，稍后回到教练页查看。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(conversations.prefix(3)) { conversation in
                    GlassCard {
                        HStack(spacing: 10) {
                            Image(systemName: "bubble.left.fill")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(conversation.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(conversation.messages.count) 条消息 · \(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

private struct PrivacyPreview: View {
    var body: some View {
        VStack(spacing: 12) {
            GlassCard {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("健康数据保存在本机")
                            .font(.caption.weight(.semibold))
                        Text("SwiftData 数据不上传服务器")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassCard {
                HStack(spacing: 10) {
                    Image(systemName: "key.horizontal.fill")
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("API Key 存在钥匙串")
                            .font(.caption.weight(.semibold))
                        Text("不同服务商密钥分开保存")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassCard {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LifeRecord 与 LifeTrack")
                            .font(.caption.weight(.semibold))
                        Text("共享身体档案、今日饮食与运动摘要")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
