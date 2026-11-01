import Foundation

/// Scenes, setups and takes by the names the director types after "@" in a note (notes.md › Naming footage),
/// as Dailies shows them: "Scene 2", "2A", "2A Take 3". A take with no setup is "Scene 4 Take 2"; one with
/// no scene or code goes by its file's name.
public struct FootageName: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable { case scene, setup, take }
    public var id: String
    public var name: String
    public var kind: Kind
    /// One line for the list: the scene's title, the setup's description, the take's caption.
    public var summary: String
    public var sceneID: String?
    public var setupCode: String?
    public var assetID: String?
    public init(id: String, name: String, kind: Kind, summary: String, sceneID: String? = nil, setupCode: String? = nil, assetID: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.summary = summary; self.sceneID = sceneID; self.setupCode = setupCode; self.assetID = assetID
    }
}

public enum FootageNames {
    /// Every scene, setup and take a note can name, in Dailies' order.
    public static func all(_ d: Dailies, assets: [MediaAsset]) -> [FootageName] {
        var out: [FootageName] = []
        let names = Dictionary(assets.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        for s in d.scenes.sorted(by: { $0.number < $1.number }) {
            out.append(FootageName(id: "scene:\(s.id)", name: "Scene \(s.number)", kind: .scene, summary: s.title, sceneID: s.id))
            for setup in s.setups { out.append(FootageName(id: "setup:\(s.id):\(setup.code)", name: setup.code, kind: .setup, summary: [setup.description, "Scene \(s.number) \(s.title)"].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "), sceneID: s.id, setupCode: setup.code)) }
        }
        let scenes = Dictionary(d.scenes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for t in d.takes.values.filter({ names[$0.assetID] != nil }).sorted(by: { order($0, scenes) < order($1, scenes) }) {
            out.append(FootageName(id: "take:\(t.assetID)", name: takeName(t, scene: t.sceneID.flatMap { scenes[$0] }, file: names[t.assetID]!), kind: .take,
                                   summary: [t.caption, t.circled ? "Circled" : nil].compactMap { $0 }.joined(separator: " \u{00B7} "), sceneID: t.sceneID, setupCode: t.setupCode, assetID: t.assetID))
        }
        // Footage nobody has logged yet still has a name.
        for a in assets where d.takes[a.id] == nil && !a.isImage {
            out.append(FootageName(id: "take:\(a.id)", name: (a.name as NSString).deletingPathExtension, kind: .take, summary: "Not logged yet", assetID: a.id))
        }
        return out
    }

    /// "2A Take 3", "Scene 4 Take 2", or the file's name.
    static func takeName(_ t: TakeInfo, scene: DailiesScene?, file: String) -> String {
        let number = t.code.flatMap { Int($0.drop { !$0.isNumber }) }
        if let number, let setup = t.setupCode { return "\(setup) Take \(number)" }
        if let number, let scene { return "Scene \(scene.number) Take \(number)" }
        return (file as NSString).deletingPathExtension
    }
    private static func order(_ t: TakeInfo, _ scenes: [String: DailiesScene]) -> String {
        String(format: "%04d|%@|%@", t.sceneID.flatMap { scenes[$0]?.number } ?? 9999, t.setupCode ?? "~", t.code ?? "~") + t.assetID
    }

    /// The names written with "@" in some words, longest first so "@2A Take 3" isn't read as "@2A".
    public static func mentions(in text: String, names: [FootageName]) -> [FootageName] {
        LibraryCatalog.mentioned(in: text, names, name: \.name)
    }

    /// What the editor reads under a note that names some: which take, setup or scene each is, what's in it, and
    /// where it is in the cut.
    public static func explain(_ found: [FootageName], dailies d: Dailies, assets: [MediaAsset], cut: Sequence?) -> String {
        let files = Dictionary(assets.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        func clock(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
        func inCut(_ ids: Set<String>) -> String? {
            let clips = (cut?.clips ?? []).filter { $0.kind == .video && $0.assetID.map(ids.contains) == true }
            guard let a = clips.map(\.start.seconds).min(), let b = clips.map(\.end.seconds).max() else { return ids.count == 1 ? "Not in the cut." : "None of it is in the cut." }
            return "In the cut at \(clock(a))\u{2013}\(clock(b))."
        }
        func takes(_ ts: [TakeInfo]) -> String {
            ts.sorted { ($0.setupCode ?? "", $0.code ?? "") < ($1.setupCode ?? "", $1.code ?? "") }.map { t in [t.setupCode, t.code].compactMap { $0 }.joined(separator: " ") + (t.circled ? " (circled)" : "") }.joined(separator: ", ")
        }
        return found.map { n -> String in
            let scene = n.sceneID.flatMap { id in d.scenes.first { $0.id == id } }
            let where_ = scene.map { "scene \($0.number) \($0.title)" }
            switch n.kind {
            case .scene:
                let ts = d.takes.values.filter { $0.sceneID == n.sceneID }
                return "@\(n.name) is \(where_ ?? n.name) (\(n.sceneID ?? "")): \(ts.count) take\(ts.count == 1 ? "" : "s")\(ts.isEmpty ? "" : ", " + takes(ts)). " + (inCut(Set(ts.map(\.assetID))) ?? "")
            case .setup:
                let ts = d.takes.values.filter { $0.sceneID == n.sceneID && $0.setupCode == n.setupCode }
                let what = scene?.setups.first { $0.code == n.setupCode }?.description ?? ""
                return "@\(n.name) is setup \(n.name)\(what.isEmpty ? "" : ", \(what),") in \(where_ ?? "no scene"): \(ts.isEmpty ? "no takes" : takes(ts)). " + (inCut(Set(ts.map(\.assetID))) ?? "")
            case .take:
                let t = n.assetID.map { d.take($0) }
                let setup = t?.setupCode.map { code in "setup \(code)" + (scene?.setups.first { $0.code == code }.map { $0.description.isEmpty ? "" : " \($0.description)" } ?? "") }
                let place = [where_, setup].compactMap { $0 }.joined(separator: ", ")
                // A caption of what's said is already in quotes; one of what's seen isn't.
                let caption = t?.caption.map { c in c.hasPrefix("\u{201C}") || c.hasPrefix("\"") ? c : "\u{201C}\(c)\u{201D}" }
                let about = [caption, t?.circled == true ? "circled" : nil, t?.unusable == true ? "not usable" : nil].compactMap { $0 }.joined(separator: ", ")
                return "@\(n.name) is the take \(n.assetID.flatMap { files[$0] } ?? n.name) (assetID \(n.assetID ?? "")) \(place.isEmpty ? "not in a scene yet" : "in " + place)\(about.isEmpty ? "" : ": " + about). " + (n.assetID.flatMap { inCut([$0]) } ?? "")
            }
        }.joined(separator: " ")
    }
}
