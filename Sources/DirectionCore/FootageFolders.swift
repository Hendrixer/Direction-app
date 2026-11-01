import Foundation

/// Where the director filed a take in their own folders (dailies.md › From your folders): the camera
/// report, read before the editor logs. A scene folder is one named with its number ("01 Intro",
/// "Scene 2 - Pricing", "S03"); a folder inside it is a setup; the files in that are its takes.
public struct FootagePlace: Codable, Hashable, Sendable {
    public var scene: Int
    public var sceneTitle: String
    /// The setup's letter ("A") and what it is ("Talking head"), when a folder inside the scene names one.
    public var setup: String?
    public var setupDescription: String?
    public var take: Int?
    /// The folders it was in, from the scene down: "01 Intro/A Talking head".
    public var folder: String
    public init(scene: Int, sceneTitle: String, setup: String? = nil, setupDescription: String? = nil, take: Int? = nil, folder: String) {
        self.scene = scene; self.sceneTitle = sceneTitle; self.setup = setup; self.setupDescription = setupDescription; self.take = take; self.folder = folder
    }
    /// "2A", the setup's code in Dailies.
    public var setupCode: String? { setup.map { "\(scene)\($0)" } }
}

public enum FootageFolders {
    /// Each file's place, keyed by its path. `root` is what the director dropped or chose: folders above the
    /// first scene folder (the film's own, "Footage", a date) are passed over, and so are a camera card's.
    public static func places(_ found: [(file: URL, root: URL)]) -> [String: FootagePlace] {
        var out: [String: FootagePlace] = [:]
        for (file, root) in found {
            // A folder's files come back with links resolved ("/var" as "/private/var"), so both sides are.
            let r = root.resolvingSymlinksInPath().pathComponents, f = file.resolvingSymlinksInPath().pathComponents
            guard f.count > r.count, Array(f.prefix(r.count)) == r else { continue }
            // The dropped folder's own name counts: "02 Pricing" dropped alone is scene 2.
            let folders = Array(f[(r.count - 1)..<(f.count - 1)]).filter { !isCard($0) }
            guard let i = folders.firstIndex(where: { scene($0) != nil }), let (number, title) = scene(folders[i]) else { continue }
            var place = FootagePlace(scene: number, sceneTitle: title, folder: folders[i])
            if i + 1 < folders.count {
                let name = folders[i + 1]
                let (letter, description) = setup(name)
                place.setup = letter; place.setupDescription = description
                place.folder += "/" + name
            } else if let camera = folders[..<i].last(where: { self.camera($0) != nil }) {
                // "A Cam/02 Pricing/…": the camera is the setup.
                place.setup = self.camera(camera); place.setupDescription = camera
            }
            out[file.path] = place
        }
        // Setups the folders don't letter take the next free letter in their scene, in name order.
        for scene in Set(out.values.map(\.scene)) {
            var used = Set(out.values.filter { $0.scene == scene }.compactMap(\.setup)).subtracting([""])
            let unlettered = Set(out.values.filter { $0.scene == scene && $0.setup == "" }.map(\.folder)).sorted()
            for folder in unlettered {
                let letter = (65...90).map { String(UnicodeScalar(UInt8($0))) }.first { !used.contains($0) } ?? "Z"
                used.insert(letter)
                for (k, p) in out where p.scene == scene && p.folder == folder { out[k]?.setup = letter }
            }
        }
        // Takes in a setup keep the numbers their names give, or are numbered in name order.
        for group in Dictionary(grouping: out.keys.filter { out[$0]?.setup != nil }, by: { "\(out[$0]!.scene)/\(out[$0]!.folder)" }).values {
            let files = group.sorted { URL(fileURLWithPath: $0).lastPathComponent.localizedStandardCompare(URL(fileURLWithPath: $1).lastPathComponent) == .orderedAscending }
            let named = files.map { take(URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent) }
            let usable = !named.contains(nil) && Set(named.compactMap { $0 }).count == files.count
            for (n, path) in files.enumerated() { out[path]?.take = usable ? named[n] : n + 1 }
        }
        for (k, p) in out where p.setup == nil { out[k]?.take = take(URL(fileURLWithPath: k).deletingPathExtension().lastPathComponent) }
        return out
    }

    /// "01 Intro" → (1, "Intro"); "Scene 2 - Pricing" → (2, "Pricing"); "S03" → (3, "Scene 3"). Not "4K",
    /// "1080p", "2026 shoot" or a date.
    static func scene(_ name: String) -> (Int, String)? {
        guard let m = name.wholeMatch(of: /(?i)(?:scene|sc|s)?[\s_.-]*(\d{1,3})(?:[\s_.:-]+(.*))?/), let n = Int(m.1) else { return nil }
        let rest = m.2.map { words(String($0)) } ?? ""
        // "10-18 shoot", "2026-10-18": a date, not a scene.
        if rest.first?.isNumber == true, name.contains(/^\d{1,4}[-_.]\d{1,2}/) { return nil }
        return (n, rest.isEmpty ? "Scene \(n)" : rest)
    }

    /// A setup folder's letter and description: "A Talking head", "2A - Wide", "Setup B", "Cam B", "A_Close".
    /// A name with no letter keeps it all as the description, and its letter comes later (""); a name that's
    /// only a letter leaves the description to the editor.
    static func setup(_ name: String) -> (String, String) {
        let trimmed = words(name)
        if let m = trimmed.wholeMatch(of: /(?i)(?:setup\s*|\d+)?([a-z])/) { return (m.1.uppercased(), "") }
        if let letter = camera(trimmed) { return (letter, trimmed) }
        if let m = trimmed.wholeMatch(of: /(?i)(?:setup\s*([a-z])|\d+([a-z]))[\s_.:-]+(.+)/) { return (String(m.1 ?? m.2 ?? "").uppercased(), String(m.3)) }
        if let m = trimmed.wholeMatch(of: /([A-Z])\s*[_.:-]\s*(.+)/) { return (String(m.1), String(m.2)) }
        if let m = trimmed.wholeMatch(of: /([A-Z])\s+([A-Z].*)/) { return (String(m.1), String(m.2)) }
        return ("", trimmed)
    }

    /// "intro_talk " → "intro talk".
    static func words(_ name: String) -> String { name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces) }

    /// "Cam A", "A Cam", "Camera B", "B-cam" → the letter.
    static func camera(_ name: String) -> String? {
        if let m = name.wholeMatch(of: /(?i)cam(?:era)?[\s_-]*([a-z])/) { return m.1.uppercased() }
        if let m = name.wholeMatch(of: /(?i)([a-z])[\s_-]*cam(?:era)?/) { return m.1.uppercased() }
        return nil
    }

    /// "T3", "Take 03", "S02_A_T03", "intro_take2", "1A-3" → the take's number.
    static func take(_ fileName: String) -> Int? {
        if let m = fileName.firstMatch(of: /(?i)(?:^|[^a-z])(?:take|tk|t)[\s_-]*(\d{1,3})(?!\d)/) { return Int(m.1) }
        if let m = fileName.wholeMatch(of: /\d{1,3}[A-Za-z][_-](\d{1,3})/) { return Int(m.1) }
        return nil
    }

    /// A camera card's own folders, which say nothing about the film.
    static func isCard(_ name: String) -> Bool {
        let n = name.uppercased()
        return ["DCIM", "PRIVATE", "M4ROOT", "CLIP", "AVCHD", "BDMV", "STREAM", "XDROOT", "CONTENTS", "MISC", "THMBNL", "SUB", "PROXY", "PROXIES"].contains(n)
            || n.wholeMatch(of: /\d{3}[A-Z0-9_]{5}/) != nil || n.wholeMatch(of: /CLIPS\d{3}/) != nil
    }
}
