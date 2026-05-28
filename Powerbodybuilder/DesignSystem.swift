import SwiftUI
// Screen size helpers
extension UIScreen {
    static let width = UIScreen.main.bounds.width
    static let height = UIScreen.main.bounds.height
}
// ═══════════════════════════════════════════
// COLORS
// ═══════════════════════════════════════════

extension Color {
    static let appBG = Color(red: 0.031, green: 0.043, blue: 0.063)
    static let appSurface = Color(red: 0.059, green: 0.075, blue: 0.102)
    static let appSurface2 = Color(red: 0.082, green: 0.102, blue: 0.137)
    static let appBorder = Color(red: 0.165, green: 0.208, blue: 0.267).opacity(0.6)
    static let appRed = Color(red: 0.902, green: 0.224, blue: 0.275)
    static let appRedGlow = Color(red: 0.902, green: 0.224, blue: 0.275).opacity(0.15)
    static let appGold = Color(red: 0.957, green: 0.635, blue: 0.38)
    static let appGreen = Color(red: 0.322, green: 0.718, blue: 0.533)
    static let appBlue = Color(red: 0.271, green: 0.482, blue: 0.616)
    static let appYellow = Color(red: 0.957, green: 0.816, blue: 0.325)
    static let appOrange = Color(red: 0.957, green: 0.522, blue: 0.263)
    static let appTextPrimary = Color(red: 0.941, green: 0.965, blue: 0.988)
    static let appTextSecondary = Color(red: 0.533, green: 0.576, blue: 0.647)
    static let appTextDim = Color(red: 0.29, green: 0.337, blue: 0.408)
}

// ═══════════════════════════════════════════
// GRADIENTS
// ═══════════════════════════════════════════

extension LinearGradient {
    static let appHeader = LinearGradient(
        colors: [
            Color(red: 0.082, green: 0.102, blue: 0.137),
            Color(red: 0.031, green: 0.043, blue: 0.063)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    static let redGlow = LinearGradient(
        colors: [
            Color.appRed.opacity(0.2),
            Color.appRed.opacity(0.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cardSheen = LinearGradient(
        colors: [
            Color.white.opacity(0.04),
            Color.white.opacity(0.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// ═══════════════════════════════════════════
// REUSABLE CARD MODIFIER
// ═══════════════════════════════════════════

struct AppCard: ViewModifier {
    var glowRed: Bool = false
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.appSurface
                    LinearGradient.cardSheen
                    if glowRed {
                        LinearGradient.redGlow
                    }
                }
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        glowRed ? Color.appRed.opacity(0.3) : Color.appBorder,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: glowRed ? Color.appRed.opacity(0.15) : Color.black.opacity(0.3),
                radius: glowRed ? 12 : 8,
                x: 0,
                y: 4
            )
    }
}

extension View {
    func appCard(glowRed: Bool = false) -> some View {
        modifier(AppCard(glowRed: glowRed))
    }
}

// ═══════════════════════════════════════════
// REUSABLE SECTION HEADER
// ═══════════════════════════════════════════

struct SectionHeader: View {
    let title: String
    var accent: Color = .appTextDim
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(accent)
            .kerning(2.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ═══════════════════════════════════════════
// ANIMATED NUMBER
// ═══════════════════════════════════════════

struct AnimatedNumber: View {
    let value: Double
    let format: String
    var color: Color = .appRed
    var fontSize: CGFloat = 22
    
    @State private var displayed: Double = 0
    
    var body: some View {
        Text(String(format: format, displayed))
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .foregroundColor(color)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    displayed = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: 0.5)) {
                    displayed = newValue
                }
            }
    }
}

// ═══════════════════════════════════════════
// STAT CELL
// ═══════════════════════════════════════════

struct PremiumStatCell: View {
    let value: String
    let label: String
    var color: Color = .appRed
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.appTextDim)
                .kerning(1.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// ═══════════════════════════════════════════
// RED ACCENT BUTTON
// ═══════════════════════════════════════════

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    
    @State private var pressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                pressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pressed = false
                action()
            }
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .black))
                    .kerning(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    Color.appRed
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            .cornerRadius(12)
            .shadow(color: Color.appRed.opacity(0.4), radius: 12, x: 0, y: 6)
            .scaleEffect(pressed ? 0.97 : 1.0)
        }
    }
}

// ═══════════════════════════════════════════
// INPUT FIELD
// ═══════════════════════════════════════════

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.appTextDim)
                    .frame(width: 20)
            }
            TextField("", text: $text)
                .placeholder(when: text.isEmpty) {
                    Text(placeholder)
                        .foregroundColor(.appTextDim)
                }
                .foregroundColor(.appTextPrimary)
                .keyboardType(keyboardType)
                .font(.system(size: 15, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appSurface2)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }

    /// Dismiss keyboard when tapping outside text fields
    func dismissKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
        )
    }

    /// Add a toolbar Done button for number pad keyboards
    func numberPadDoneButton() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.appRed)
            }
        }
    }
}

// ═══════════════════════════════════════════
// DETAIL EXPANDER
// Per-screen "Show details ▾" disclosure for minimal/standard density.
// State is session-scoped — every fresh launch starts collapsed so the
// minimal view is always the first thing the user sees.
// ═══════════════════════════════════════════

struct DetailExpander<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    @State private var expanded = false

    init(label: String = "Show details", @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded ? "Hide details" : label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .kerning(1.5)
                        .foregroundColor(.appTextSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appTextSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.appSurface2.opacity(0.6))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.appBorder, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            if expanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
