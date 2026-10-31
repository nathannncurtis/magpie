import SwiftUI

/// The pieces Settings and its pages are built from (03 · Settings): the grouped box,
/// its rows, the icon square, and the toggle row. The icon square and the chevron are
/// the menu's too; the menu's groups, rows and toggle rows are its own.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: Metrics.Radius.boxGrouped, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.boxGrouped, style: .continuous)
                .strokeBorder(Palette.groupHairline, lineWidth: 0.75)
        )
        // The box's 16 from the screen's edges; the rows and their hairlines run the
        // box's width, no wider.
        .padding(.horizontal, Metrics.Spacing.insetList)
    }
}

/// What a row's icon square shows: an SF Symbol, the mark, the drawn cookie, an engine's
/// favicon, or the Other engine's plus glyph.
enum SettingsIcon {
    case symbol(String)
    case mark
    case cookie
    case favicon(String)
    case otherEngine
}

/// One row of a Settings group: an icon square, a title, and what trails — a value with a
/// chevron, a toggle, or nothing. 46 tall; `.divided()` draws the hairline above it that
/// separates it from the row before.
struct SettingsRow<Trailing: View>: View {
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
                        .fill(Palette.separatorOnMist)
                        .frame(height: 0.5)
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
        SettingsRowFace(icon: icon, title: title, trailing: trailing)
            .frame(minHeight: Metrics.Spacing.rowSettings)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }

    /// Draws the hairline above this row.
    func divided(_ divided: Bool = true) -> Self {
        var copy = self
        copy.isDivided = divided
        return copy
    }

    /// Makes the row a tappable one.
    func action(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.onTap = action
        return copy
    }
}

/// What a Settings row's face holds: the icon square, the label, then what trails. The
/// plain row and the toggle row wear it alike.
private struct SettingsRowFace<Trailing: View>: View {
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

/// The row's 30 pt ink square with its on-ink icon (01 Icons).
struct IconSquare: View {
    let icon: SettingsIcon

    var body: some View {
        Group {
            if case .favicon(let name) = icon {
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.faviconMedium, style: .continuous))
                    .frame(width: 30, height: 30, alignment: .center)
            } else if case .otherEngine = icon {
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.Radius.iconSquareSmall, style: .continuous)
                        .fill(Palette.fill)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                }
                .frame(width: 30, height: 30)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.Radius.iconSquareSmall, style: .continuous)
                        .fill(Palette.ink)
                    iconView
                        .foregroundStyle(Palette.onInk)
                }
                .frame(width: 30, height: 30)
            }
        }
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 16, weight: .medium))
                .imageScale(.medium)
        case .mark:
            Mark(size: 18, style: .solid)
        case .cookie:
            CookieIcon()
                .frame(width: 16, height: 16)
        case .favicon, .otherEngine:
            EmptyView()
        }
    }
}

/// The cookie, drawn (01 Icons: no symbol fits; a 2 pt stroke on a 24-unit grid).
struct CookieIcon: View {
    var body: some View {
        ZStack {
            CookieShape()
                .stroke(style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            CookieDots()
                .fill()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The cookie outline: a 270-degree circle whose missing corner is bitten away by two
/// small arcs, traced in a 24-unit space.
struct CookieShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height) / 24
        let point = { (x: CGFloat, y: CGFloat) in
            CGPoint(x: rect.minX + x * side, y: rect.minY + y * side)
        }
        var path = Path()
        path.move(to: point(20, 12))
        path.addArc(
            center: point(12, 12), radius: 8 * side,
            startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
        path.addArc(
            center: point(13.293, 6.707), radius: 3 * side,
            startAngle: .degrees(244.5), endAngle: .degrees(25.5), clockwise: false)
        path.addArc(
            center: point(17.293, 10.707), radius: 3 * side,
            startAngle: .degrees(244.5), endAngle: .degrees(25.5), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The cookie's chips, in the same 24-unit space.
struct CookieDots: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height) / 24
        let point = { (x: CGFloat, y: CGFloat) in
            CGPoint(x: rect.minX + x * side, y: rect.minY + y * side)
        }
        var path = Path()
        for center in [point(9, 10), point(14, 15), point(9, 15)] {
            path.addEllipse(
                in: CGRect(
                    x: center.x - 1.2 * side, y: center.y - 1.2 * side,
                    width: 2.4 * side, height: 2.4 * side))
        }
        return path
    }
}

/// A row whose whole face flips the switch at its end (03 · Settings): the system
/// `Toggle`, tinted `toggleOn`, carrying the row's icon square and label as its own
/// label, so a tap anywhere from the icon to the switch flips it. `.divided()` draws
/// the hairline above it, as on the other rows.
struct SettingsToggleRow: View {
    let icon: SettingsIcon
    let title: String
    let isOn: Binding<Bool>
    var isDivided = false

    var body: some View {
        Toggle(isOn: isOn) {
            SettingsRowFace(icon: icon, title: title) { EmptyView() }
                .frame(minHeight: Metrics.Spacing.rowSettings)
                .contentShape(.rect)
                // The switch alone answers a tap on its own; the row's face flips it too.
                .onTapGesture { isOn.wrappedValue.toggle() }
        }
        .toggleStyle(.switch)
        .tint(Palette.toggleOn)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if isDivided {
                Rectangle()
                    .fill(Palette.separatorOnMist)
                    .frame(height: 0.5)
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

/// The chevron after a row's value.
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.textOnMistSecondaryMeta)
    }
}

/// The checkmark on a Settings list's chosen row: decoration only — the row's
/// `isSelected` trait carries the choice to VoiceOver.
struct SettingsCheckmark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .accessibilityHidden(true)
    }
}

/// An uppercase section label above a group.
struct SettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.labelOnMist)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Metrics.Spacing.insetList + 4)
            .padding(.trailing, Metrics.Spacing.insetList)
            .padding(.top, Metrics.Spacing.gapSectionTop)
            .padding(.bottom, Metrics.Spacing.gapSectionBottom)
            .accessibilityAddTraits(.isHeader)
    }
}
