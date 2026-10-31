import SwiftUI

/// The hardware keyboard's shortcuts, listed in the system's shortcut overlay (hold ⌘).
/// Each one is live only where it means something: the page's own only while reading.
struct KeyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Tab")) { model.newTabFromTabs() }
                .keyboardShortcut("t")
                .disabled(!model.canOpenNewTab)
            Button(String(localized: "Open Location")) { model.openSearchOverPage() }
                .keyboardShortcut("l")
                .disabled(!model.isReadingPage)
            Button(String(localized: "Close Tab")) { model.closeCurrentTab() }
                .keyboardShortcut("w")
                .disabled(!model.isReadingPage)
        }
        CommandGroup(after: .sidebar) {
            Button(String(localized: "Show All Tabs")) { model.showTabs() }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
                .disabled(!model.canShowTabsFromKeyboard)
        }
        CommandMenu(String(localized: "Page")) {
            Button(String(localized: "Reload Page")) { model.currentSession?.retry() }
                .keyboardShortcut("r")
                .disabled(!model.isReadingPage || model.currentSession == nil)
            Button(String(localized: "Back")) { model.currentSession?.goBack() }
                .keyboardShortcut("[")
                .disabled(!model.canGoBack)
            Button(String(localized: "Forward")) { model.currentSession?.goForward() }
                .keyboardShortcut("]")
                .disabled(!model.canGoForward)
            Button(String(localized: "Find on Page")) { model.isFindingInPage = true }
                .keyboardShortcut("f")
                .disabled(!model.isReadingPage || model.currentSession == nil)
            Button(String(localized: "Close Search")) { model.dismissWithEscape() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!model.canDismissWithEscape)
        }
    }
}
