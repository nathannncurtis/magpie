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
    private var relay: ModValueRelay?
    /// The worlds mods have been handed, so their handlers can come off again.
    private var usedWorlds: [String: WKContentWorld] = [:]

    init(values: (any ModValuesReading)? = nil) {
        self.values = values
    }

    /// A page configuration carrying the mods' controller, so every page runs them.
    func pageConfiguration() -> WebPage.Configuration {
        var configuration = WebPage.Configuration()
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
            addMessageHandler(for: world, name: worldName)
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

    private func addMessageHandler(for world: WKContentWorld, name: String) {
        if relay == nil {
            relay = ModValueRelay()
        }
        guard let relay else { return }
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
                        { "mod": "\#(modID)", "key": key, "value": GM_values[key] });
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

    var values: (any ModValuesReading)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        guard let mod = body["mod"] as? String else { return }
        guard let key = body["key"] as? String else { return }
        guard let value = body["value"] as? String else { return }
        let fromPrivatePage = message.webView?.configuration.websiteDataStore.isPersistent == false
        store(value, forKey: key, modID: mod, fromPrivatePage: fromPrivatePage)
    }

    /// A private tab's page keeps its values for itself: nothing it sets is saved.
    func store(_ value: String, forKey key: String, modID: String, fromPrivatePage: Bool) {
        guard !fromPrivatePage else { return }
        values?.storeValue(value, forKey: key, modID: modID)
    }
}
