import SwiftUI
import SwiftData
import Charts

enum OnboardingState {
    private static let hasSeenKey = "hasSeenLifeRecordOnboarding"
    static var hasSeenOnboarding: Bool { UserDefaults.standard.bool(forKey: hasSeenKey) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: hasSeenKey) }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var useExamples = false
    @State private var error: String?
    private let titles = ["从今天的一餐开始", "让记录，慢慢连成变化", "有问题，和教练聊聊", "按你的节奏开始"]
    private let details = [
        "饮食、训练和身体测量，都放在「今日」。先记一项就好，不必一次填完。",
        "在「趋势」回看热量、训练与身体变化。切换时间范围，也能点进每一天的明细。",
        "聊饮食、训练，或请教练整理已有记录。使用 AI 需要联网和可用的服务。",
        "直接记录自己的生活，或先用一份完整示例熟悉功能。之后都能在设置中重看导览。"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button { move(to: step - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("上一步")
                } else { Text("LifeRecord").font(.headline) }
                Spacer()
                Button("跳过") { finish(withExamples: false) }.frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("保留现有记录，直接进入应用")
            }
            .padding(.horizontal, 24)
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Capsule().fill(index <= step ? AppTheme.accent : Color.secondary.opacity(0.15)).frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("使用导览，第 \(step + 1) 步，共 4 步")
            .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(["01 / 轻松记录", "02 / 看见变化", "03 / 智能教练", "04 / 准备好了"][step])
                            .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                        Text(titles[step]).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text(details[step]).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    preview
                    if step == 0 {
                        tip("plus.circle", "记一餐或一次测量", "点今日页右上角的「＋」，手动填写即可保存。")
                        tip("timer", "训练可以先计时", "结束后再补部位、动作、重量和次数。")
                    } else if step == 1 {
                        tip("hand.tap", "从概览走到明细", "点开图表或训练日历，查看每一天发生了什么。")
                        tip("chart.xyaxis.line", "空白不等于零", "缺少记录的日期会留空，不会当作零摄入或零体重。")
                    } else if step == 2 {
                        tip("checkmark.shield", "由你决定是否修改记录", "需要教练操作记录时，先开启记录权限，并留意操作与复核提示。")
                        tip("internaldrive", "日常记录可离线使用", "启用同步或发起 AI 请求时，相关数据才会发送至配置的服务。")
                    } else {
                        tip("slider.horizontal.3", "进入后，先设自己的目标", "到「设置 → 个人与目标」调整体重与每日营养目标。")
                        Text("示例为合成内容，仅保存在本机；不计入真实目标反馈、提醒或 AI 周报，也不会同步。清除示例会保留你自己的记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 8) {
                Button {
                    if step < 3 { move(to: step + 1) } else { finish(withExamples: useExamples) }
                } label: {
                    HStack {
                        Text(step == 3 ? (useExamples ? "载入示例，开始体验" : "开始我的记录") : "继续")
                        Image(systemName: "arrow.right")
                    }.frame(maxWidth: .infinity).frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("onboarding-continue")
                Text(step == 3 ? "无需现在登录或配置接口" : "\(step + 1) / 4 · 随时可以跳过")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
            .frame(maxWidth: .infinity).background(.regularMaterial)
        }
        .background(AppBackground())
        .interactiveDismissDisabled()
        .alert("示例未能保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private var preview: some View {
        if step == 0 {
            card {
                HStack { Label("今日的一小步", systemImage: "sun.max").font(.headline); Spacer(); exampleBadge }
                previewRow("fork.knife", "燕麦鸡蛋牛奶碗", "早餐 · 527 kcal", .orange)
                Divider()
                previewRow("dumbbell", "胸部 · 三头", "45 分钟 · 2 个动作", .teal)
                Divider()
                previewRow("scalemass", "晨起测量", "65.0 kg · 体脂 14.3%", AppTheme.accent)
            }
        } else if step == 1 {
            card {
                HStack { Text("一个月的记录").font(.headline); Spacer(); exampleBadge }
                Text("体重有波动，变化看趋势").font(.subheadline).foregroundStyle(.secondary)
                Chart {
                    ForEach(0..<14, id: \.self) { day in
                        LineMark(x: .value("日期", day), y: .value("体重", previewWeight(day)))
                            .foregroundStyle(AppTheme.accent).interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: 63.8...65.3).chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 130)
                .accessibilityLabel("示例体重折线：随时间缓慢上升，伴有日常波动")
                HStack { Label("每日热量", systemImage: "flame"); Spacer(); Label("训练日历", systemImage: "calendar") }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } else if step == 2 {
            card {
                HStack { Label("智能教练", systemImage: "bubble.left.and.bubble.right").font(.headline); Spacer(); exampleBadge }
                Text("这周的训练记录在哪里看？")
                    .padding(14).frame(maxWidth: .infinity, alignment: .trailing)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                Text("到「趋势」打开训练日历，选择日期，就能查看训练部位、动作和每组明细。")
                    .font(.subheadline).padding(14).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                Text("预先编写的对话展示，无需连接 AI").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 12) {
                choice(false, symbol: "square.and.pencil", title: "从自己的第一条开始", detail: "保留现有内容，不添加示例。")
                choice(true, symbol: "sparkles.rectangle.stack", title: "先体验完整示例", detail: "近 30 天饮食、身体测量、训练与两组教练对话；可随时清除。")
            }
        }
    }

    private func previewWeight(_ day: Int) -> Double {
        let progress = Double(day) * 0.07
        let wave = sin(Double(day)) * 0.12
        return 64.0 + progress + wave
    }

    private var exampleBadge: some View {
        Text("示意").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18, content: content).padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.secondary.opacity(0.12)))
    }
    private func previewRow(_ symbol: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color).frame(width: 42, height: 42)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(AppTheme.accent).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
    private func choice(_ examples: Bool, symbol: String, title: String, detail: String) -> some View {
        Button { useExamples = examples } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol).font(.title2).frame(width: 28)
                VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Spacer(minLength: 0)
                Image(systemName: useExamples == examples ? "checkmark.circle.fill" : "circle").font(.title3)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(useExamples == examples ? AppTheme.accent.opacity(0.08) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(useExamples == examples ? AppTheme.accent : Color.secondary.opacity(0.15)))
        }.buttonStyle(.plain).foregroundStyle(.primary)
            .accessibilityAddTraits(useExamples == examples ? .isSelected : [])
            .accessibilityIdentifier(examples ? "onboarding-examples" : "onboarding-blank")
    }
    private func move(to next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = next }
    }
    private func finish(withExamples: Bool) {
        if withExamples && !DemoDataService.reinstall(context: context) {
            error = "请先保存正在编辑的记录后重试，也可以选择从自己的第一条开始。"
            return
        }
        OnboardingState.markSeen()
        dismiss()
    }
}
