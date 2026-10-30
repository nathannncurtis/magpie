import SwiftUI
import UIKit

/// The glass search pill at the foot of the Archive and Bookmarks lists. It is the
/// field: tapping it focuses the search, and typing filters the list behind it live.
/// The screens it sits on run to the bottom edge under the keyboard, so the pill lifts
/// itself clear of the keys while it holds focus.
struct BottomSearchPill: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var focused: Bool
    /// How far the keyboard stands up from the foot of the screen, zero once it is away.
    @State private var keyboardRise: CGFloat = 0

    private enum PillMetrics {
        static let height: CGFloat = Metrics.Bar.bottomSearchPillHeight
        static let horizontalPadding: CGFloat = 20
        static let icon: CGFloat = 17
        static let iconGap: CGFloat = 10
    }

    private enum Timing {
        /// The keyboard's own move, for the notes that carry no duration.
        static let keyboardMove: TimeInterval = 0.25
    }

    var body: some View {
        HStack(spacing: PillMetrics.iconGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: PillMetrics.icon, weight: .medium))
                .imageScale(.medium)
                .foregroundStyle(Palette.textOnMistSecondary)
            TextField(placeholder, text: $text)
                .font(Typography.row)
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { focused = false }
                .accessibilityIdentifier("list.search.field")
        }
        .padding(.horizontal, PillMetrics.horizontalPadding)
        .frame(height: PillMetrics.height)
        .glassEffect(.regular.interactive(), in: .capsule)
        .offset(y: -keyboardRise)
        .onReceive(keyboardFrames) { note in
            rideKeyboard(note)
        }
    }

    /// The keyboard's coming stands, in screen coordinates, each with the duration its
    /// own move runs.
    private var keyboardFrames: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
    }

    /// Rides the keyboard: the screens the pill sits on ignore the keyboard's safe area —
    /// their mist runs to the bottom edge — so the pill carries itself up by the keys'
    /// stand, keeping its foot clearance above them.
    @MainActor
    private func rideKeyboard(_ note: Notification) {
        guard
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let screen = footScreen
        else { return }
        let rawDuration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
        let duration = (rawDuration as? Double) ?? Timing.keyboardMove
        withAnimation(.easeInOut(duration: duration)) {
            keyboardRise = max(0, screen.bounds.height - frame.minY)
        }
    }

    /// The screen whose foot the pill sits on: the keyboard's frame is in its coordinates.
    @MainActor
    private var footScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }
}

#Preview {
    struct PillHost: View {
        @State private var text = ""

        var body: some View {
            ZStack {
                MistBackground().ignoresSafeArea()
                VStack {
                    Spacer()
                    BottomSearchPill(placeholder: "Search archived tabs", text: $text)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 26)
                }
            }
        }
    }
    return PillHost()
}
