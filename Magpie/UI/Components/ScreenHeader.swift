import SwiftUI

private enum HeaderMetrics {
    /// The control row's height. The 44 pt targets in it spill 4 pt past each edge.
    static let controlRow: CGFloat = 36
    static let titleTop: CGFloat = 2
    static let titleBottom: CGFloat = 10
}

/// The head of every secondary screen: a 36 pt row of controls (something leading, a Done
/// trailing), and under it the title. The title sits at the same height on every screen,
/// so moving between Archive, Bookmarks, Mods and Settings never shifts it.
struct ScreenHeader<Leading: View, Trailing: View>: View {
    /// Nil for a screen that has its own title, such as the Skim page: the control row
    /// stands alone.
    let title: String?
    var titleID: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String?,
        titleID: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.titleID = titleID
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading()
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, Metrics.Spacing.insetList)
            .frame(height: HeaderMetrics.controlRow)
            // Rides above the title, so the targets' spill stays tappable.
            .zIndex(1)
            if let title {
                Text(title)
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.Spacing.insetList)
                    .padding(.top, HeaderMetrics.titleTop)
                    .padding(.bottom, HeaderMetrics.titleBottom)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleID ?? "screen.title")
            }
        }
        .readableWidth()
    }
}

/// A text control in a header's row: Done, Edit, Save. The label sits flush with the
/// header's inset on its own side, inside a 44 pt target.
struct HeaderTextButton: View {
    let title: String
    var edge: HorizontalAlignment = .trailing
    var id: String
    /// Over a photo, the label rides a glass capsule so it stays readable.
    var onGlass = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .frame(
                    minWidth: Metrics.tapTarget, minHeight: Metrics.tapTarget,
                    alignment: edge == .leading ? .leading : .trailing
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private var label: some View {
        let text = Text(title)
            .font(Typography.buttonPill)
            .foregroundStyle(Palette.textPrimary)
        if onGlass {
            text
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
        } else {
            text
        }
    }
}

/// The Done at a header's trailing edge: leaves the screen, as the back swipe does.
struct HeaderDoneButton: View {
    var id: String
    var onGlass = false
    var action: () -> Void

    var body: some View {
        HeaderTextButton(
            title: String(localized: "Done"), edge: .trailing, id: id, onGlass: onGlass,
            action: action)
    }
}

/// The back chevron at a header's leading edge.
struct HeaderBackButton: View {
    var id: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(Typography.icon(.regular))
                .foregroundStyle(Palette.textPrimary)
                .frame(
                    minWidth: Metrics.tapTarget, minHeight: Metrics.tapTarget, alignment: .leading
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Back"))
        .accessibilityIdentifier(id)
    }
}

#Preview {
    ZStack {
        MistBackground().ignoresSafeArea()
        VStack {
            ScreenHeader(
                title: "Bookmarks",
                leading: { HeaderTextButton(title: "Edit", edge: .leading, id: "e") {} },
                trailing: { HeaderDoneButton(id: "d") {} })
            Spacer()
        }
    }
}
