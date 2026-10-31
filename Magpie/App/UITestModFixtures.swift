import Foundation

/// The mods content the UI tests serve and install: one tiny userscript, one tiny filter
/// list, and the bundled directory index that points at them. The index's digests match
/// these files' bytes, so a UI-test install verifies the same way a real one does.
enum UITestModFixtures {

    /// Served at `/mod.user.js`. It stands in for the directory's smallest script.
    static let userscript = """
        // ==UserScript==
        // @name         Wider Wikipedia
        // @namespace    magpie
        // @version      1.2
        // @author       l.marsh
        // @description  Lets articles use the full width.
        // @match        *://*.wikipedia.org/*
        // @run-at       document-end
        // @grant        GM_addStyle
        // ==/UserScript==
        GM_addStyle("#content { max-width: none; }");
        """

    /// Served at `/mod.list.txt`.
    static let filterList = """
        ! Magpie UI-test list
        ||ads.example.com^
        ||tracker.example.net^
        banner.example.com/banner.gif
        @@||quiet.example.com^
        """

    /// The bundled directory index for UI-test runs, decoded; nil when it is missing or
    /// will not decode, which leaves the directory empty.
    static func directoryIndex() -> DirectoryIndex? {
        guard
            let url = Bundle.main.url(forResource: "ModsDirectoryFixture", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(DirectoryIndex.self, from: data)
    }

    /// The address the fixtures live at.
    static func serverURL(_ path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(UITestEnvironment.pageServerPort)
        components.path = path
        return components.url
    }
}
