import Foundation
import UIKit

/// Fixed Skim material for previews and the UI tests: the board's finished
/// page, with local photo files standing in for its sources' images. Nothing
/// here touches the network.
enum SkimFixture {

    static let query = "seasoning carbon steel"
    static let hosts = ["seriouseats.com", "debuyer.com", "reddit.com"]

    private static let sourcePages: [(host: String, title: String)] = [
        ("seriouseats.com", "How to season a carbon steel pan"),
        ("debuyer.com", "Caring for your Mineral B pan"),
        ("reddit.com", "Carbon steel after two years"),
    ]

    /// The board's finished page; `photoCount` of its sources carry a photo.
    static func page(photoCount: Int) -> SkimPage {
        let sources = sourcePages.enumerated().map { index, source in
            SkimSourceRef(
                url: URL(string: "https://\(source.host)/\(index + 1)")
                    ?? URL(fileURLWithPath: "/"),
                title: source.title,
                host: source.host,
                faviconURL: nil,
                imageURL: index < photoCount ? photoFile(index: index) : nil)
        }
        return SkimPage(
            query: query,
            title: "Seasoning carbon steel",
            sections: [
                SkimSection(
                    emoji: "🔥", term: "Method",
                    claim:
                        "Wipe on a very thin coat of oil, then heat until it stops smoking. Repeat three or four times.",
                    citations: [1, 3]),
                SkimSection(
                    emoji: "🫒", term: "Oil",
                    claim: "Any high smoke-point oil works; flaxseed looks great and flakes within weeks.",
                    citations: [1]),
                SkimSection(
                    emoji: "🍳", term: "First pans",
                    claim: "De Buyer ships with a beeswax coat; scrub it off with hot water first.",
                    citations: [2]),
                SkimSection(
                    emoji: "💧", term: "Upkeep",
                    claim: "No soaking. Dry it on the heat, then a drop of oil.",
                    citations: [1, 2]),
            ],
            sources: sources)
    }

    /// A local photo file standing in for one source's image.
    static func photoFile(index: Int) -> URL? {
        let palettes: [(top: UInt32, bottom: UInt32)] = [
            (0x9A6B48, 0x5A3A26),  // a pan, browned
            (0xCFD3D6, 0x5D656B),  // steel, cool
            (0xE8A04C, 0x8C5A2B),  // a flame, amber
        ]
        let palette = palettes[index % palettes.count]
        let size = CGSize(width: 1200, height: 1524)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor(rgb: palette.top).cgColor, UIColor(rgb: palette.bottom).cgColor,
            ]
            guard
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors as CFArray,
                    locations: [0, 1])
            else { return }
            cg.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: [])
            cg.setFillColor(UIColor(white: 1, alpha: 0.08).cgColor)
            cg.fillEllipse(in: CGRect(x: 240, y: 560, width: 720, height: 720))
            cg.setFillColor(UIColor(white: 0, alpha: 0.10).cgColor)
            cg.fillEllipse(in: CGRect(x: 400, y: 720, width: 400, height: 400))
        }
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skim-fixture-\(index).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}
