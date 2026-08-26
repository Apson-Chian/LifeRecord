import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \BodyMetric.date, order: .reverse) private var bodyMetrics: [BodyMetric]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waterEntries: [WaterEntry]

    @State private var selectedDate = Date.now
    @State private var activeSheet: SheetDestination?

    private enum SheetDestination: String, Identifiable {
        case meal, weight, water
        var id: String { rawValue }
    }

    private var selectedMeals: [MealEntry] {
        meals.filter { Calendar.current.isSameDay($0.date, selectedDate) }
    }

    private var nutrition: DailyNutrition {
        selectedMeals.reduce(into: DailyNutrition()) { $0.add($1) }
    }

    private var water: Double {
        waterEntries
            .filter { Calendar.current.isSameDay($0.date, selectedDate) }
            .reduce(0) { $0 + $1.milliliters }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 18) {
                        DateNavigator(selectedDate: $selectedDate)
                        goalHero
                        quickActions
                        macroCard
                        mealLog
                        insightCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { activeSheet = .meal } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("添加记录")
                }
            }
            .sheet(item: $activeSheet) { destination in
                switch destination {
                case .meal: AddMealView(defaultDate: selectedDate)
                case .weight: AddWeightView(defaultDate: selectedDate, lastWeight: bodyMetrics.first?.weight ?? settings.baselineWeight)
                case .water: AddWaterView(defaultDate: selectedDate)
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let prefix = hour < 11 ? "早上好" : (hour < 18 ? "今天状态如何" : "晚上好")
        return settings.displayName.isEmpty ? prefix : "\(prefix)，\(settings.displayName)"
    }

    private var currentWeight: Double {
        bodyMetrics.first(where: { $0.date <= Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: selectedDate)) ?? selectedDate })?.weight
            ?? settings.baselineWeight
    }

    private var weightProgress: Double {
        let total = settings.targetWeight - settings.baselineWeight
        guard abs(total) > 0.01 else { return 1 }
        return min(max((currentWeight - settings.baselineWeight) / total, 0), 1)
    }

    private var goalHero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(settings.fitnessGoal.rawValue, systemImage: settings.fitnessGoal.symbol)
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                        Text(settings.fitnessGoal.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(settings.height)) cm")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 22) {
                    ZStack {
                        Circle().stroke(AppTheme.accent.opacity(0.13), lineWidth: 11)
                        Circle()
                            .trim(from: 0, to: settings.fitnessGoal == .gainMuscle ? weightProgress : min(nutrition.calories / max(settings.calorieGoal, 1), 1))
                            .stroke(AppTheme.accent.gradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text(settings.fitnessGoal == .gainMuscle ? currentWeight.formatted(.number.precision(.fractionLength(1))) : nutrition.calories.formatted(.number.precision(.fractionLength(0))))
                                .font(.title2.bold().monospacedDigit())
                            Text(settings.fitnessGoal == .gainMuscle ? "kg" : "千卡")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 108, height: 108)

                    VStack(alignment: .leading, spacing: 12) {
                        if settings.fitnessGoal == .gainMuscle {
                            Label("目标 \(settings.targetWeight.formatted(.number.precision(.fractionLength(1)))) kg", systemImage: "flag.checkered")
                            Label("每周 +\(settings.weeklyWeightTarget.formatted(.number.precision(.fractionLength(2)))) kg", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        Label(calorieStatusText, systemImage: "flame.fill")
                        Label("蛋白质 \(Int(nutrition.protein)) / \(Int(settings.proteinGoal)) g", systemImage: "bolt.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var calorieStatusText: String {
        let remaining = settings.calorieGoal - nutrition.calories
        if remaining >= 0 { return "还差 \(Int(remaining)) 千卡" }
        return "超出 \(Int(abs(remaining))) 千卡"
    }

    private var latestWeightText: String {
        guard let latest = bodyMetrics.first else { return "尚未记录体重" }
        return "最近 \(latest.weight.formatted(.number.precision(.fractionLength(1)))) kg"
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            ActionTile(title: "记一餐", subtitle: "多图/配料表", symbol: "fork.knife.circle.fill", tint: AppTheme.accent) {
                activeSheet = .meal
            }
            ActionTile(title: "记体重", subtitle: "追踪趋势", symbol: "scalemass.fill", tint: AppTheme.protein) {
                activeSheet = .weight
            }
            ActionTile(title: "喝水", subtitle: "+250 ml", symbol: "drop.fill", tint: AppTheme.water) {
                let entry = WaterEntry(date: selectedDate, milliliters: 250)
                modelContext.insert(entry)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private var macroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("营养目标").font(.headline)
                MacroProgressView(title: "蛋白质", value: nutrition.protein, goal: settings.proteinGoal, color: AppTheme.protein)
                MacroProgressView(title: "碳水", value: nutrition.carbs, goal: settings.carbsGoal, color: AppTheme.carbs)
                MacroProgressView(title: "脂肪", value: nutrition.fat, goal: settings.fatGoal, color: AppTheme.fat)
                MacroProgressView(title: "饮水", value: water / 1000, goal: settings.waterGoal / 1000, color: AppTheme.water, unit: "L")
            }
        }
    }

    private var mealLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("饮食记录").font(.title3.bold())
                Spacer()
                Text("\(selectedMeals.count) 项").font(.subheadline).foregroundStyle(.secondary)
            }
            if selectedMeals.isEmpty {
                GlassCard {
                    ContentUnavailableView {
                        Label("还没有餐食", systemImage: "fork.knife.circle")
                    } description: {
                        Text("用文字、照片或手动方式记录第一餐。")
                    } actions: {
                        Button("添加餐食") { activeSheet = .meal }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                ForEach(MealKind.allCases) { kind in
                    let group = selectedMeals.filter { $0.kind == kind }
                    if !group.isEmpty {
                        MealSection(kind: kind, meals: group)
                    }
                }
            }
        }
    }

    private var insightCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "wand.and.sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日提示").font(.headline)
                    Text(localInsight)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var localInsight: String {
        guard !selectedMeals.isEmpty else {
            return settings.fitnessGoal == .gainMuscle
                ? "你目前偏瘦，增肌期优先保证持续的热量盈余和力量训练。先记录真实摄入，连续两周再根据体重均值调整。"
                : "先记录真实情况，不追求完美。连续记录比单日数字更有分析价值。"
        }
        if nutrition.protein < settings.proteinGoal * 0.55 {
            return settings.fitnessGoal == .gainMuscle
                ? "蛋白质进度偏慢。下一餐先补一份 30–40g 蛋白质，同时搭配足量主食，增肌期不要只吃蛋白而忽略总热量。"
                : "蛋白质进度偏慢。下一餐可以优先安排一份易估量的优质蛋白。"
        }
        if nutrition.calories > settings.calorieGoal {
            return "今天已超过设定热量，但无需用极端节食补偿。保持正常训练与作息，关注一周平均值。"
        }
        return "今天的宏量营养进度比较平稳。晚些时候结合饥饿感和训练安排决定是否需要加餐。"
    }
}

private struct DateNavigator: View {
    @Binding var selectedDate: Date
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 10) {
            Button { moveDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressScaleButtonStyle())

            DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            if !calendar.isDateInToday(selectedDate) {
                Button("今天") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 1)) { selectedDate = .now }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }

            Button { moveDay(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
    }

    private func moveDay(_ value: Int) {
        guard let next = calendar.date(byAdding: .day, value: value, to: selectedDate) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 1)) { selectedDate = next }
    }
}

private struct MealSection: View {
    @Environment(\.modelContext) private var modelContext
    let kind: MealKind
    let meals: [MealEntry]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(kind.rawValue, systemImage: kind.symbol)
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                ForEach(meals) { meal in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(meal.name).font(.subheadline.weight(.semibold))
                                if meal.source == .ai {
                                    Image(systemName: "sparkles").font(.caption2).foregroundStyle(AppTheme.accent)
                                }
                            }
                            Text("蛋白 \(meal.protein, specifier: "%.0f")g · 碳水 \(meal.carbs, specifier: "%.0f")g · 脂肪 \(meal.fat, specifier: "%.0f")g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(meal.calories, specifier: "%.0f")")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Text("kcal").font(.caption2).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button("删除", systemImage: "trash", role: .destructive) { modelContext.delete(meal) }
                    }
                    if meal.id != meals.last?.id { Divider() }
                }
            }
        }
    }
}
