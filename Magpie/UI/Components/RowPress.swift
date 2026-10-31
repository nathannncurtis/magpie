import SwiftUI

/// Press feedback for the lists' tappable rows, which take their tap from a gesture
/// rather than a Button: the row keeps its tap gesture, and a zero-distance drag
/// alongside it lights the ghost fill while a finger is down.
extension View {

    /// The row's tap, with the pressed fill behind it while the touch lasts.
    func rowPress(perform action: @escaping () -> Void) -> some View {
        modifier(RowPress(action: action))
    }
}

private struct RowPress: ViewModifier {
    let action: () -> Void
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .background(Palette.fill.opacity(pressed ? 1 : 0))
            .contentShape(.rect)
            .onTapGesture(perform: action)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // A moving finger is a scroll, not a press.
                        pressed = value.translation == .zero
                    }
                    .onEnded { _ in pressed = false }
            )
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
