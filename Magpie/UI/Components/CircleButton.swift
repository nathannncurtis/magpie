import SwiftUI

/// A bar button's fixed metrics (03 · Chrome): the hit area and the symbol inside.
enum CircleButtonLayout {

    /// The hit area, which also holds the symbol.
    static let hitSize: CGFloat = 48
    /// The symbol inside.
    static let symbolSize: CGFloat = 20
    /// The pressed fill, in the middle of the spec's 8-10% band.
    static let pressedFillOpacity = 0.09
    /// How faint a disabled button's symbol sits: still there, not calling, and still
    /// plain against a mid-luminance tint.
    static let disabledOpacity = 0.45
}

/// A bar button (03 · Chrome): a 48 × 48 hit area holding a 20 pt symbol, with no
/// background of its own. The ••• state fills with `ink` while the menu is open; a
/// disabled one keeps its place and fades.
struct CircleButton<Content: View>: View {

    /// Whether the pressed fill shows.
    var isPressed = false
    let action: () -> Void
    private let content: () -> Content

    init(
        isPressed: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isPressed = isPressed
        self.action = action
        self.content = content
    }

    /// A disabled button keeps its place and fades instead: the caller's `disabled`
    /// state reaches it through the environment, so every bar row reads the same.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: CircleButtonLayout.hitSize, height: CircleButtonLayout.hitSize)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : CircleButtonLayout.disabledOpacity)
        .background {
            if isPressed {
                Circle().fill(Palette.ink.opacity(CircleButtonLayout.pressedFillOpacity))
            }
        }
    }
}

/// One 20 pt SF Symbol at medium weight, the content a bar button holds.
struct CircleButtonSymbol: View {

    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: CircleButtonLayout.symbolSize, weight: .medium))
            .imageScale(.medium)
    }
}

extension CircleButton where Content == CircleButtonSymbol {

    /// A button holding one SF Symbol.
    init(systemName: String, isPressed: Bool = false, action: @escaping () -> Void) {
        self.init(isPressed: isPressed, action: action) {
            CircleButtonSymbol(systemName: systemName)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        CircleButton(systemName: "chevron.backward") {}
        CircleButton(action: {}) { TabCount(count: 4) }
        CircleButton(systemName: "ellipsis", isPressed: true) {}
    }
    .foregroundStyle(Color(hex: 0x3A2E26))
    .padding(30)
}
