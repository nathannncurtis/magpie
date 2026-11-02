import SwiftUI

/// One soft radial blob of mist.
private struct MistBlob: Sendable {
    /// The blob's centre, as fractions of the drawing size.
    let center: CGPoint
    /// The blob's radii, as fractions of the drawing size.
    let radii: CGSize
    /// Where the colour reaches fully clear, as a fraction of the radii.
    let fade: CGFloat
    let lightHex: UInt32
    let lightOpacity: Double
    let darkHex: UInt32
    let darkOpacity: Double

    func color(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hex: darkHex, opacity: darkOpacity)
            : Color(hex: lightHex, opacity: lightOpacity)
    }
}

/// The mist layers: a base gradient with four blobs, plus the two drifting layers.
private enum MistSpec {
    static func baseTop(for scheme: ColorScheme, night: Bool) -> Color {
        if night { return Palette.nightInk }
        return scheme == .dark ? Color(hex: 0x0E1614) : Color(hex: 0xF2F5F2)
    }

    static func baseBottom(for scheme: ColorScheme, night: Bool) -> Color {
        if night { return Palette.nightInkDeep }
        return scheme == .dark ? Color(hex: 0x090D0C) : Color(hex: 0xE3ECE8)
    }

    /// How much of the teal shows through the night mist: a faint glow on ink.
    static let nightGlow = 0.45

    static let still: [MistBlob] = [
        MistBlob(
            center: CGPoint(x: 0.22, y: 0.12), radii: CGSize(width: 0.55, height: 0.38), fade: 0.70,
            lightHex: 0x6EE7B7, lightOpacity: 0.55, darkHex: 0x10B981, darkOpacity: 0.30),
        MistBlob(
            center: CGPoint(x: 0.92, y: 0.30), radii: CGSize(width: 0.60, height: 0.45), fade: 0.72,
            lightHex: 0x0D9488, lightOpacity: 0.38, darkHex: 0x0D9488, darkOpacity: 0.34),
        MistBlob(
            center: CGPoint(x: 0.10, y: 0.70), radii: CGSize(width: 0.70, height: 0.50), fade: 0.72,
            lightHex: 0x10B981, lightOpacity: 0.28, darkHex: 0x10B981, darkOpacity: 0.16),
        MistBlob(
            center: CGPoint(x: 0.85, y: 0.88), radii: CGSize(width: 0.80, height: 0.55), fade: 0.75,
            lightHex: 0x0D9488, lightOpacity: 0.30, darkHex: 0x0D9488, darkOpacity: 0.26),
    ]

    static let driftFast: [MistBlob] = [
        MistBlob(
            center: CGPoint(x: 0.30, y: 0.35), radii: CGSize(width: 0.28, height: 0.22), fade: 0.70,
            lightHex: 0x6EE7B7, lightOpacity: 0.55, darkHex: 0x10B981, darkOpacity: 0.30),
        MistBlob(
            center: CGPoint(x: 0.72, y: 0.62), radii: CGSize(width: 0.32, height: 0.26), fade: 0.72,
            lightHex: 0x0D9488, lightOpacity: 0.36, darkHex: 0x0D9488, darkOpacity: 0.32),
    ]

    static let driftSlow: [MistBlob] = [
        MistBlob(
            center: CGPoint(x: 0.62, y: 0.30), radii: CGSize(width: 0.30, height: 0.24), fade: 0.70,
            lightHex: 0x10B981, lightOpacity: 0.30, darkHex: 0x0D9488, darkOpacity: 0.26),
        MistBlob(
            center: CGPoint(x: 0.36, y: 0.72), radii: CGSize(width: 0.26, height: 0.22), fade: 0.72,
            lightHex: 0x6EE7B7, lightOpacity: 0.40, darkHex: 0x10B981, darkOpacity: 0.20),
    ]
}

/// One end state of a drift loop.
private struct DriftTransform: Equatable {
    /// Horizontal travel, as a fraction of the width (within ±6%).
    var dx: CGFloat
    /// Vertical travel, as a fraction of the height (within ±6%).
    var dy: CGFloat
    /// Rotation, in degrees (within ±9).
    var angle: Double
    /// Scale (within 1.0-1.1).
    var scale: CGFloat

    static let fastFrom = DriftTransform(dx: -0.06, dy: -0.03, angle: -9, scale: 1.0)
    static let fastTo = DriftTransform(dx: 0.06, dy: 0.03, angle: 9, scale: 1.1)
    static let slowFrom = DriftTransform(dx: 0.06, dy: 0.04, angle: 9, scale: 1.1)
    static let slowTo = DriftTransform(dx: -0.06, dy: -0.04, angle: -9, scale: 1.0)
}

/// One drifting layer of blobs, eased between its two end transforms.
private struct DriftLayer: View {
    let blobs: [MistBlob]
    let scheme: ColorScheme
    let size: CGSize
    let from: DriftTransform
    let to: DriftTransform
    let active: Bool

    private var transform: DriftTransform { active ? to : from }

    var body: some View {
        Canvas { context, _ in
            drawMistBlobs(blobs, of: scheme, in: &context, size: size)
        }
        .scaleEffect(transform.scale)
        .rotationEffect(.degrees(transform.angle))
        .offset(x: transform.dx * size.width, y: transform.dy * size.height)
    }
}

/// Fills the context with each blob's colour, clear at the blob's fade point.
private func drawMistBlobs(
    _ blobs: [MistBlob], of scheme: ColorScheme, in context: inout GraphicsContext, size: CGSize,
    glow: Double = 1
) {
    for blob in blobs {
        let color = blob.color(for: scheme).opacity(glow)
        // A copy carries its own transform, so each blob draws in its own unit space.
        var blobContext = context
        blobContext.transform = CGAffineTransform(
            translationX: blob.center.x * size.width, y: blob.center.y * size.height
        ).scaledBy(x: blob.radii.width * size.width, y: blob.radii.height * size.height)
        blobContext.fill(
            Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
            with: .radialGradient(
                Gradient(colors: [color, color.opacity(0)]),
                center: CGPoint(x: 0, y: 0),
                startRadius: 0,
                endRadius: blob.fade
            ))
    }
}

/// The teal backdrop behind the launch screen, tabs, Skim working, Welcome, the engine picker,
/// Archive, Bookmarks, Settings and Mods: a base gradient with four soft radial blobs on top.
struct MistBackground: View {
    /// Skim working only: two extra blob layers drift in a slow loop. Off under Reduce Motion.
    var drifting = false
    /// Skim no-photo tier: the mist is masked over its height so it melts into the page.
    var fadesIntoPage = false
    /// The private look: ink with a faint teal glow, the same in light and dark.
    var night = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fastDriftActive = false
    @State private var slowDriftActive = false

    /// The scheme the blobs are drawn in: night is always the dark one.
    private var scheme: ColorScheme { night ? .dark : colorScheme }

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: fadesIntoPage ? Metrics.Mist.fadeHeight : geo.size.height)
            ZStack {
                Canvas { context, _ in
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .linearGradient(
                            Gradient(colors: [
                                MistSpec.baseTop(for: scheme, night: night),
                                MistSpec.baseBottom(for: scheme, night: night),
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        ))
                    drawMistBlobs(
                        MistSpec.still, of: scheme, in: &context, size: size,
                        glow: night ? MistSpec.nightGlow : 1)
                }
                .frame(width: size.width, height: size.height)
                if drifting && !reduceMotion {
                    DriftLayer(
                        blobs: MistSpec.driftFast, scheme: scheme, size: size,
                        from: .fastFrom, to: .fastTo, active: fastDriftActive)
                    DriftLayer(
                        blobs: MistSpec.driftSlow, scheme: scheme, size: size,
                        from: .slowFrom, to: .slowTo, active: slowDriftActive)
                }
            }
            .frame(width: geo.size.width, height: size.height, alignment: .top)
            .mask(alignment: .top) {
                if fadesIntoPage {
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: .black, location: 0.30),
                            Gradient.Stop(color: .black.opacity(0.45), location: 0.60),
                            Gradient.Stop(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Metrics.Mist.fadeHeight)
                } else {
                    Color.black
                }
            }
        }
        .onAppear { startDrift() }
    }

    /// Eases both drift layers between their end transforms, each on its own period.
    private func startDrift() {
        guard drifting, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
            fastDriftActive = true
        }
        withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
            slowDriftActive = true
        }
    }
}

#Preview("Mist") {
    MistBackground()
        .ignoresSafeArea()
}

#Preview("Night") {
    MistBackground(night: true)
        .ignoresSafeArea()
}

#Preview("Drifting") {
    MistBackground(drifting: true)
        .ignoresSafeArea()
}

#Preview("Fading into the page") {
    MistBackground(fadesIntoPage: true)
        .ignoresSafeArea()
}
