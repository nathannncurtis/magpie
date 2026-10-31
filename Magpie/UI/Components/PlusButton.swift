import SwiftUI

/// The ink glass circle that opens a new tab. In dark the ink glass is paper.
struct PlusButton: View {
    var action: () -> Void

    private enum ButtonMetrics {
        static let size: CGFloat = 54
        static let icon: CGFloat = 22
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: ButtonMetrics.icon, weight: .medium))
                .imageScale(.medium)
                .foregroundStyle(Palette.onInk)
                .frame(width: ButtonMetrics.size, height: ButtonMetrics.size)
                .glassEffect(.regular.tint(Palette.ink).interactive(), in: .circle)
                .contentShape(.circle)
        }
        // A plain style: the prominent glass style pads its label into a wider capsule,
        // and the button is a 54 pt circle.
        .buttonStyle(.plain)
        .accessibilityLabel(Text("New tab"))
    }
}

#Preview {
    PlusButton(action: {})
        .padding(20)
}
