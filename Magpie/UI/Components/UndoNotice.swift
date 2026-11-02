import SwiftUI

/// A deletion just made, on offer for an undo until it runs out. The lists share it: a
/// swipe removes at once, and this puts the row back.
struct UndoNotice: Identifiable {
    let id = UUID()
    /// "Deleted", "Removed": what the capsule says.
    let title: String
    /// Puts back what the swipe took.
    let undo: () -> Void

    static func deleted(undo: @escaping () -> Void) -> UndoNotice {
        UndoNotice(title: UndoCopy.deleted, undo: undo)
    }

    static func removed(undo: @escaping () -> Void) -> UndoNotice {
        UndoNotice(title: UndoCopy.removed, undo: undo)
    }
}

/// The undo capsule's words for the lists.
enum UndoCopy {
    static let deleted = String(localized: "Deleted")
    static let removed = String(localized: "Removed")

    /// What VoiceOver reads for the whole capsule.
    static func label(_ title: String) -> String {
        String(localized: "\(title). Undo")
    }
}

/// How long the capsule stays up, and where it sits.
enum UndoNoticeMetrics {
    static let duration: Duration = .seconds(4)
    /// The gap above a bottom search pill, for the lists that carry one.
    static let abovePill: CGFloat = Metrics.Bar.bottomSearchPillHeight + 14
}

private struct UndoNoticeModifier: ViewModifier {
    @Binding var notice: UndoNotice?
    let bottomInset: CGFloat
    let lift: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let notice {
                    UndoCapsule(
                        title: notice.title,
                        accessibilityLabel: UndoCopy.label(notice.title),
                        identifier: "undo.capsule"
                    ) {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.settle.animation) {
                            notice.undo()
                            self.notice = nil
                        }
                    }
                    .padding(.bottom, Metrics.Spacing.barBottomEdge(safeAreaBottom: bottomInset) + lift)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                    .id(notice.id)
                    .task {
                        try? await Task.sleep(for: UndoNoticeMetrics.duration)
                        guard !Task.isCancelled else { return }
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.chrome.animation) {
                            if self.notice?.id == notice.id { self.notice = nil }
                        }
                    }
                }
            }
            .animation(Springs.chrome.animation, value: notice?.id)
            // Leaving the screen lets the deletion stand.
            .onDisappear { notice = nil }
    }
}

extension View {
    /// The "Deleted · Undo" capsule over the list's foot while `notice` is set. `lift`
    /// holds it clear of a bottom search pill.
    func undoNotice(
        _ notice: Binding<UndoNotice?>, bottomInset: CGFloat, lift: CGFloat = 0
    ) -> some View {
        modifier(UndoNoticeModifier(notice: notice, bottomInset: bottomInset, lift: lift))
    }
}
