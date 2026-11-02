import Observation
import SwiftUI
import WebKit

/// What a page's alert, confirm or prompt asks, and what the person answered.
struct PageDialog: Identifiable, Equatable {
    enum Kind: Equatable {
        case alert
        case confirm
        case prompt(defaultText: String)
    }

    /// The person's answer; a prompt's text rides on `ok`.
    enum Answer: Equatable {
        case ok(String)
        case cancel
    }

    let id = UUID()
    let kind: Kind
    let message: String
    /// The site asking, in display form: a dialog always says whose it is.
    let host: String

    /// The alert's title.
    var title: String {
        host.isEmpty ? String(localized: "This page says") : String(localized: "\(host) says")
    }
}

/// The page's dialog presenter: each alert, confirm and prompt waits here until the
/// reading screen's alert answers it, so a page never hangs on a dialog nobody shows.
/// Dialogs queue; one is up at a time.
@MainActor
@Observable
final class PageDialogs: WebPage.DialogPresenting {

    /// The dialog up now, for the screen's alert.
    private(set) var current: PageDialog?
    /// A prompt's text field, kept here so the alert can bind to it.
    var promptText = ""

    @ObservationIgnored private var waiting: [(PageDialog, CheckedContinuation<PageDialog.Answer, Never>)] = []
    @ObservationIgnored private var resolveCurrent: CheckedContinuation<PageDialog.Answer, Never>?

    /// How long the screen's alert gets to leave before the next one is put up.
    private static let betweenDialogs: Duration = .milliseconds(350)

    func handleJavaScriptAlert(message: String, initiatedBy frame: WebPage.FrameInfo) async {
        _ = await ask(.alert, message, frame)
    }

    func handleJavaScriptConfirm(
        message: String, initiatedBy frame: WebPage.FrameInfo
    ) async -> WebPage.JavaScriptConfirmResult {
        await ask(.confirm, message, frame) == .cancel ? .cancel : .ok
    }

    func handleJavaScriptPrompt(
        message: String, defaultText: String?, initiatedBy frame: WebPage.FrameInfo
    ) async -> WebPage.JavaScriptPromptResult {
        switch await ask(.prompt(defaultText: defaultText ?? ""), message, frame) {
        case .ok(let text): return .ok(text)
        case .cancel: return .cancel
        }
    }

    /// The person answered the dialog on screen.
    func answer(_ answer: PageDialog.Answer) {
        guard let continuation = resolveCurrent else { return }
        resolveCurrent = nil
        current = nil
        continuation.resume(returning: answer)
        presentNextSoon()
    }

    /// The page is going away: every dialog it still holds is cancelled, so none of its
    /// scripts stay suspended.
    func cancelAll() {
        let pending = waiting
        waiting = []
        current = nil
        resolveCurrent?.resume(returning: .cancel)
        resolveCurrent = nil
        for (_, continuation) in pending { continuation.resume(returning: .cancel) }
    }

    private func ask(
        _ kind: PageDialog.Kind, _ message: String, _ frame: WebPage.FrameInfo
    ) async -> PageDialog.Answer {
        let host = HostFormatter.host(for: frame.request.url)
        let dialog = PageDialog(kind: kind, message: message, host: host)
        SnapshotLog.event("dialog \(kind)")
        return await withCheckedContinuation { continuation in
            waiting.append((dialog, continuation))
            if current == nil, resolveCurrent == nil { presentNext() }
        }
    }

    private func presentNext() {
        guard current == nil, !waiting.isEmpty else { return }
        let (dialog, continuation) = waiting.removeFirst()
        if case .prompt(let text) = dialog.kind { promptText = text }
        resolveCurrent = continuation
        current = dialog
    }

    /// A beat between two dialogs, so SwiftUI sees the first alert go before the second
    /// comes.
    private func presentNextSoon() {
        guard !waiting.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.betweenDialogs)
            self?.presentNext()
        }
    }
}

/// Puts the page's dialog over the reading screen as an alert.
struct PageDialogAlert: ViewModifier {
    let dialogs: PageDialogs?

    func body(content: Content) -> some View {
        if let dialogs {
            content.modifier(Presenter(dialogs: dialogs))
        } else {
            content
        }
    }

    private struct Presenter: ViewModifier {
        @Bindable var dialogs: PageDialogs

        func body(content: Content) -> some View {
            content.alert(
                dialogs.current?.title ?? "",
                isPresented: Binding(
                    get: { dialogs.current != nil },
                    // Every button answers the dialog itself; nothing dismisses it unanswered.
                    set: { _ in }),
                presenting: dialogs.current
            ) { dialog in
                if case .prompt = dialog.kind {
                    TextField(String(localized: "Answer"), text: $dialogs.promptText)
                        .accessibilityIdentifier("page.dialog.field")
                }
                switch dialog.kind {
                case .alert:
                    Button(String(localized: "OK")) { dialogs.answer(.ok("")) }
                        .accessibilityIdentifier("page.dialog.ok")
                case .confirm, .prompt:
                    Button(String(localized: "Cancel"), role: .cancel) { dialogs.answer(.cancel) }
                    Button(String(localized: "OK")) { dialogs.answer(.ok(dialogs.promptText)) }
                        .accessibilityIdentifier("page.dialog.ok")
                }
            } message: { dialog in
                Text(dialog.message)
            }
        }
    }
}
