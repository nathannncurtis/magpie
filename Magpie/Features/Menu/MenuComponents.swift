import SwiftUI

/// The pieces the menu is built from (03 · Menu): the grabber, the quick-action tiles,
/// the groups and their rows. The icon square and the chevron come from Settings'
/// pieces, so the two screens read as one.
///
/// The menu's numbers: rows 50 tall, groups inset 14 with radius 20, tiles at least 64
/// tall with radius 18, gaps 8 between tiles and 10 between groups.

/// The menu's grabber: 38 by 5, the ink at 18%.
struct MenuGrabber: View {
    var body: some View {
        Capsule()
            .fill(Palette.grabber)
            .frame(width: Metrics.Menu.grabberWidth, height: Metrics.Menu.grabberHeight)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// The menu's quick actions (03 · Menu): equal tiles, side by side.
struct MenuTileRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: Metrics.Spacing.gapTileGrid) {
            content()
        }
        .padding(.horizontal, Metrics.Spacing.insetFloating)
        .padding(.top, Metrics.Menu.tileRowTopPadding)
        .padding(.bottom, Metrics.Menu.tileRowBottomPadding)
    }
}

/// What every tile shows (03 · Menu): the icon over its caption label, on the tile's
/// fill with the inner hairline. The button tiles and the share tile both wear this face.
struct MenuTileFace<Icon: View>: View {
    let title: String
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        VStack(spacing: Metrics.Menu.tileIconGap) {
            icon()
            Text(title)
                .font(Typography.tileLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: Metrics.Menu.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.tileSmall, style: .continuous)
                .fill(Palette.menuTile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.tileSmall, style: .continuous)
                .strokeBorder(Palette.menuHairline, lineWidth: 0.75)
        )
        .foregroundStyle(Palette.menuTileLabel)
        .contentShape(.rect)
    }
}

/// A tappable quick-action tile.
struct MenuTile<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            MenuTileFace(title: title, icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

/// A 20 pt symbol at medium weight: what a tile's icon is, when it isn't the mark.
struct MenuTileSymbol: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: Metrics.Menu.tileIconSize, weight: .medium))
            .imageScale(.medium)
    }
}

/// One rounded box of menu rows (03 · Menu), inset from the sheet's sides.
struct MenuGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.boxGrouped, style: .continuous)
                .fill(Palette.menuGroup)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.boxGrouped, style: .continuous)
                .strokeBorder(Palette.menuHairline, lineWidth: 0.75)
        )
        .padding(.horizontal, Metrics.Spacing.insetFloating)
    }
}

/// One row of a menu group: an icon square, the label, and what trails — a toggle or a
/// value with its chevron. At least 50 tall, divided from the row above by a hairline.
struct MenuRow<Trailing: View>: View {
    let icon: SettingsIcon
    let title: String
    var isDivided = false
    var onTap: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        rowContent
            .overlay(alignment: .top) {
                if isDivided {
                    Rectangle()
                        .fill(Palette.separator)
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)
                }
            }
    }

    @ViewBuilder private var rowContent: some View {
        if let onTap {
            Button(action: onTap) { inner }
                .buttonStyle(.plain)
        } else {
            inner
        }
    }

    private var inner: some View {
        MenuRowFace(icon: icon, title: title, trailing: trailing)
            .frame(minHeight: Metrics.Spacing.rowMenu)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }

    /// Makes the row a tappable one.
    func action(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.onTap = action
        return copy
    }

    /// Draws the hairline above this row.
    func divided(_ divided: Bool = true) -> Self {
        var copy = self
        copy.isDivided = divided
        return copy
    }
}

/// What a menu row's face holds: the icon square, the label, then what trails. The plain
/// row, the toggle row and the archive row wear it alike.
private struct MenuRowFace<Trailing: View>: View {
    let icon: SettingsIcon
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconSquare(icon: icon)
            Text(title)
                .font(Typography.row)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 12)
            trailing()
        }
    }
}

/// A menu row whose whole face flips the switch at its end (03 · Menu): the system
/// `Toggle`, tinted `toggleOn`, carrying the row's icon square and label as its own
/// label, so a tap anywhere from the icon to the switch flips it. `.divided()` draws
/// the hairline above it, as on the other rows.
struct MenuToggleRow: View {
    let icon: SettingsIcon
    let title: String
    let isOn: Binding<Bool>
    var isDivided = false

    var body: some View {
        Toggle(isOn: isOn) {
            MenuRowFace(icon: icon, title: title) { EmptyView() }
                .frame(minHeight: Metrics.Spacing.rowMenu)
                .contentShape(.rect)
        }
        .toggleStyle(.switch)
        .tint(Palette.toggleOn)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if isDivided {
                Rectangle()
                    .fill(Palette.separator)
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }
        }
        .accessibilityLabel(title)
    }

    /// Draws the hairline above this row.
    func divided(_ divided: Bool = true) -> Self {
        var copy = self
        copy.isDivided = divided
        return copy
    }
}

/// The archive row (03 · Menu): the whole row opens the interval picker, whose choices
/// are Settings' own; the trailing value's ⌃⌄ says the row picks. `.divided()` draws the
/// hairline above it, as on the other rows.
struct MenuArchiveRow: View {
    let interval: TimeInterval
    let choose: (TimeInterval) -> Void
    var isDivided = false

    var body: some View {
        Menu {
            ForEach(Preferences.archiveIntervalSteps, id: \.self) { step in
                Button(Preferences.archiveIntervalLabel(step)) {
                    choose(step)
                }
            }
        } label: {
            MenuRowFace(icon: .symbol("archivebox"), title: "Archive inactive tabs") {
                HStack(spacing: 6) {
                    Text(String(localized: "After \(Preferences.archiveIntervalLabel(interval))"))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .medium))
                }
                .font(Typography.row)
                .foregroundStyle(Palette.textSecondary)
            }
            .frame(minHeight: Metrics.Spacing.rowMenu)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .overlay(alignment: .top) {
            if isDivided {
                Rectangle()
                    .fill(Palette.separator)
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
            }
        }
    }

    /// Draws the hairline above this row.
    func divided(_ divided: Bool = true) -> Self {
        var copy = self
        copy.isDivided = divided
        return copy
    }
}

/// A row value and the chevron that says the row opens something.
struct MenuValue: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
            SettingsChevron()
        }
        .font(Typography.row)
        .foregroundStyle(Palette.textSecondary)
    }
}
