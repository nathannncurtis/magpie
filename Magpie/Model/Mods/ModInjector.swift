import Foundation
import Observation
import WebKit

/// Adds the enabled userscript mods to every page as `WKUserScript`s, each in its own
/// content world (04 · 06).
///
/// `WKUserScript` has no host filter of its own, so every script is wrapped in a guard
/// that checks `location.href` against the mod's compiled rules before running the code.
/// One content controller is shared by every page, which is what lets a change to the
/// mods reach the next page any tab loads.
///
/// Re-applying swaps the scripts on the controller. A page already showing a document
/// keeps what it had; the new set runs from that page's next navigation.
@MainActor
@Observable
final class ModInjector {

    /// The handler name the GM shim posts `GM_setValue` through.
    private static let messageName = "magpieMods"

    /// The controller every page's configuration carries.
    let contentController = WKUserContentController()

    private let values: (any ModValuesReading)?
    /// The worlds mods have been handed, so their handlers can come off again.
    private var usedWorlds: [String: WKContentWorld] = [:]

    init(values: (any ModValuesReading)? = nil) {
        self.values = values
    }

    /// A page configuration carrying the mods' controller, so every page runs them.
    func pageConfiguration() -> WebPage.Configuration {
        var configuration = WebPage.Configuration.browser()
        configuration.userContentController = contentController
        return configuration
    }

    /// Swaps in the given userscript mods. The store decides which are enabled; a mod
    /// whose code or rules have gone missing is skipped rather than refused.
    func apply(_ mods: [InstalledMod]) {
        guard let values else { return }
        contentController.removeAllUserScripts()
        removeMessageHandlers()

        for mod in mods where mod.kind == .userscript {
            guard let metadata = mod.script, let body = values.scriptBody(for: mod) else {
                continue
            }
            let worldName = Self.worldName(for: mod)
            let world = WKContentWorld.world(name: worldName)
            addMessageHandler(for: world, name: worldName, modID: mod.id)
            let script = WKUserScript(
                source: Self.wrappedScript(
                    metadata: metadata,
                    modID: mod.id,
                    modName: mod.name,
                    body: body,
                    values: values.storedValues(modID: mod.id)),
                injectionTime: Self.injectionTime(for: metadata.runAt),
                forMainFrameOnly: true,
                in: world)
            contentController.addUserScript(script)
        }
    }

    /// A world of each mod's own, so mods cannot see each other's values.
    private static func worldName(for mod: InstalledMod) -> String {
        "magpie.mod." + mod.id
    }

    /// Each world gets a relay bound to its own mod, so the mod a value lands in comes
    /// from the world that posted it, never from what the script says it is. The handler
    /// lives only in that world: the page's own scripts, and other mods, can't reach it.
    private func addMessageHandler(for world: WKContentWorld, name: String, modID: String) {
        let relay = ModValueRelay(modID: modID, worldName: name)
        relay.values = values
        contentController.add(relay, contentWorld: world, name: Self.messageName)
        usedWorlds[name] = world
    }

    private func removeMessageHandlers() {
        for world in usedWorlds.values {
            contentController.removeScriptMessageHandler(
                forName: Self.messageName,
                contentWorld: world)
        }
        usedWorlds.removeAll()
    }

    /// WKUserScript offers two injection times: document-start, and end of document,
    /// which carries both document-end and document-idle scripts.
    nonisolated static func injectionTime(for runAt: UserscriptMetadata.RunAt) -> WKUserScriptInjectionTime {
        runAt == .documentStart ? .atDocumentStart : .atDocumentEnd
    }

    /// The guard, the GM shim and the mod's code, as one script.
    nonisolated static func wrappedScript(
        metadata: UserscriptMetadata,
        modID: String,
        modName: String,
        body: String,
        values: [String: String]
    ) -> String {
        let guardExpression = guardExpression(
            run: metadata.runRegexSources,
            barring: metadata.excludeRegexSources)
        let host = encode(["scriptHandler": "Magpie", "version": Self.hostVersion])
        let scriptInfo = encode([
            "name": modName,
            "namespace": metadata.namespace ?? "",
            "version": metadata.version ?? "",
            "description": metadata.summary ?? "",
            "author": metadata.author ?? "",
        ])

        return #"""
            (function () {
            var __href = location.href;
            if (\#(guardExpression)) { return; }
            var GM_info = \#(host);
            GM_info.script = \#(scriptInfo);
            var GM_values = \#(encode(values));
            function GM_addStyle(css) {
                var style = document.createElement("style");
                style.textContent = css;
                (document.head || document.documentElement).appendChild(style);
                return style;
            }
            function GM_getValue(key, fallback) {
                if (Object.prototype.hasOwnProperty.call(GM_values, key)) {
                    try { return JSON.parse(GM_values[key]); } catch (e) { return fallback; }
                }
                return fallback;
            }
            function GM_setValue(key, value) {
                GM_values[key] = JSON.stringify(value);
                try {
                    window.webkit.messageHandlers.magpieMods.postMessage(
                        { "key": String(key), "value": GM_values[key] });
                } catch (e) { }
            }
            \#(body)
            })();
            """#
    }

    /// The JavaScript that bars a page's address: it returns when no run rule lets it
    /// through, or a bar does. An empty rule set bars everything.
    nonisolated static func guardExpression(run: [String], barring: [String]) -> String {
        let allowed = run.map { rule in
            "/\(RuleRegexJS.literalSafe(rule))/i.test(__href)"
        }.joined(separator: " || ")
        guard !allowed.isEmpty else { return "true" }
        let barred = barring.map { rule in
            "/\(RuleRegexJS.literalSafe(rule))/i.test(__href)"
        }.joined(separator: " || ")
        if barred.isEmpty {
            return "!(\(allowed))"
        }
        return "!(\(allowed)) || (\(barred))"
    }

    nonisolated private static var hostVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        return (version as? String) ?? "1.0"
    }

    nonisolated private static func encode(_ value: some Encodable) -> String {
        guard
            let data = try? JSONEncoder().encode(value),
            let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
}

/// What the injector reads and writes through: each mod's code, and the values its
/// script saves for itself.
@MainActor
protocol ModValuesReading: AnyObject {
    func scriptBody(for mod: InstalledMod) -> String?
    func storedValues(modID: String) -> [String: String]
    func storeValue(_ json: String, forKey key: String, modID: String)
}

extension ModStore: ModValuesReading {}

/// Answers the GM shim's posts: one value, for one mod, kept in the mod's own storage.
@MainActor
final class ModValueRelay: NSObject, WKScriptMessageHandler {

    /// The longest key, and the longest value as JSON, one post may store.
    nonisolated static let maxKeyLength = 256
    nonisolated static let maxValueLength = 256 * 1024

    var values: (any ModValuesReading)?
    let modID: String
    let worldName: String

    init(modID: String, worldName: String) {
        self.modID = modID
        self.worldName = worldName
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // Mods run in the main frame only, in their own world.
        guard message.frameInfo.isMainFrame, message.world.name == worldName else { return }
        guard let (key, value) = Self.entry(from: message.body) else { return }
        let fromPrivatePage = message.webView?.configuration.websiteDataStore.isPersistent == false
        store(value, forKey: key, modID: modID, fromPrivatePage: fromPrivatePage)
    }

    /// A private tab's page keeps its values for itself: nothing it sets is saved.
    func store(_ value: String, forKey key: String, modID: String, fromPrivatePage: Bool) {
        guard !fromPrivatePage else { return }
        values?.storeValue(value, forKey: key, modID: modID)
    }

    /// The key and value a post carries, when it is shaped as the shim sends it and
    /// within the size limits.
    nonisolated static func entry(from body: Any) -> (key: String, value: String)? {
        guard
            let body = body as? [String: Any],
            let key = body["key"] as? String,
            let value = body["value"] as? String,
            !key.isEmpty, key.utf8.count <= maxKeyLength,
            value.utf8.count <= maxValueLength
        else { return nil }
        return (key, value)
    }
}
