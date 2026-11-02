import SwiftUI
import WidgetKit

/// The search widgets: the mark and a Search pill, on the home screen (small, medium) and
/// the lock screen (accessory). A tap anywhere opens Magpie's search sheet.
@main
struct MagpieWidgetBundle: WidgetBundle {
    var body: some Widget {
        SearchWidget()
    }
}

struct SearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.magpiebrowser.Magpie.search", provider: SearchProvider()) { _ in
            SearchWidgetView()
        }
        .configurationDisplayName("Search")
        .description("Search from your home screen or lock screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

/// One entry, forever: the widget never changes.
struct SearchEntry: TimelineEntry {
    let date = Date.now
}

struct SearchProvider: TimelineProvider {
    func placeholder(in context: Context) -> SearchEntry { SearchEntry() }

    func getSnapshot(in context: Context, completion: @escaping (SearchEntry) -> Void) {
        completion(SearchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SearchEntry>) -> Void) {
        completion(Timeline(entries: [SearchEntry()], policy: .never))
    }
}

struct SearchWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(URL(string: "magpie://search"))
            .containerBackground(for: .widget) { WidgetPalette.paper }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 16) {
                WidgetMark(size: 56, style: .sheen)
                    .foregroundStyle(WidgetPalette.ink)
                SearchPill(height: 44)
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                WidgetMark(size: 30, style: .solid)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                WidgetMark(size: 24, style: .solid)
                Label("Search", systemImage: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            }
            .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetMark(size: 44, style: .sheen)
                    .foregroundStyle(WidgetPalette.ink)
                Spacer(minLength: 8)
                SearchPill(height: 34)
            }
        }
    }
}

/// The "Search" pill: a capsule on the paper with a glass-like fill and a magnifier.
private struct SearchPill: View {
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
            Text("Search")
            Spacer(minLength: 0)
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(WidgetPalette.pillText)
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(WidgetPalette.pill, in: .capsule)
    }
}

/// The values below are copied from the app's palette (Magpie/Theme/Colors.swift): a
/// widget cannot import the app module. Keep them in step with it.
enum WidgetPalette {
    /// `Palette.paper`.
    static let paper = dynamic(light: 0xF6F5F1, dark: 0x121316)
    /// `Palette.ink`.
    static let ink = dynamic(light: 0x101115, dark: 0xF6F5F1)
    /// `Palette.textOnMistSecondary`.
    static let pillText = dynamic(light: 0x3F4B48, dark: 0xA9B9B5)
    /// `Palette.separatorOnMist`, the quiet fill a pill sits on.
    static let pill = dynamic(light: 0x102824, lightOpacity: 0.08, dark: 0xFFFFFF, darkOpacity: 0.07)
    /// `Palette.sheen`.
    static let sheen = LinearGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: Color(hex: 0x0D9488), location: 0),
            Gradient.Stop(color: Color(hex: 0x10B981), location: 0.55),
            Gradient.Stop(color: Color(hex: 0x6EE7B7), location: 1),
        ]),
        startPoint: .topLeading, endPoint: .bottomTrailing)

    private static func dynamic(
        light: UInt32, lightOpacity: Double = 1, dark: UInt32, darkOpacity: Double = 1
    ) -> Color {
        Color(
            uiColor: UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                return UIColor(
                    Color(
                        hex: isDark ? dark : light,
                        opacity: isDark ? darkOpacity : lightOpacity))
            })
    }
}

extension Color {
    /// An sRGB colour from a 0xRRGGBB value, at the given opacity.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

/// Where the mark's artwork lands in a frame.
enum WidgetMarkGeometry {
    static let bounds: CGRect = {
        let brush = MarkPath.brushPath().boundingRect
        let gap = CGRect(
            x: MarkPath.dryGapCenter.x - MarkPath.dryGapRadius,
            y: MarkPath.dryGapCenter.y - MarkPath.dryGapRadius,
            width: MarkPath.dryGapRadius * 2, height: MarkPath.dryGapRadius * 2)
        let bead = CGRect(
            x: MarkPath.beadCenter.x - MarkPath.beadRadius,
            y: MarkPath.beadCenter.y - MarkPath.beadRadius,
            width: MarkPath.beadRadius * 2, height: MarkPath.beadRadius * 2)
        return brush.union(gap).union(bead)
    }()

    static func transform(into rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / max(bounds.width, 1), rect.height / max(bounds.height, 1))
        return CGAffineTransform(
            translationX: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale
        ).scaledBy(x: scale, y: scale)
    }
}

/// The Magpie mark, drawn from the same artwork as the app's (Magpie/UI/Components/Mark.swift):
/// the brush in the current colour, the bead in the sheen or the current colour.
struct WidgetMark: View {
    enum Style { case sheen, solid }

    let size: CGFloat
    let style: Style

    var body: some View {
        ZStack {
            Brush()
            if style == .sheen {
                Bead().fill(WidgetPalette.sheen)
            } else {
                Bead()
            }
        }
        .frame(width: size, height: size)
    }

    private struct Brush: Shape {
        func path(in rect: CGRect) -> Path {
            let transform = WidgetMarkGeometry.transform(into: rect)
            var path = MarkPath.brushPath().applying(transform)
            path.addPath(
                Path(
                    ellipseIn: CGRect(
                        x: MarkPath.dryGapCenter.x - MarkPath.dryGapRadius,
                        y: MarkPath.dryGapCenter.y - MarkPath.dryGapRadius,
                        width: MarkPath.dryGapRadius * 2, height: MarkPath.dryGapRadius * 2)
                ).applying(transform))
            return path
        }
    }

    private struct Bead: Shape {
        func path(in rect: CGRect) -> Path {
            let transform = WidgetMarkGeometry.transform(into: rect)
            let center = MarkPath.beadCenter.applying(transform)
            let radius = MarkPath.beadRadius * transform.a
            return Path(
                ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
    }
}

/// `MarkPath.brushPath()` lives in the app's Mark.swift; the widget builds the same path.
extension MarkPath {
    static func brushPath() -> Path {
        var path = Path()
        for subpath in brush {
            guard let first = subpath.first else { continue }
            path.move(to: first)
            for point in subpath.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }
}
