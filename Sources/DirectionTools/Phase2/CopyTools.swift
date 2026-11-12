import Foundation
import CoreText
import ImageIO
import UniformTypeIdentifiers
import DirectionCore

// Bringing a file into the editor's working folder (the film's Editor folder): a font for a graphic, a logo from the
// director's Images, a still a tool drew for a style, a sound for a technique. The editor has no shell, so this is
// its `cp`: only from places Direction vouches for, only into the folder, and never over an agent's own settings.
extension ToolCatalog {
    static var copyDefinitions: [ToolDefinition] { [
        definition("direction_copy", "Bring a file into your working folder (the film\u{2019}s Editor folder) to use in a graphic, a look, a style or a technique: a font on this Mac by its name (font: \"Fira Mono Medium\"), a sound or image from the director\u{2019}s library by its name (library: \"Logo\"), or a file by its path (from): an image or sound one of Direction\u{2019}s tools made (its imagePaths or audioPaths), a file in this film, the director\u{2019}s Sounds, Images, Styles, Looks or Techniques, a take\u{2019}s own file, or a font file in this Mac\u{2019}s fonts folders. to is where it goes in the working folder, like Graphics/title/fira-mono.otf or stills/opening.jpg; an image is converted when to ends in another kind (png, jpg, heic, tiff). Returns its path in the folder. A file already there is replaced.",
                   ["font": noted(string, "A font installed on this Mac, by its full name or PostScript name."),
                    "library": noted(string, "A sound or image in the director\u{2019}s library, by its name as direction_library lists it."),
                    "from": noted(string, "A file\u{2019}s path, from the places above."),
                    "to": noted(string, "Where it goes, inside your working folder.")],
                   required: ["to"], readOnly: false),
    ] }
}

extension ToolRuntime {
    func invokeCopy(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        guard name == "direction_copy" else { return nil }
        let given = [a["font"].string, a["library"].string, a["from"].string].compactMap { $0 }.filter { !$0.isEmpty }
        guard given.count == 1 else { throw DirectionError("invalid_arguments", "Give one of font, library or from, and to. Nothing was copied.") }
        let folder = store.url.appendingPathComponent("Editor", isDirectory: true)
        let to = try a.requiredString("to")
        let target = try FileCopy.target(to, in: folder)
        let source: URL
        if let font = a["font"].string { source = try FileCopy.font(font) }
        else if let item = a["library"].string { source = try FileCopy.library(item) }
        else { source = try FileCopy.allowed(a["from"].string!, film: store.url, cache: cacheDirectory, takes: try store.read().assets.map(\.path)) }
        try FileCopy.copy(source, to: target, in: folder)
        let relative = to.split(separator: "/").joined(separator: "/")
        return ToolResponse(.object(["path": .string(relative), "from": .string(source.lastPathComponent), "bytes": .number(Double((try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0))]))
    }
}

enum FileCopy {
    /// Where a copy may go: a file inside the folder, not hidden (an agent's settings live in dot folders), and never
    /// an agent's instructions. Links are checked when the copy is made (`copy`), once its folder exists.
    static func target(_ path: String, in folder: URL) throws -> URL {
        let parts = path.split(separator: "/").map(String.init)
        let refuse = { DirectionError("copy_not_here", "\(path) isn\u{2019}t a place in your working folder Direction will copy to: give a file\u{2019}s path inside it, like Graphics/title/font.otf, with no hidden folders. Nothing was copied.") }
        guard !path.hasPrefix("/"), !path.hasSuffix("/"), !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." || $0.hasPrefix(".") }) else { throw refuse() }
        guard !["claude.md", "claude.local.md", "agents.md", "agents.override.md", "gemini.md", "notes.md"].contains(parts.last!.lowercased()) else { throw refuse() }
        let url = folder.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(folder.standardizedFileURL.path + "/") else { throw refuse() }
        return url
    }

    /// An installed font's file, by its full or PostScript name (CoreText falls back to another font for a name it
    /// doesn't know, so the name is checked).
    static func font(_ name: String) throws -> URL {
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        let names = [CTFontCopyFullName(font), CTFontCopyPostScriptName(font), CTFontCopyDisplayName(font)].map { ($0 as String).lowercased() }
        guard names.contains(name.lowercased()), let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL else {
            throw DirectionError("font_not_found", "There\u{2019}s no font called \(name) on this Mac. Its full name is what Font Book shows, like \u{201C}Fira Mono Medium\u{201D}.")
        }
        return url
    }

    static func library(_ name: String) throws -> URL {
        if let (song, part) = MediaLibrary.findSong(name) { return MediaLibrary.sounds.url(part ?? song.lead) }
        guard let (library, item) = MediaLibrary.find(name) else { throw DirectionError("library_item_not_found", "There\u{2019}s no \(name) in the library. direction_library lists what\u{2019}s there.") }
        return library.url(item)
    }

    /// The places a path may come from: what Direction made for this film, the film itself, the director's library,
    /// the takes' own files and the Mac's fonts. Not anywhere else on the Mac.
    static func allowed(_ path: String, film: URL, cache: URL, takes: [String]) throws -> URL {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
        var folder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) else { throw DirectionError("file_not_found", "There\u{2019}s no file at \(path). Nothing was copied.") }
        guard !folder.boolValue else { throw DirectionError("copy_not_a_file", "\(path) is a folder: give one file. Nothing was copied.") }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [film, cache, MediaLibrary.sounds.folder, MediaLibrary.images.folder, SharedSettings.stylesFolder, SharedSettings.looksFolder, SharedSettings.techniquesFolder,
                     home.appendingPathComponent("Library/Fonts"), URL(fileURLWithPath: "/Library/Fonts"), URL(fileURLWithPath: "/System/Library/Fonts")]
            .map { $0.standardizedFileURL.resolvingSymlinksInPath().path + "/" }
        let hidden = url.pathComponents.contains { $0.hasPrefix(".") && $0 != "." }
        let take = takes.contains { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path == url.path }
        guard take || (!hidden && roots.contains { url.path.hasPrefix($0) }) else {
            throw DirectionError("copy_not_from_here", "Direction copies only what its tools made, files in this film, the director\u{2019}s library, the takes and this Mac\u{2019}s fonts, not \(path). Nothing was copied.")
        }
        return url
    }

    static let images: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    /// A copy, or an image in another kind when the endings differ. Replaces a file that was there, never a folder.
    /// The folder it lands in must really be inside the working folder once links are followed, and the file itself
    /// can't be a link: the editor's own commands (Codex keeps them) or a shared film could point one anywhere, and
    /// Direction writes outside the editor's sandbox.
    static func copy(_ source: URL, to target: URL, in folder: URL) throws {
        let fm = FileManager.default
        let refuse = DirectionError("copy_not_here", "\(target.lastPathComponent) would land outside your working folder (a link points elsewhere), or over a folder or a link. Nothing was copied.")
        // A film someone shared could carry its Editor folder as a link.
        if (try? fm.destinationOfSymbolicLink(atPath: folder.path)) != nil { throw refuse }
        if !fm.fileExists(atPath: folder.path) { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        // Each folder on the way, as it's made: none may lead out of the working folder.
        var parent = folder
        for part in target.deletingLastPathComponent().path.dropFirst(folder.standardizedFileURL.path.count).split(separator: "/") {
            parent.appendPathComponent(String(part))
            if (try? fm.destinationOfSymbolicLink(atPath: parent.path)) != nil { throw refuse }
            if !fm.fileExists(atPath: parent.path) { try fm.createDirectory(at: parent, withIntermediateDirectories: false) }
            guard (parent.resolvingSymlinksInPath().standardizedFileURL.path + "/").hasPrefix(root) else { throw refuse }
        }
        if (try? fm.destinationOfSymbolicLink(atPath: target.path)) != nil { throw refuse }
        var isFolder: ObjCBool = false
        if fm.fileExists(atPath: target.path, isDirectory: &isFolder), isFolder.boolValue { throw refuse }
        let from = source.pathExtension.lowercased(), to = target.pathExtension.lowercased()
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(to)")
        defer { try? fm.removeItem(at: temporary) }
        if from != to, images.contains(from), images.contains(to) {
            guard let image = CGImageSourceCreateWithURL(source as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }),
                  let type = UTType(filenameExtension: to), let out = CGImageDestinationCreateWithURL(temporary as CFURL, type.identifier as CFString, 1, nil) else {
                throw DirectionError("copy_failed", "Direction couldn\u{2019}t read \(source.lastPathComponent) as an image to make a .\(to).")
            }
            CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(out) else { throw DirectionError("copy_failed", "Direction couldn\u{2019}t write \(target.lastPathComponent).") }
        } else {
            try fm.copyItem(at: source, to: temporary)
        }
        if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: temporary) } else { try fm.moveItem(at: temporary, to: target) }
    }
}
