import SwiftUI

enum AppTheme {
    static let accentFill = Color(red: 0.34, green: 0.32, blue: 0.96)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.65, green: 0.62, blue: 1, alpha: 1)
            : UIColor(red: 0.34, green: 0.32, blue: 0.96, alpha: 1)
    })
    static let accentSoft = Color(red: 0.48, green: 0.43, blue: 1.00)
    static let protein = Color(red: 0.20, green: 0.55, blue: 0.98)
    static let carbs = Color(red: 0.95, green: 0.64, blue: 0.22)
    static let fat = Color(red: 0.88, green: 0.35, blue: 0.67)
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
            .background(CardSurface(tint: tint))
    }
}

/// Shared surface keeps dashboard cards and action tiles consistent in both appearances.
struct CardSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var tint: Color = AppTheme.accent
    var radius: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [tint.opacity(colorScheme == .dark ? 0.13 : 0.055), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint.opacity(contrast == .increased ? 0.5 : 0.13), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.025), radius: 2, y: 2)
            .shadow(color: tint.opacity(colorScheme == .dark ? 0 : 0.045), radius: 16, y: 7)
    }
}

struct AppButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = AppTheme.accentFill
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .foregroundStyle(prominent ? Color.white : tint)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(
                        colors: prominent ? [tint, tint.opacity(0.85)] : [tint.opacity(0.12), tint.opacity(0.07)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(prominent ? Color.white.opacity(0.16) : tint.opacity(0.16), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
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
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Spacer(minLength: 8)
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(tint.opacity(0.08), in: Circle())
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardSurface(tint: tint, radius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.45)
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 1), value: configuration.isPressed)
    }
}

extension View {
    func keyboardDoneButton() -> some View {
        keyboardDismissControl()
    }

    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}


extension View {
    func keyboardDismissControl() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") { dismissKeyboard() }
                    .fontWeight(.semibold)
            }
        }
    }
}
