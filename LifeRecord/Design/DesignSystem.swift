import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.34, green: 0.32, blue: 0.96)
    static let accentSoft = Color(red: 0.48, green: 0.43, blue: 1.00)
    static let protein = Color(red: 0.20, green: 0.55, blue: 0.98)
    static let carbs = Color(red: 0.95, green: 0.64, blue: 0.22)
    static let fat = Color(red: 0.88, green: 0.35, blue: 0.67)
    static let water = Color.cyan
    static let meals = Color(red: 0.94, green: 0.25, blue: 0.35)
    static let recorded = Color(red: 0.16, green: 0.68, blue: 0.37)
    static let success = Color(red: 0.20, green: 0.52, blue: 0.88)
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemGroupedBackground), AppTheme.accent.opacity(0.075), Color(.systemGroupedBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    var tint: Color

    init(tint: Color = AppTheme.accent, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .shadow(color: Color.black.opacity(0.035), radius: 3, y: 2)
            .shadow(color: tint.opacity(0.07), radius: 20, y: 8)
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
    }
}

struct MacroProgressView: View {
    let title: String
    let value: Double
    let goal: Double
    let color: Color
    var unit = "g"

    private var valueText: String {
        value.formatted(.number.precision(.fractionLength(unit == "L" ? 1 : 0)))
    }

    private var goalText: String {
        goal.formatted(.number.precision(.fractionLength(unit == "L" ? 1 : 0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(valueText) / \(goalText) \(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(value, goal), total: max(goal, 1))
                .tint(color)
                .accessibilityLabel(title)
                .accessibilityValue("已记录 \(valueText) \(unit)，目标 \(goalText) \(unit)")
        }
    }
}

struct ActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.24), tint.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                Circle().stroke(.white.opacity(0.24), lineWidth: 0.5)
                            }
                            .shadow(color: tint.opacity(0.17), radius: 8, y: 4)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 1), value: configuration.isPressed)
    }
}

extension View {
    func keyboardDoneButton() -> some View {
        keyboardDismissControl().toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("收起") { dismissKeyboard() }
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "keyboard.chevron.compact.down")
                    .foregroundStyle(.secondary)
            }
        }
    }

    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}


/// A visible fallback above the keyboard, independent of SwiftUI keyboard-toolbar delivery.
private struct KeyboardDismissControl: ViewModifier {
    @State private var keyboardVisible = false
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if keyboardVisible {
                    HStack {
                        Spacer()
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 20)
                    .background(.bar)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in keyboardVisible = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }
}

extension View {
    func keyboardDismissControl() -> some View { modifier(KeyboardDismissControl()) }
}
