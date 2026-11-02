import SwiftUI
import AppKit
import AVFoundation
import DirectionCore

// Dailies reads the editor's log (Dailies, TakeInfo) joined with the footage itself.
// Everything here is derived; writes go through FilmModel's director actions.

/// Sidebar bins that aren't scenes. Stored in `FilmModel.selectedSceneID` beside scene IDs.
enum DailiesBin {
    static let unsorted = "dailies:unsorted"
    static let unusable = "dailies:unusable"
}

/// Snapshot-only state: transient things a frame draws (a hover, a drag in flight, a playhead)
/// and the stand-in art for each take. The running app never sets it.
struct DailiesPreview {
    var art: [String: FootageArt] = [:]
    var hoverTakeID: String?
    var selectedTakeID: String?
    var draggingTakeID: String?
    var dropSceneID: String?
    var takePosition: Double?
    var takePlaying = false
}

extension EnvironmentValues {
    @Entry var dailiesPreview = DailiesPreview()
}

/// One line of a take's transcript: a sentence, or a stage direction in parentheses.
struct DailiesLine: Identifiable, Equatable {
    var id: Int
    var start: Double
    var end: Double
    var text: String
    var direction = false
}

/// One camera position in a scene and its takes, in take order.
struct DailiesSetupGroup: Identifiable {
    var code: String
    var description: String
    var takes: [TakeInfo]
    var id: String { code }
}

extension TakeInfo {
    /// "warmest read": the editor's reason in a few words, for cards. A first line on its own wins.
    var suggestionShort: String? {
        guard let s = suggestion?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let line = s.split(separator: "\n").first, s.contains("\n") { return String(line) }
        let clause = s.split(whereSeparator: { ",;.:\u{2014}".contains($0) }).first.map(String.init) ?? s
        return clause.prefix(1).lowercased() + clause.dropFirst()
    }
    /// The editor's full reason: the first sentence, then the rest in a quieter line.
    var suggestionReason: (main: String, more: String?)? {
        guard var s = suggestion?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.contains("\n") { s = s.split(separator: "\n").dropFirst().joined(separator: " ") }
        guard let r = s.range(of: ". ") else { return (s, nil) }
        let more = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return (String(s[..<r.lowerBound]) + ".", more.isEmpty ? nil : more)
    }
    /// 3 from "T3"; unnumbered takes sort last.
    var takeNumber: Int { Int((code ?? "").filter(\.isNumber)) ?? .max }
}

extension FilmModel {
    // MARK: Takes

    /// Every logged take with its file, in footage order.
    var dailiesLogged: [TakeInfo] { (project?.assets ?? []).compactMap { dailies.takes[$0.id] } }

    /// Takes in a scene, setup by setup (in the scene's setup order), then by take number.
    func dailiesTakes(inScene id: String) -> [TakeInfo] { dailiesSetups(inScene: id).flatMap(\.takes) }

    func dailiesSetups(inScene id: String) -> [DailiesSetupGroup] {
        guard let scene = scene(id) else { return [] }
        let takes = dailiesLogged.filter { $0.sceneID == id }
        var groups = scene.setups.map { DailiesSetupGroup(code: $0.code, description: $0.description, takes: []) }
        for t in takes {
            let code = t.setupCode ?? ""
            if let i = groups.firstIndex(where: { $0.code == code }) { groups[i].takes.append(t) }
            else { groups.append(.init(code: code, description: code.isEmpty ? "Other takes" : "", takes: [t])) }
        }
        for i in groups.indices { groups[i].takes.sort { ($0.takeNumber, $0.assetID) < ($1.takeNumber, $1.assetID) } }
        return groups.filter { g in !g.takes.isEmpty || scene.setups.contains { $0.code == g.code } }
    }

    /// Logged takes the editor couldn't place in a scene. Never used in a cut.
    var dailiesUnsorted: [TakeInfo] {
        let scenes = Set(dailies.scenes.map(\.id))
        return dailiesLogged.filter { !$0.unusable && !($0.sceneID.map(scenes.contains) ?? false) }
    }
    var dailiesUnusable: [TakeInfo] { dailiesLogged.filter(\.unusable) }
    func dailiesCircles(inScene id: String) -> Int { dailiesLogged.filter { $0.sceneID == id && $0.circled }.count }
    /// The takes a sidebar row or the grid shows.
    func dailiesTakes(inBin id: String?) -> [TakeInfo] {
        switch id {
        case DailiesBin.unsorted?: dailiesUnsorted
        case DailiesBin.unusable?: dailiesUnusable
        case let id?: dailiesTakes(inScene: id)
        case nil: []
        }
    }

    // MARK: Describing a take

    /// "2A T3", or the file name before the editor has logged it.
    /// "2A T3"; "A1" when the take's code already starts with its setup's ("A A1" said it twice).
    func dailiesLabel(_ t: TakeInfo) -> String {
        if let setup = t.setupCode, !setup.isEmpty, let code = t.code, code.hasPrefix(setup) { return code }
        let parts = [t.setupCode, t.code].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? (asset(t.assetID)?.name ?? "Take") : parts.joined(separator: " ")
    }
    /// An uncircled take in sync with a circled one, that one's label: circling either angle asks for
    /// the moment, so the editor treats both as circled (footage-index.md › Sync).
    func circledAngle(_ assetID: String) -> String? {
        guard !dailies.take(assetID).circled, let g = dailies.syncGroup(for: assetID) else { return nil }
        return g.takes.first { $0.assetID != assetID && dailies.take($0.assetID).circled }.map { dailiesLabel(dailies.take($0.assetID)) }
    }
    /// "T3" inside its setup.
    func dailiesShortLabel(_ t: TakeInfo) -> String { t.code ?? dailiesLabel(t) }
    func dailiesDuration(_ id: String) -> Double { asset(id)?.duration.seconds ?? 0 }
    /// The editor's caption, else the first line of dialogue in quotes, else the file name.
    func dailiesCaption(_ t: TakeInfo) -> String {
        if let c = t.caption, !c.isEmpty { return c }
        if let line = dailiesLines(t.assetID).first(where: { !$0.direction }) { return "\u{201C}\(line.text)\u{201D}" }
        return asset(t.assetID)?.name ?? ""
    }
    /// Stand-in art for previews and before a frame loads.
    func dailiesArt(_ id: String) -> FootageArt {
        let t = dailies.takes[id]
        if let n = scene(t?.sceneID)?.number ?? scene(t?.guessSceneID)?.number { return FootageArt.forScene(n) }
        return .room
    }
    var dailiesTotalSeconds: Double { footage.reduce(0) { $0 + $1.duration.seconds } }
    func dailiesIsTranscribed(_ id: String) -> Bool { transcripts.contains { $0.assetID == id && !$0.words.isEmpty } }

    // MARK: Transcript

    /// A take's dialogue as sentences, with stage directions on their own lines.
    func dailiesLines(_ assetID: String) -> [DailiesLine] {
        Self.dailiesLines(transcripts.filter { $0.assetID == assetID })
    }

    /// Lines from a take's transcripts: the chosen track, else the fullest.
    nonisolated static func dailiesLines(_ candidates: [SourceTranscript]) -> [DailiesLine] {
        guard let transcript = candidates.max(by: { ($0.selectedAt ?? 0, $0.words.count) < ($1.selectedAt ?? 0, $1.words.count) }) else { return [] }
        let words = transcript.words.sorted { $0.range.start < $1.range.start }
        var lines: [DailiesLine] = [], current: [TranscriptWord] = [], inDirection = false
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            lines.append(.init(id: lines.count, start: first.range.start.seconds, end: last.range.end.seconds, text: text, direction: text.hasPrefix("(")))
            current = []
        }
        for w in words {
            let text = w.text.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("(") && !inDirection { flush(); inDirection = true }
            if let last = current.last, !inDirection, w.range.start.seconds - last.range.end.seconds > 1.2 { flush() }
            current.append(w)
            if inDirection { if text.hasSuffix(")") { inDirection = false; flush() } }
            else if let c = text.last, ".?!\u{2026}".contains(c) { flush() }
        }
        flush()
        return lines
    }

    /// "Flubbed line at 0:31" → 31 s, for the alert chip in the transcript.
    func dailiesFlub(_ t: TakeInfo) -> (String, Double)? {
        for flag in t.flags where flag.localizedCaseInsensitiveContains("flub") {
            guard let match = flag.firstMatch(of: /(\d+):(\d\d)/), let m = Double(match.1), let s = Double(match.2) else { continue }
            return (flag, m * 60 + s)
        }
        return nil
    }

    // MARK: Director actions beyond FilmModel's

    func renameScene(_ id: String, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let old = scene(id)?.title, !title.isEmpty, title != old else { return }
        perform { try $0.renameScene(id: id, title: title) }
        registerUndo("Rename Scene") { $0.renameScene(id, to: old) }
    }

    /// Moves several takes at once as one undoable step.
    func moveTakes(_ ids: [String], to sceneID: String?) {
        undoManager?.beginUndoGrouping()
        for id in ids where dailies.takes[id]?.sceneID != sceneID { moveTake(id, to: sceneID) }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(ids.count == 1 ? "Move Take" : "Move Takes")
    }

    /// Accepts the editor's guess for every unsorted take that has one.
    func acceptGuesses() {
        let moves = dailiesUnsorted.compactMap { t in t.guessSceneID.flatMap { scene($0) }.map { (t.assetID, $0.id) } }
        guard !moves.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        for (id, scene) in moves { moveTake(id, to: scene) }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Accept Guesses")
        toast = Toast(title: "Moved \(moves.count) \(moves.count == 1 ? "take" : "takes"). Undo \u{2318}Z")
    }

    func toggleCircles(_ ids: [String]) {
        let takes = ids.compactMap { dailies.takes[$0] }.filter { !$0.unusable }
        guard !takes.isEmpty else { return }
        let on = !takes.allSatisfy(\.circled)
        undoManager?.beginUndoGrouping()
        for t in takes where t.circled != on { setCircle(t.assetID, on) }
        undoManager?.endUndoGrouping()
    }

    func toggleUnusable(_ ids: [String]) {
        let takes = ids.compactMap { dailies.takes[$0] }
        guard !takes.isEmpty else { return }
        let on = !takes.allSatisfy(\.unusable)
        undoManager?.beginUndoGrouping()
        for t in takes where t.unusable != on { setUnusable(t.assetID, on) }
        undoManager?.endUndoGrouping()
    }

    func revealTakes(_ ids: [String]) {
        let urls = ids.compactMap { asset($0) }.map { URL(fileURLWithPath: $0.path) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

// MARK: Formats

enum DailiesFormat {
    /// "3 h 12 m", "48 m".
    static func hoursMinutes(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded()), h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) h \(m) m" : "\(m) m"
    }
    /// "4 min 12 s".
    static func minutesSeconds(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 60 ? "\(s / 60) min \(s % 60) s" : "\(s) s"
    }
    static func count(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) \(n == 1 ? one : many ?? one + "s")" }
}

// MARK: Pieces shared by Dailies and Start

/// The editor speaking: diamond, one or two sentences in first person, an optional quieter line.
struct DailiesSayLine: View {
    var text: String
    var detail: String? = nil
    var color: Color = Gate.Text.primary
    var steelDiamond = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            GemMark(size: 8, color: steelDiamond ? Gate.Text.disabled : nil).frame(width: 14).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(Gate.Font.body).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .lineSpacing(3.3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The editor: \(text)\(detail.map { " \($0)" } ?? "")")
    }
}

/// Uppercase mono label in ion with a diamond: "WHAT THE EDITOR IS FINDING".
struct DailiesEditorLabel: View {
    var text: String
    var body: some View {
        HStack(spacing: 8) {
            GemMark(size: 8)
            Text(text.uppercased()).font(Gate.Font.label).tracking(0.74).foregroundStyle(Gate.Voice.agent)
        }
    }
}

/// Glass duration tag inside a thumbnail: mono 10.5, 4/6 padding, radius 5.
struct DailiesDurationTag: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(Gate.Text.primary)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Gate.Material.glass).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Gate.Material.glassBorder, lineWidth: 1)))
    }
}

/// A take's picture: the poster frame when one exists, a frame read from the file otherwise,
/// and the stand-in art in previews. `scrub` (0…1) shows a frame from that point in the take.
struct DailiesTakeThumb: View {
    var asset: MediaAsset?
    var art: FootageArt
    var preview: Bool
    var scrub: Double? = nil
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Gate.Surface.sunken
            if preview || asset == nil { FootageArtView(art: art) }
            else if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else if let path = asset?.thumbnailPath, let poster = ThumbnailCache.image(path) { Image(nsImage: poster).resizable().aspectRatio(contentMode: .fill) }
        }
        .clipped()
        .clearOfGrain()
        .task(id: taskKey) {
            guard !preview, let asset else { return }
            if scrub == nil, asset.thumbnailPath.flatMap(ThumbnailCache.image) != nil { image = nil; return }
            image = await DailiesFrames.shared.frame(asset, at: scrub ?? 0.12)
        }
    }
    private var taskKey: String { "\(asset?.id ?? "")|\(scrub.map { String(Int($0 * 24)) } ?? "poster")" }
}

/// Frames read from takes for thumbnails and hover scrubbing, cached by file and position.
@MainActor final class DailiesFrames {
    static let shared = DailiesFrames()
    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    func frame(_ asset: MediaAsset, at fraction: Double) async -> NSImage? {
        let step = Int((max(0, min(1, fraction)) * 24).rounded())
        let key = "\(asset.path)#\(step)"
        if let hit = cache[key] { return hit }
        let url = URL(fileURLWithPath: asset.path), seconds = asset.duration.seconds * Double(step) / 24
        guard FileManager.default.fileExists(atPath: asset.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let (cg, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache[key] = image; order.append(key)
        if order.count > 400 { cache.removeValue(forKey: order.removeFirst()) }
        return image
    }
}
