import Foundation

/// A Final Draft file as Fountain, so ScriptImport reads it like any screenplay: scene headings, action,
/// character cues with their parentheticals and dialogue, transitions.
public enum FinalDraft {
    public static func fountain(_ data: Data) throws -> String {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw DirectionError("script_unreadable", "That Final Draft file couldn\u{2019}t be read.") }
        var out: [String] = []
        for (type, text) in reader.paragraphs {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            switch type {
            case "Scene Heading": out += ["", ScriptImport.isSceneHeading(t) ? t.uppercased() : "." + t, ""]
            case "Character": out += ["", t.uppercased()]
            case "Parenthetical": out.append(t.hasPrefix("(") ? t : "(\(t))")
            case "Dialogue": out.append(t)
            case "Transition": out += ["", t.uppercased().hasSuffix(":") ? t.uppercased() : t.uppercased() + ":", ""]
            default: out += ["", t, ""]
            }
        }
        return out.joined(separator: "\n")
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var paragraphs: [(String, String)] = []
        private var type: String?, text = "", inText = false
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "Paragraph" { type = attributes["Type"] ?? "Action"; text = "" }
            if name == "Text" { inText = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText, type != nil { text += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "Text" { inText = false }
            if name == "Paragraph", let t = type { paragraphs.append((t, text)); type = nil }
        }
    }
}
