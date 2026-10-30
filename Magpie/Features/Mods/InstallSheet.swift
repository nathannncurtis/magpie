import SwiftUI
import UIKit

/// The install-from-URL sheet (04 · 12, 04 · 17): paste a link, Magpie reads it, shows
/// where the mod runs and what it can do, and says plainly that it isn't reviewed. The
/// install itself is the moment in 05 · 06: press, the mark drawing while the install
/// runs, the tick, the sheet dropping away, and the confirmation row landing behind it.
struct InstallSheet: View {

    /// Layout numbers from the board.
    private enum Layout {
        static let sideInset: CGFloat = 16
        static let titleBottom: CGFloat = 12
        static let fieldHeight: CGFloat = 46
        static let fieldRadius: CGFloat = 14
        static let ringWidth: CGFloat = 1.5
        static let fieldGap: CGFloat = 9
        static let previewRadius = Metrics.Radius.tileSmall
        static let previewPadding: CGFloat = 14
        static let labelWidth: CGFloat = 64
        static let warnRadius: CGFloat = 14
        static let buttonHeight: CGFloat = 50
        static let buttonRadius: CGFloat = 25
        static let buttonsTop: CGFloat = 14
        static let markSide: CGFloat = 24
        static let minimumInstallMs: UInt64 = 600
        static let tickMs: UInt64 = 260
    }

    /// What the sheet is doing.
    private enum Phase: Equatable {
        case idle
        case reading
        case ready(InstallLinkResult)
        case installing
        case ticked
    }

    let onInstall: (ModDraft) -> Void

    @State private var linkText = ""
    @State private var phase: Phase = .idle
    @State private var inspectedURL: URL?
    @State private var readTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()
                .padding(.bottom, 8)
            Text(ModsCopy.installFromURL)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.bottom, Layout.titleBottom)
            field
                .padding(.horizontal, Layout.sideInset)
                .padding(.bottom, 12)
            outcome
            buttons
                .padding(
                    EdgeInsets(
                        top: Layout.buttonsTop, leading: Layout.sideInset,
                        bottom: 0, trailing: Layout.sideInset))
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: linkText) { _, text in
            queueRead(of: text)
        }
    }

    // MARK: The field

    private var field: some View {
        HStack(spacing: Layout.fieldGap) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            TextField(
                String(localized: "example.com/mod.user.js"),
                text: $linkText
            )
            .font(Typography.meta)
            .foregroundStyle(Palette.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.go)
            .focused($fieldFocused)
            .onSubmit { read(linkText) }
            .accessibilityIdentifier("mods.sheet.field")
        }
        .padding(.horizontal, 14)
        .frame(height: Layout.fieldHeight)
        .background(Palette.installURLFill, in: fieldShape)
        .overlay(fieldShape.strokeBorder(Palette.textPrimary, lineWidth: Layout.ringWidth))
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Layout.fieldRadius, style: .continuous)
    }

    // MARK: What came back

    @ViewBuilder
    private var outcome: some View {
        switch phase {
        case .idle, .reading:
            EmptyView()
        case .ready(let result):
            if result.isInstallable {
                preview(result)
                warning
            } else {
                failure(result)
            }
        case .installing, .ticked:
            if let result = readyResult, result.isInstallable {
                preview(result)
                warning
            }
        }
    }

    /// The preview card: what it is, where it runs, what it can do (board's `.x-prev`).
    private func preview(_ result: InstallLinkResult) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ModIcon(spec: previewIcon(result))
                VStack(alignment: .leading, spacing: 1) {
                    Text(previewName(result))
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(previewLine(result))
                        .font(Typography.small)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            permRow(ModsCopy.runsOn, runsOn(result))
            permRow(ModsCopy.can, ModsCopy.pagesPermission)
            if let unsupported = unsupportedGrants(result) {
                permRow(ModsCopy.alsoGrantsLabel, ModsCopy.alsoGrantsValue(unsupported.joined(separator: ", ")))
            }
        }
        .padding(Layout.previewPadding)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Layout.previewRadius, style: .continuous))
        .padding(.horizontal, Layout.sideInset)
        .accessibilityIdentifier("mods.sheet.preview")
    }

    private func permRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Typography.meta.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Layout.labelWidth, alignment: .leading)
            Text(value)
                .font(Typography.meta)
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.separator).frame(height: 1)
        }
    }

    /// Why the link can't install, in a card (04 · 17).
    private func failure(_ result: InstallLinkResult) -> some View {
        let (title, line): (String, String)
        switch result {
        case .webPage:
            (title, line) = (ModsCopy.webPageTitle, ModsCopy.webPageLine)
        case .unreachable:
            (title, line) = (ModsCopy.unreachableTitle, ModsCopy.unreachableLine)
        case .noRunRules:
            (title, line) = (ModsCopy.noRunRulesTitle, ModsCopy.noRunRulesLine)
        case .userscript, .filterList:
            (title, line) = (ModsCopy.webPageTitle, ModsCopy.webPageLine)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(line)
                .font(Typography.meta)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Layout.previewRadius, style: .continuous))
        .padding(.horizontal, Layout.sideInset)
        .accessibilityIdentifier("mods.sheet.failure")
    }

    /// The warning under the preview: nobody has reviewed a link install.
    private var warning: some View {
        Text(
            ModsCopy.notInDirectory + " " + ModsCopy.warningLine
        )
        .font(Typography.meta)
        .foregroundStyle(Palette.warningText)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(
            Palette.warningBackground,
            in: RoundedRectangle(cornerRadius: Layout.warnRadius, style: .continuous)
        )
        .padding(.horizontal, Layout.sideInset)
        .padding(.top, 12)
        .accessibilityIdentifier("mods.sheet.warning")
    }

    // MARK: The buttons

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(ModsCopy.cancel) { dismiss() }
                .font(Typography.buttonPill)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.buttonHeight)
                .background(Palette.fill, in: Capsule())
                .accessibilityIdentifier("mods.sheet.cancel")
            installButton
        }
    }

    private var installButton: some View {
        Button(action: install) {
            Group {
                switch phase {
                case .installing:
                    MarkDrawOn(size: Layout.markSide)
                case .ticked:
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                default:
                    Text(ModsCopy.install)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.buttonHeight)
        }
        .font(Typography.buttonPill)
        .foregroundStyle(Palette.onInk)
        .background(Palette.ink, in: Capsule())
        .opacity(installable ? 1 : 0.3)
        .disabled(!installable)
        .buttonStyle(PressScale())
        .accessibilityIdentifier("mods.sheet.install")
    }

    private var installable: Bool {
        readyResult?.isInstallable == true && !installing
    }

    private var installing: Bool {
        phase == .installing || phase == .ticked
    }

    private var readyResult: InstallLinkResult? {
        if case .ready(let result) = phase { return result }
        return nil
    }

    // MARK: Reading the link

    /// A quiet read once the typing settles; the return key reads at once.
    private func queueRead(of text: String) {
        readTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase = .idle
            return
        }
        readTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            read(text)
        }
    }

    private func read(_ text: String) {
        guard let url = Self.url(from: text) else {
            inspectedURL = nil
            phase = text.isEmpty ? .idle : .ready(.webPage)
            return
        }
        guard url != inspectedURL || readyResult == nil else { return }
        inspectedURL = url
        phase = .reading
        Task { @MainActor in
            let result = await ModLinkInstaller.inspect(url)
            guard inspectedURL == url else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.settle.animation) {
                phase = .ready(result)
            }
        }
    }

    /// A pasted address, completing a missing scheme the way the field's placeholder
    /// suggests.
    private static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full) else { return nil }
        return url.scheme == "http" || url.scheme == "https" ? url : nil
    }

    // MARK: Installing (05 · 06)

    private func install() {
        guard let result = readyResult, result.isInstallable, let url = inspectedURL else { return }
        guard let draft = ModLinkInstaller.draft(from: result, url: url) else { return }
        let started = Date()
        phase = .installing
        Task { @MainActor in
            // The mark draws while the install runs, but never for less than a beat.
            let spentMs = Date().timeIntervalSince(started) * 1000
            if spentMs < Double(Layout.minimumInstallMs) {
                try? await Task.sleep(
                    for: .milliseconds(Double(Layout.minimumInstallMs) - spentMs))
            }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Springs.snap.animation) {
                phase = .ticked
            }
            Self.successHaptic()
            try? await Task.sleep(for: .milliseconds(Double(Layout.tickMs)))
            dismiss()
            onInstall(draft)
        }
    }

    private static func successHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Preview pieces

    private func previewIcon(_ result: InstallLinkResult) -> ModIconSpec {
        if case .userscript = result { return .linkInstall() }
        return ModIconSpec(
            glyph: "line.3.horizontal.decrease.circle.fill", gradient: ["#6F7B8A", "#3E4753"])
    }

    private func previewName(_ result: InstallLinkResult) -> String {
        switch result {
        case .userscript(let script):
            return script.metadata.name ?? inspectedURL.map(ModLinkInstaller.name(from:)) ?? ""
        case .filterList:
            return inspectedURL.map(ModLinkInstaller.name(from:)) ?? ""
        case .noRunRules, .webPage, .unreachable:
            return ""
        }
    }

    private func previewLine(_ result: InstallLinkResult) -> String {
        switch result {
        case .userscript(let script):
            if let author = script.metadata.author {
                return ModsCopy.scriptBy(author, version: script.metadata.version ?? "")
            }
            return ModsCopy.filterListBy(nil)
        case .filterList:
            return ModsCopy.filterListBy(nil)
        case .noRunRules, .webPage, .unreachable:
            return ""
        }
    }

    /// Where the script runs: the @match domains, else its @include patterns.
    private func runsOn(_ result: InstallLinkResult) -> String {
        guard case .userscript(let script) = result else {
            return String(localized: "Every site")
        }
        let domains = script.metadata.matchDomains
        if !domains.isEmpty {
            return domains.joined(separator: ", ")
        }
        let patterns = script.metadata.includes.map { pattern in
            switch pattern.kind {
            case .glob(let glob): return glob
            case .regex(let source): return "/\(source)/"
            }
        }
        return patterns.isEmpty
            ? String(localized: "Every site")
            : ModsCopy.sitesItNames(
                patterns.joined(separator: ", "))
    }

    private func unsupportedGrants(_ result: InstallLinkResult) -> [String]? {
        guard case .userscript(let script) = result else { return nil }
        let unsupported = script.metadata.unsupportedGrants
        return unsupported.isEmpty ? nil : unsupported
    }
}

/// The sheet's grabber: 38 by 5, its own quiet grey.
private struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Palette.grabber)
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }
}

/// The mark drawing itself while an install runs (05 · 06).
private struct MarkDrawOn: View {

    private enum Layout {
        static let strokeWidth: CGFloat = 2.4
        static let pass: Double = 1.1
    }

    var size: CGFloat

    @State private var progress: CGFloat = 0

    var body: some View {
        Centreline()
            .trim(from: 0, to: progress)
            .stroke(
                Palette.onInk,
                style: StrokeStyle(lineWidth: Layout.strokeWidth, lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
            .onAppear {
                Task { @MainActor in
                    while !Task.isCancelled {
                        progress = 0
                        withAnimation(.linear(duration: Layout.pass)) {
                            progress = 1
                        }
                        try? await Task.sleep(for: .seconds(Layout.pass))
                    }
                }
            }
            .accessibilityLabel(Text(String(localized: "Installing")))
    }

    /// The mark's centreline, fitted into the frame.
    private struct Centreline: Shape {
        func path(in rect: CGRect) -> Path {
            MarkGeometry.centreline().applying(MarkGeometry.transform(into: rect))
        }
    }
}

/// The press the install carries: a small settle to 0.96 while held.
private struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : Springs.settle.animation,
                value: configuration.isPressed)
    }
}
