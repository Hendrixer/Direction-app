import SwiftUI
import AppKit
import CoreImage
import DirectionCore
import DirectionMedia

/// The film's look and the Look sheet (specs/looks.md). The sheet previews on the film's own frames,
/// through the same LookPipeline the renderer uses, and changes nothing until Use This Look.
@MainActor @Observable final class LooksModel {
    // MARK: Store-backed
    /// The director's look for the film and for scenes with their own.
    var look = FilmLook()
    /// Note → looks the editor proposed for it (paths), for opening from a look answer.
    var proposals: [String: [String]] = [:]

    // MARK: The sheet
    var groups: [LookGroup] = []
    /// The selected tile: an entry's id, or nil for None.
    var selectedID: String?
    /// What Use This Look would set: the selected tile's LUT plus the filters as they are now.
    var draft = LookSettings.noLook
    /// Filter amounts the director set before switching a filter off, so switching it on again restores them.
    var remembered: [String: Double] = [:]
    /// nil is the whole film; otherwise a scene id.
    var applyTo: String?
    /// "Use the film's look" was clicked for a scene with its own look.
    var useFilmLook = false
    /// `\` is held: the large picture shows the frame without the look.
    var comparing = false
    /// A still clicked to show its frame large; nil shows the frame under the playhead.
    var largeStill: String?

    // MARK: Pictures
    struct Frame { var image: CIImage; var frameIndex: Int }
    struct Still: Identifiable { var id: String; var label: String; var frame: Frame }
    var stills: [Still] = []
    var current: Frame?
    var rendered = Rendered()
    struct Rendered { var picture: CGImage?; var plain: CGImage?; var stills: [String: CGImage] = [:]; var tiles: [String: CGImage] = [:] }

    @ObservationIgnored private var watcher: LooksWatcher?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var detectedFor = -1

    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {
        guard let store = film.store else { return }
        look = (try? store.filmLook()) ?? FilmLook()
        proposals = (try? store.lookProposals()) ?? [:]
        // Log curves are read once per take, in the background, so the renderer can pick camera LUTs.
        let count = film.project?.assets.count ?? 0
        if count != detectedFor { detectedFor = count; Task.detached(priority: .utility) { await CameraLog.detectMissing(in: store) } }
    }

    // MARK: Opening and closing

    /// Opens the Look sheet on the film's current look, or on the looks the editor proposed for a note.
    func open(_ film: FilmModel, noteID: String? = nil) {
        film.pause()
        if !film.isPreview { _ = try? SharedSettings.ensureLooksFolder() }
        reloadGroups(film)
        let note = noteID.flatMap(film.note)
        applyTo = note?.sceneID
        useFilmLook = false; comparing = false; largeStill = nil; remembered = [:]
        if let path = noteID.flatMap({ proposals[$0]?.first }), let entry = entry(path) { select(entry) }
        else { adopt(applied(for: applyTo)) }
        film.sheet = .look
        loadFrames(film)
        startWatching(film)
    }

    func close(_ film: FilmModel) {
        watcher?.stop(); watcher = nil
        if film.sheet == .look { film.sheet = nil }
    }

    /// Use This Look: one undoable director act for the film or the chosen scene.
    func use(_ film: FilmModel) {
        let chosen: LookSettings? = useFilmLook && applyTo != nil ? nil : (draft.isNone ? .noLook : draft)
        film.setLook(chosen, sceneID: applyTo)
        close(film)
    }

    // MARK: Choosing

    var allEntries: [LookEntry] { groups.flatMap(\.looks) }
    func entry(_ id: String?) -> LookEntry? { id.flatMap { id in allEntries.first { $0.id == id } } }

    /// The look in force for the film or a scene: the scene's own, else the film's.
    func applied(for sceneID: String?) -> LookSettings { (sceneID.flatMap { look.scenes[$0] } ?? look.film) ?? .noLook }
    /// The tile that shows the look in force for the current Apply to, for its Current chip.
    var currentTileID: String? { tileID(for: applied(for: applyTo)) }
    func tileID(for settings: LookSettings) -> String? {
        guard let lut = settings.lut else { return nil }
        let file = URL(fileURLWithPath: lut).lastPathComponent
        // A chosen folder LUT lives in the film as a copy; it's still that folder look.
        return allEntries.first { $0.settings.lut == lut }?.id ?? allEntries.first { $0.settings.lut.map { URL(fileURLWithPath: $0).lastPathComponent } == file && $0.name == settings.name }?.id
    }

    /// Picks a tile. The editor's looks come with their filters; a folder LUT keeps the filters as they are.
    func select(_ entry: LookEntry?) {
        guard entry?.problem == nil else { return }
        useFilmLook = false
        selectedID = entry?.id
        if let entry, entry.group == LooksLibrary.editorGroup { draft = entry.settings; remembered = [:] }
        else {
            draft.lut = entry?.settings.lut; draft.strength = 1
            draft.name = entry?.name ?? "None"; draft.by = entry?.settings.by ?? "you"; draft.note = nil
        }
        renderDraft()
    }

    /// Shows an existing look in the sheet.
    func adopt(_ settings: LookSettings) {
        draft = settings; selectedID = tileID(for: settings)
        renderDraft()
    }

    func setStrength(_ value: Double) { draft.strength = min(1, max(0, value)); useFilmLook = false; renderDraft() }

    func isOn(_ f: LookFilter) -> Bool { (draft.filters[f.rawValue] ?? 0) > 0 }
    func amount(_ f: LookFilter) -> Double { draft.filters[f.rawValue] ?? remembered[f.rawValue] ?? 0.5 }
    func option(_ f: LookFilter) -> String { draft.options[f.rawValue] ?? f.options.first ?? "" }
    func setOn(_ f: LookFilter, _ on: Bool) {
        if on { draft.filters[f.rawValue] = f.hasAmount ? (remembered[f.rawValue] ?? 0.5) : 1 }
        else { remembered[f.rawValue] = draft.filters[f.rawValue]; draft.filters[f.rawValue] = nil }
        useFilmLook = false; renderDraft()
    }
    func setAmount(_ f: LookFilter, _ value: Double) { draft.filters[f.rawValue] = max(0.01, min(1, value)); useFilmLook = false; renderDraft() }
    func setOption(_ f: LookFilter, _ value: String) { draft.options[f.rawValue] = value; useFilmLook = false; renderDraft() }

    /// Apply to changed: show what that target has now.
    func setApplyTo(_ sceneID: String?) {
        applyTo = sceneID; useFilmLook = false
    }
    func sceneHasOwnLook(_ sceneID: String?) -> Bool { sceneID.map { look.scenes[$0] != nil } ?? false }
    /// "Use the film's look": the scene gives up its own look when you press Use This Look.
    func chooseFilmLook() { adopt(applied(for: nil)); useFilmLook = true }

    // MARK: Folder

    func reloadGroups(_ film: FilmModel) {
        guard !film.isPreview else { return }
        groups = LooksLibrary.groups(folder: SharedSettings.looksFolder, film: film.url)
        if let id = selectedID, entry(id) == nil { selectedID = tileID(for: draft) }
        renderTiles()
    }

    /// A LUT dropped into the Looks folder (or a look the editor makes) appears while the sheet is open.
    private func startWatching(_ film: FilmModel) {
        guard !film.isPreview, watcher == nil else { return }
        var paths = [SharedSettings.looksFolder]
        if let store = film.store { try? FileManager.default.createDirectory(at: store.editorLooksFolder, withIntermediateDirectories: true); paths.append(store.editorLooksFolder) }
        watcher = LooksWatcher(paths: paths) { [weak self, weak film] in
            Task { @MainActor in guard let self, let film, film.sheet == .look else { return }; self.reloadGroups(film) }
        }
    }

    // MARK: Frames

    /// The frame under the playhead and one still per scene (up to five), rendered without any look.
    private func loadFrames(_ film: FilmModel) {
        guard !film.isPreview, let runtime = film.runtime, let project = film.displayed ?? film.project, let sequence = film.sequence else { return }
        let fps = film.fps, at = min(film.position, max(0, film.duration - 1 / fps))
        let sceneFor = film.dailies.takes.compactMapValues(\.sceneID), dailies = film.dailies
        let picks = LookMaker.picks(sequence, sceneForAsset: sceneFor, count: 5)
        generation += 1
        let token = generation
        Task {
            do {
                let compiled = try await SequenceRenderer.compile(project: project, sequenceID: sequence.id, cacheDirectory: runtime.cacheDirectory, previewMaxDimension: 1440)
                let folder = runtime.cacheDirectory.appendingPathComponent("Looks/Sheet")
                func plain(_ t: Double, _ size: Int) async throws -> CIImage? {
                    let url = folder.appendingPathComponent(newID("frame") + ".png")
                    _ = try await SequenceRenderer.frame(compiled, at: .init(seconds: t), to: url, maxDimension: size)
                    defer { try? FileManager.default.removeItem(at: url) }
                    // Decoded now, so the file can go.
                    guard let image = LookMaker.image(at: url), let cg = LookPreview.context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.itur_709)!) else { return nil }
                    return CIImage(cgImage: cg)
                }
                if let image = try await plain(at, 1440), token == generation { current = Frame(image: image, frameIndex: Int(at * fps)) }
                var loaded: [Still] = []
                for p in picks {
                    guard let image = try await plain(p.time, 320) else { continue }
                    let label = dailies.scenes.first { $0.id == p.sceneID }?.label ?? Timecode.format(p.time, fps: fps)
                    loaded.append(Still(id: p.sceneID ?? "\(p.time)", label: label, frame: Frame(image: image, frameIndex: Int(p.time * fps))))
                }
                guard token == generation else { return }
                stills = loaded
                renderTiles(); renderDraft()
            } catch { film.error = error.localizedDescription }
        }
    }

    /// Fixtures and previews hand in their own frames.
    func setFrames(current: Frame, stills: [Still]) { self.current = current; self.stills = stills }

    // MARK: Rendering

    /// Renders the large picture and the stills with the draft. Off the main thread in the app,
    /// at once in previews; a newer change drops an older render.
    func renderDraft(sync: Bool = false) {
        guard let current else { return }
        generation += 1
        let token = generation, look = draft, big = largeStill.flatMap { id in stills.first { $0.id == id }?.frame } ?? current
        let stills = self.stills.map { ($0.id, $0.frame) }
        if sync { let r = LookPreview.draft(big, stills, look); rendered.picture = r.picture; rendered.plain = r.plain; rendered.stills = r.stills; return }
        Task.detached(priority: .userInitiated) {
            let r = LookPreview.draft(big, stills, look)
            await MainActor.run { guard token == self.generation else { return }; self.rendered.picture = r.picture; self.rendered.plain = r.plain; self.rendered.stills = r.stills }
        }
    }

    /// Each tile is the current frame with that tile's own look.
    func renderTiles(sync: Bool = false) {
        guard let current else { return }
        let entries = allEntries.map { ($0.id, $0.problem == nil ? $0.settings : LookSettings.noLook) }
        if sync { rendered.tiles = LookPreview.tiles(current, entries); return }
        Task.detached(priority: .userInitiated) { let tiles = LookPreview.tiles(current, entries); await MainActor.run { self.rendered.tiles = tiles } }
    }
}

extension LooksModel.Frame: @unchecked Sendable {}

/// Core Image work for the sheet: one Metal context, shared.
enum LookPreview {
    nonisolated(unsafe) static let context = CIContext(options: [.cacheIntermediates: false])

    nonisolated static func draft(_ big: LooksModel.Frame, _ stills: [(String, LooksModel.Frame)], _ look: LookSettings) -> (picture: CGImage?, plain: CGImage?, stills: [String: CGImage]) {
        var out: [String: CGImage] = [:]
        for (id, f) in stills { out[id] = render(f, look: look, width: 276) }
        return (render(big, look: look), render(big, look: nil), out)
    }

    nonisolated static func tiles(_ frame: LooksModel.Frame, _ entries: [(String, LookSettings)]) -> [String: CGImage] {
        var out: [String: CGImage] = [:]
        out["none"] = render(frame, look: nil, width: 208)
        for (id, look) in entries { out[id] = render(frame, look: look, width: 208) }
        return out
    }

    nonisolated static func render(_ frame: LooksModel.Frame, look: LookSettings?, width: CGFloat? = nil) -> CGImage? {
        var image = frame.image
        if let width, image.extent.width > width {
            let s = width / image.extent.width
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            image = image.cropped(to: image.extent.integral)
        }
        if let look { image = LookPipeline.apply(look, to: image, frameIndex: frame.frameIndex) }
        return context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.itur_709))
    }
}

extension FilmModel {
    /// Film › Look…, the picture's Look…, and a look answer in Changes.
    func openLook(noteID: String? = nil) { looks.open(self, noteID: noteID) }

    /// The director chooses the look: undoable, and in History as "Changed the look of the film".
    func setLook(_ look: LookSettings?, sceneID: String?) {
        let previous = sceneID.map { looks.look.scenes[$0] } ?? looks.look.film
        if isPreview {
            if let sceneID { looks.look.scenes[sceneID] = look } else { looks.look.film = look?.isNone == true ? nil : look }
        } else {
            perform { try $0.setLook(look, sceneID: sceneID, asDirector: true) }
        }
        registerUndo("Change Look") { $0.setLook(previous, sceneID: sceneID) }
    }
}
