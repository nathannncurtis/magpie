import SwiftUI

/// Press feedback for the lists' tappable rows: the row is a button with its own style,
/// which lights the ghost fill while a finger is down. A drag gesture on the row would
/// take the touch from the list's swipe to delete, so the press comes from the button.
extension View {

    /// The row's tap, with the pressed fill behind it while the touch lasts.
    func rowPress(perform action: @escaping () -> Void) -> some View {
        modifier(RowPress(action: action))
    }
}

private struct RowPress: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        Button(action: action) {
            content
        }
        .buttonStyle(RowPressStyle())
    }
}

/// The pressed fill behind a row, with no dimming of its own.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Palette.fill.opacity(configuration.isPressed ? 1 : 0))
            .contentShape(.rect)
    }
}

#Preview {
    struct PressHost: View {
        var body: some View {
            ListRow(title: "How to season a carbon steel pan", subtitle: "seriouseats.com", host: "seriouseats.com")
                .padding(.horizontal, 16)
                .rowPress {}
        }
    }
    return PressHost()
}
