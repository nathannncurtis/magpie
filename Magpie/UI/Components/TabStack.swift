import SwiftUI

/// Whether a vertical fling carries a card off, as pure arithmetic: past 30% of the
/// card's height, or faster than 500 pt/s. Up is negative for both measures.
enum FlingToClose {
    /// The share of the card's height a drag must pass.
    static let distanceFraction: CGFloat = 0.3
    /// The closing speed, in points per second.
    static let velocityThreshold: CGFloat = 500

    static func closes(translationY: CGFloat, velocityY: CGFloat, cardHeight: CGFloat) -> Bool {
        translationY < -(distanceFraction * cardHeight) || velocityY < -velocityThreshold
    }
}

/// Where every card and label sits, as pure arithmetic on the container's size: the
/// current card centred at 62% of the container, its neighbours a stride away, peeping
/// in past the edges.
enum StackLayout {
    static func stride(containerWidth: CGFloat) -> CGFloat {
        containerWidth * StackMetrics.cardScale + StackMetrics.cardGap
    }

    /// The card's frame for a tab this many strides from the centred one; `drag`
    /// shifts the whole row sideways.
    static func cardFrame(offset: Int, container: CGSize, drag: CGFloat = 0) -> CGRect {
        let cardWidth = container.width * StackMetrics.cardScale
        let cardHeight = container.height * StackMetrics.cardScale
        let centreX = container.width / 2 + CGFloat(offset) * stride(containerWidth: container.width) + drag
        return CGRect(
            x: centreX - cardWidth / 2,
            y: container.height / 2 - cardHeight / 2,
            width: cardWidth,
            height: cardHeight)
    }

    /// The window a label occupies: leading-aligned to its card, clipped by the screen
    /// with it, stopping short of the next card's label.
    static func labelWindow(card: CGRect, nextCardLeading: CGFloat, containerWidth: CGFloat) -> CGRect {
        let leading = max(card.minX + StackMetrics.labelInset, StackMetrics.leadingClamp)
        let trailing = min(
            card.maxX,
            nextCardLeading - StackMetrics.labelInset,
            containerWidth - StackMetrics.trailingBound)
        return CGRect(
            x: leading,
            y: card.minY - StackMetrics.labelGap - StackMetrics.labelSlotHeight,
            width: max(trailing - leading, StackMetrics.labelMinWidth),
            height: StackMetrics.labelSlotHeight)
    }
}

/// The stack's fixed measurements, in points.
private enum StackMetrics {
    /// The card is the page at 62% of the container's scale.
    static let cardScale: CGFloat = 0.62
    /// Cards sit 14 pt apart.
    static let cardGap: CGFloat = 14
    /// A label rides 12 pt above its card, in a 22 pt slot.
    static let labelGap: CGFloat = 12
    static let labelSlotHeight: CGFloat = 22
    /// A label starts this far in from its card's leading edge and stops this far
    /// short of the next card.
    static let labelInset: CGFloat = 6
    /// Where a clipped label may sit from the screen's left and right edges.
    static let leadingClamp: CGFloat = 14
    static let trailingBound: CGFloat = 16
    static let labelMinWidth: CGFloat = 20
    /// A card flies this many card-heights up when it closes.
    static let flyDistance: CGFloat = 1.6
    /// The drag travel that locks the gesture to one axis.
    static let axisLock: CGFloat = 12
    /// The share of a stride a sideways drag must cover to move the stack by one tab.
    static let swipeFraction: CGFloat = 0.25
    /// Cards up to this far from the current one are drawn.
    static let visibleNeighbours = 2
    /// How long a closed card takes to leave, and the crossfade under Reduce Motion.
    static let flightDuration: TimeInterval = 0.35
    static let crossfadeDuration: TimeInterval = 0.2

    static var crossfade: Animation { .easeInOut(duration: crossfadeDuration) }
}

/// The tab cards side by side: the current one centred, its neighbours peeking in from
/// the edges, labels riding above. Swipe sideways to move through the stack, fling the
/// centred card up to close it, tap a peeking neighbour to centre it, tap the centred
/// card to open it.
struct TabStack: View {
    let tabs: [Tab]
    let currentID: Tab.ID?
    var onSelect: (Tab.ID) -> Void
    var onOpen: (Tab.ID) -> Void
    var onClose: (Tab.ID) -> Void
    var snapshotLoader: (Tab.ID) async -> Data?
    var namespace: Namespace.ID? = nil

    @State private var horizontalDrag: CGFloat = 0
    @State private var verticalDrag: CGFloat = 0
    @State private var dragCardID: Tab.ID?
    @State private var lockedAxis: Axis?
    @State private var flyingID: Tab.ID?
    @State private var flyOffset: CGFloat = 0
    @State private var snapshots: [Tab.ID: Data] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let stride = size.width * StackMetrics.cardScale + StackMetrics.cardGap
            let current = currentIndex
            let stack = ZStack {
                ForEach(tabs) { tab in
                    if let index = tabs.firstIndex(where: { $0.id == tab.id }),
                        abs(index - current) <= StackMetrics.visibleNeighbours
                    {
                        card(tab, index: index, current: current, size: size, stride: stride)
                            .transition(.opacity)
                            .task(id: tab.id) { await loadSnapshot(for: tab.id) }
                        label(tab, index: index, current: current, size: size, stride: stride)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: size, stride: stride))

            // Reduce Motion: the stack crossfades between its states instead of sliding.
            if reduceMotion {
                stack.id(currentID).transition(.opacity)
            } else {
                stack
            }
        }
    }

    // MARK: Cards and labels

    private func card(
        _ tab: Tab, index: Int, current: Int, size: CGSize, stride: CGFloat
    ) -> some View {
        let frame = StackLayout.cardFrame(offset: index - current, container: size, drag: horizontalDrag)
        let lift: CGFloat
        if flyingID == tab.id {
            lift = flyOffset
        } else if dragCardID == tab.id {
            lift = verticalDrag
        } else {
            lift = 0
        }
        return TabCard(tab: tab, snapshot: snapshots[tab.id], namespace: namespace)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY + lift)
            .zIndex(Double(100 - abs(index - current)))
            .onTapGesture {
                guard flyingID == nil else { return }
                if tab.id == currentID {
                    onOpen(tab.id)
                } else {
                    withAnimation(reduceMotion ? StackMetrics.crossfade : Springs.settle.animation) {
                        onSelect(tab.id)
                    }
                }
            }
    }

    /// A label rides above its own card, aligned to its leading edge and clipped by the
    /// screen with it when it peeks; it never spills onto the current card's label.
    @ViewBuilder
    private func label(
        _ tab: Tab, index: Int, current: Int, size: CGSize, stride: CGFloat
    ) -> some View {
        if abs(index - current) <= 1 {
            let card = StackLayout.cardFrame(offset: index - current, container: size, drag: horizontalDrag)
            let nextLeading = StackLayout.cardFrame(
                offset: index - current + 1, container: size, drag: horizontalDrag
            ).minX
            let window = StackLayout.labelWindow(
                card: card, nextCardLeading: nextLeading, containerWidth: size.width)
            // Natural width, hard-cut at the window's edge — a peeking label's text runs
            // off the screen with its card rather than folding into an ellipsis.
            TabLabel(title: tab.displayTitle, host: tab.host, faviconData: tab.faviconData)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: window.width, alignment: .leading)
                .clipped()
                .frame(height: window.height, alignment: .bottomLeading)
                .position(x: window.midX, y: window.midY)
                .zIndex(200)
        }
    }

    // MARK: Gestures

    private func dragGesture(size: CGSize, stride: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: StackMetrics.axisLock)
            .onChanged { value in
                dragChanged(value, size: size, stride: stride)
            }
            .onEnded { value in
                dragEnded(value, size: size, stride: stride)
            }
    }

    private func dragChanged(_ value: DragGesture.Value, size: CGSize, stride: CGFloat) {
        guard flyingID == nil, !tabs.isEmpty else { return }
        if lockedAxis == nil {
            if abs(value.translation.width) >= StackMetrics.axisLock {
                lockedAxis = .horizontal
            } else if abs(value.translation.height) >= StackMetrics.axisLock {
                lockedAxis = .vertical
                if let hit = cardID(at: value.startLocation.x, size: size, stride: stride), hit == currentID {
                    dragCardID = hit
                }
            }
        }
        switch lockedAxis {
        case .horizontal:
            horizontalDrag = value.translation.width
        case .vertical:
            if dragCardID != nil { verticalDrag = value.translation.height }
        case nil:
            break
        }
    }

    private func dragEnded(_ value: DragGesture.Value, size: CGSize, stride: CGFloat) {
        switch lockedAxis {
        case .horizontal:
            let step = swipeStep(
                translation: value.translation.width,
                predicted: value.predictedEndTranslation.width,
                stride: stride)
            let target = min(max(currentIndex + step, 0), tabs.count - 1)
            withAnimation(reduceMotion ? StackMetrics.crossfade : Springs.settle.animation) {
                if step != 0, tabs.indices.contains(target) {
                    let id = tabs[target].id
                    if id != currentID { onSelect(id) }
                }
                horizontalDrag = 0
            }
        case .vertical:
            endVerticalDrag(value, size: size)
        case nil:
            break
        }
        lockedAxis = nil
        dragCardID = nil
    }

    private func endVerticalDrag(_ value: DragGesture.Value, size: CGSize) {
        guard let id = dragCardID else { return }
        let cardHeight = size.height * StackMetrics.cardScale
        if FlingToClose.closes(
            translationY: verticalDrag, velocityY: value.velocity.height, cardHeight: cardHeight)
        {
            close(id, cardHeight: cardHeight)
        } else {
            withAnimation(reduceMotion ? nil : Springs.settle.animation) {
                verticalDrag = 0
            }
        }
    }

    /// The card follows the finger, then flies off; the next card slides over with settle.
    private func close(_ id: Tab.ID, cardHeight: CGFloat) {
        if reduceMotion {
            withAnimation(StackMetrics.crossfade) { onClose(id) }
            verticalDrag = 0
            return
        }
        flyOffset = verticalDrag
        flyingID = id
        withAnimation(Springs.chrome.animation) {
            flyOffset = -(cardHeight * StackMetrics.flyDistance)
        }
        Task {
            try? await Task.sleep(for: .seconds(StackMetrics.flightDuration))
            withAnimation(Springs.settle.animation) { onClose(id) }
            flyingID = nil
            flyOffset = 0
        }
    }

    private func swipeStep(translation: CGFloat, predicted: CGFloat, stride: CGFloat) -> Int {
        let threshold = stride * StackMetrics.swipeFraction
        if translation <= -threshold || predicted <= -threshold { return 1 }
        if translation >= threshold || predicted >= threshold { return -1 }
        return 0
    }

    private func cardID(at x: CGFloat, size: CGSize, stride: CGFloat) -> Tab.ID? {
        let index = currentIndex + Int(((x - size.width / 2) / stride).rounded())
        return tabs.indices.contains(index) ? tabs[index].id : nil
    }

    private var currentIndex: Int {
        if let currentID, let index = tabs.firstIndex(where: { $0.id == currentID }) {
            return index
        }
        return 0
    }

    // MARK: Snapshots

    private func loadSnapshot(for id: Tab.ID) async {
        guard snapshots[id] == nil, let data = await snapshotLoader(id) else { return }
        snapshots[id] = data
    }
}
