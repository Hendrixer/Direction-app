import Foundation
import SwiftUI
import AppKit
import AVKit
import Observation
import DirectionCore
import DirectionMedia
import DirectionTools

enum Room: String, CaseIterable, Identifiable {
    case dailies, script, screening, notes, changes, finish
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var shortcut: KeyEquivalent { KeyEquivalent(Character(String((Room.allCases.firstIndex(of: self) ?? 0) + 1))) }
}

enum ActiveSheet: String, Identifiable { case turnover, lockPicture, deliver, share, relink, brief
    var id: String { rawValue }
}

enum NotesTab: String { case sheet, questions, outside }
enum NoteAnchorMode: String, CaseIterable { case moment, range, region, scene, wholeCut
    var label: String { switch self { case .moment: "Moment"; case .range: "Range"; case .region: "Region"; case .scene: "Scene"; case .wholeCut: "Whole cut" } }
}
enum OnboardingStep: Int, Comparable { case brief, footage, firstLook
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// The titlebar's one steel button for the current room and state.
struct PrimaryAction {
    var title: String
    var icon: String?
    var count: String?
    var enabled = true
    /// Help tag; for a disabled action, why it's disabled.
    var help: String? = nil
    /// Key hint shown inside the button, e.g. "⌘↩".
    var key: String? = nil
    var action: () -> Void
}

/// State and actions for one open film. Every room reads from here; store writes go
/// through the methods below so the editor sees exactly what the director did.
@MainActor @Observable
final class FilmModel {
    // MARK: Store-backed state
    var project: Project?
    var brief = Brief()
    var dailies = Dailies()
    var notes: [ReviewComment] = []
    /// Oldest first: Assembly, Cut 2, Cut 3…
    var cuts: [ReviewCut] = []
    var turnovers: [Turnover] = []
    var questions: [EditorQuestion] = []
    var directing = DirectingState()
    var editorStatus: EditorStatus?
    var transcripts: [SourceTranscript] = []
    var jobs: [JobRecord] = []
    var events: [ProjectEvent] = []
    var error: String?

    // MARK: Navigation
    var room: Room = .notes
    var sheet: ActiveSheet?
    var toast: Toast?
    var showEditorPopover = false
    var showCommandMenu = false
    var showShortcuts = false
    /// Increments once when a new cut arrives; the window runs the prism sweep.
    var sweepToken = 0
    var offline = false
    /// Takes whose files can't be reached; set by the footage-missing banner.
    var missingTakes = 0

    // MARK: Watching
    /// The cut on screen. nil follows the latest cut.
    var watchedCutID: String?
    var displayed: Project?
    var position = 0.0
    var playing = false
    var isPreparing = false

    // MARK: Notes
    var notesTab: NotesTab = .sheet
    var selectedNoteID: String?
    var draftText = ""
    var draftKind: NoteKind?
    var anchorMode: NoteAnchorMode = .moment
    var rangeSelection: ClosedRange<Double>?
    var region: CGRect?
    var drawingRegion = false
    var composerFocus = 0
    var showDropped = false

    // MARK: Screening
    var screeningStartedAt: Date?
    var screeningMarkIDs: [String] = []
    var screeningEnded = false
    var freshMarkID: String?

    // MARK: Dailies and Script
    var selectedSceneID: String?
    var openTakeID: String?
    var selectedLineID: String?

    // MARK: Changes
    var selectedAnswerNoteID: String?
    var playingChanges = false
    var changeIndex = 0
    var comparingNoteID: String?

    /// Previews and snapshots run without a store.
    let isPreview: Bool
    @ObservationIgnored var runtime: ToolRuntime?
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var compiled: CompiledSequence?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderKey = ""
    @ObservationIgnored private var cursor: Int64 = -1
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var knownDelivered: Set<String> = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Set by the window. Director actions register their inverse here for ⌘Z.
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var playbackActivity: NSObjectProtocol?
    /// Posts a user notification: (title, body, settings key). Set by the app.
    @ObservationIgnored var onNotify: ((String, String, String) -> Void)?
    @ObservationIgnored private var knownQuestions: Set<String> = []

    var store: ProjectStore? { runtime?.store }
    var url: URL? { store?.url }

    init(preview: Bool = false) {
        isPreview = preview
        guard !preview else { return }
        player.automaticallyWaitsToMinimizeStalling = false
        let output = UserDefaults.standard.string(forKey: "audioOutput") ?? ""
        player.audioOutputDeviceUniqueID = output.isEmpty ? nil : output
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1 / 24, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { guard let self, time.seconds.isFinite, !self.isPreparing else { return }; self.position = time.seconds; self.playing = self.player.rate > 0; self.keepAwake(self.playing) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            let id = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let current = self.player.currentItem, ObjectIdentifier(current) == id else { return }
                self.player.pause(); self.playing = false; self.didReachEnd()
            }
        }
    }

    convenience init(url: URL) throws {
        self.init()
        let store = try ProjectStore(url: url)
        try ProjectLibrary().register(store)
        runtime = try ToolRuntime(store: store)
        refresh(force: true)
        knownDelivered = Set(turnovers.filter { $0.state == .delivered }.map(\.id))
        knownQuestions = Set(questions.map(\.id))
        room = defaultRoom
    }

    func startPolling() {
        guard pollTask == nil, !isPreview else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    func close() {
        pollTask?.cancel(); pollTask = nil; renderTask?.cancel(); player.pause(); player.replaceCurrentItem(with: nil)
        if let runtime { Task { await runtime.cancelAll() } }
    }

    // MARK: Loading

    func refresh(force: Bool = false) {
        guard let store else { return }
        do {
            let latest = try store.eventCursor()
            guard force || latest != cursor else { return }
            project = try store.read()
            brief = try store.brief(); dailies = try store.dailies(); directing = try store.directingState(); editorStatus = try store.editorStatus()
            notes = try store.notes(); cuts = try store.cuts().sorted { $0.createdAt < $1.createdAt }
            turnovers = try store.turnovers(); questions = try store.questions()
            transcripts = try store.transcripts(); jobs = try store.jobs()
            let newEvents = try store.events(since: max(0, cursor)); events = Array((events + newEvents).suffix(200))
            cursor = latest
            announceDeliveredCuts()
            announceQuestions()
            loadDisplayed()
        } catch { self.error = error.localizedDescription }
    }

    private func announceDeliveredCuts() {
        for t in turnovers where t.state == .delivered && !knownDelivered.contains(t.id) {
            knownDelivered.insert(t.id)
            guard let cut = cuts.first(where: { $0.id == t.resultCutID }) else { continue }
            sweepToken += 1
            let answers = notes.filter { $0.latestAnswer?.cutID == cut.id }.count
            toast = Toast(title: "\(cut.name) is ready", detail: "\(answers) answers · \(Timecode.duration(changesDuration(in: cut))) of changes to watch", editor: true, actionTitle: "Watch changes")
            if watchedCutID == nil { loadDisplayed(force: true) }
            onNotify?("\(cut.name) is ready", "\(filmName) · \(answers) answers to review", NotificationKey.cutReady)
        }
    }

    private func announceQuestions() {
        let fresh = openQuestions.filter { !knownQuestions.contains($0.id) }
        defer { knownQuestions.formUnion(questions.map(\.id)) }
        guard cursor >= 0, !knownQuestions.isEmpty || !questions.isEmpty, pollTask != nil else { return }
        for q in fresh {
            onNotify?(q.kind == "cant" ? "The editor can't do note \(q.noteIDs.first.map(noteNumber) ?? "")" : "The editor has a question", q.text, q.kind == "cant" ? NotificationKey.cant : NotificationKey.question)
        }
    }

    /// Loads the project at the watched cut's revision and prepares playback.
    func loadDisplayed(force: Bool = false) {
        guard let store else { return }
        let revision = watchedCut?.editRevision ?? project?.editRevision ?? 0
        if force || displayed?.editRevision != revision || displayed == nil {
            displayed = (try? store.read(revision: revision)) ?? project
        }
        preparePlayback()
    }

    // MARK: Derived: cuts and sequences

    var latestCut: ReviewCut? { cuts.last }
    var watchedCut: ReviewCut? { watchedCutID.flatMap { id in cuts.first { $0.id == id } } ?? latestCut }
    var previousCut: ReviewCut? { watchedCut.flatMap { w in cuts.last { $0.createdAt < w.createdAt } } }
    var sequence: DirectionCore.Sequence? { try? (displayed ?? project)?.sequence(watchedCut?.sequenceID) }
    var duration: Double { sequence?.duration.seconds ?? 0 }
    var fps: Double { sequence?.frameRate.value ?? 24 }
    var aspect: CGFloat { CGFloat(sequence?.width ?? 1920) / CGFloat(max(1, sequence?.height ?? 1080)) }
    var filmName: String { project?.name ?? "Film" }
    /// The crumb: "New film" until the brief names it.
    var filmTitle: String { (project?.name ?? "").hasPrefix("Untitled film") ? "New film" : filmName }
    func cutName(_ id: String?) -> String { id.flatMap { id in cuts.first { $0.id == id }?.name } ?? "Working cut" }
    func asset(_ id: String?) -> MediaAsset? { id.flatMap { id in project?.assets.first { $0.id == id } } }
    var scenes: [DailiesScene] { dailies.scenes.sorted { $0.number < $1.number } }
    func scene(_ id: String?) -> DailiesScene? { id.flatMap { id in dailies.scenes.first { $0.id == id } } }
    var hasFootage: Bool { !(project?.assets.isEmpty ?? true) }

    /// Scenes as they sit in the watched cut, from the clips on the bottom video layer.
    var stripScenes: [StripScene] {
        guard let sequence else { return [] }
        let clips = sequence.clips.filter { $0.kind == .video && $0.layer == 0 }.sorted { $0.start < $1.start }
        var out: [StripScene] = []
        let changed = changedRanges(in: watchedCut)
        for (i, clip) in clips.enumerated() {
            let scene = dailies.scene(for: clip.assetID)
            let start = clip.start.seconds, end = clip.end.seconds
            if let last = out.last, let scene, last.id == scene.id, abs(last.end - start) < 0.05 { out[out.count - 1].end = end; continue }
            let number = scene?.number ?? (i + 1)
            out.append(StripScene(id: scene?.id ?? clip.id, number: number, title: scene?.title ?? (dailies.scenes.isEmpty ? clip.name : ""), start: start, end: end, art: FootageArt.forScene(number), thumbnail: asset(clip.assetID)?.thumbnailPath, locked: scene?.locked ?? false))
        }
        for i in out.indices { out[i].changed = changed.contains { $0.overlaps(out[i].start...out[i].end) } }
        return out
    }
    func stripScene(at time: Double) -> StripScene? { stripScenes.first { time >= $0.start && time < $0.end } ?? stripScenes.last }

    // MARK: Derived: notes

    /// The cut notes are written against.
    var notesCut: ReviewCut? { watchedCut }
    /// Notes on the sheet: everything the director wrote that isn't in the outside inbox.
    var sheetNotes: [ReviewComment] {
        notes.filter { !$0.inInbox && !($0.isOutside && $0.outsideState == "declined") && !$0.isUnasked && ($0.lifecycle != .dropped || showDropped) && $0.lifecycle != .accepted }
            .sorted { ($0.number ?? .max, $0.createdAt) < ($1.number ?? .max, $1.createdAt) }
    }
    /// Written or reopened notes waiting for the next turnover.
    var readyNotes: [ReviewComment] { sheetNotes.filter { [.written, .reopened].contains($0.lifecycle) && $0.visibleToEditor } }
    var draftNotes: [ReviewComment] { sheetNotes.filter { $0.lifecycle == .draft } }
    var inbox: [ReviewComment] { notes.filter(\.inInbox).sorted { $0.createdAt < $1.createdAt } }
    var openQuestions: [EditorQuestion] { questions.filter { $0.answer == nil } }
    var openTurnover: Turnover? { turnovers.last { $0.state.isOpen } }
    var lastTurnover: Turnover? { turnovers.last }
    func note(_ id: String?) -> ReviewComment? { id.flatMap { id in notes.first { $0.id == id } } }
    func noteNumber(_ id: String) -> String { note(id)?.number.map(String.init) ?? "–" }
    /// The note's moment in the watched cut.
    func noteTime(_ c: ReviewComment) -> Double? { c.range?.start.seconds ?? c.time?.seconds }

    var noteMarks: [StripMark] {
        sheetNotes.compactMap { c in noteTime(c).map { StripMark(id: c.id, time: $0, kind: c.isOutside ? .outside : .director, fresh: c.id == freshMarkID) } }
    }

    func anchorText(_ c: ReviewComment) -> String {
        if let action = c.scriptAction { return action.lineLabel ?? "Line" }
        if let r = c.range { return Timecode.range(r.start.seconds, r.end.seconds, fps: fps) }
        if let t = c.time { return Timecode.format(t.seconds, fps: fps) }
        if let s = scene(c.sceneID) { return "Scene \(s.number)" }
        return "Whole cut"
    }

    // MARK: Derived: answers and changes

    /// Answers the editor delivered in a cut, in note order.
    func answers(in cut: ReviewCut?) -> [ReviewComment] {
        guard let cut else { return [] }
        return notes.filter { c in c.answers?.contains { $0.cutID == cut.id } ?? false }.sorted { ($0.number ?? .max) < ($1.number ?? .max) }
    }
    func answer(_ c: ReviewComment, in cut: ReviewCut?) -> NoteAnswer? { c.answers?.last { $0.cutID == cut?.id } }
    var unreviewedAnswers: [ReviewComment] { answers(in: latestCut).filter { answer($0, in: latestCut)?.state == "unreviewed" && $0.lifecycle == .answered } }
    func changedRanges(in cut: ReviewCut?) -> [ClosedRange<Double>] {
        answers(in: cut).compactMap { answer($0, in: cut)?.range }.map { $0.start.seconds...$0.end.seconds }
    }
    @AppStorage("handleSeconds") @ObservationIgnored var handleSeconds = 2.0
    /// Changed passages with handles, merged, for Play changes.
    func changeReel(in cut: ReviewCut?) -> [ClosedRange<Double>] {
        let padded = changedRanges(in: cut).map { max(0, $0.lowerBound - handleSeconds)...min(max(duration, $0.upperBound), $0.upperBound + handleSeconds) }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for r in padded { if let last = merged.last, r.lowerBound <= last.upperBound { merged[merged.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound) } else { merged.append(r) } }
        return merged
    }
    func changesDuration(in cut: ReviewCut?) -> Double { changeReel(in: cut).reduce(0) { $0 + $1.upperBound - $1.lowerBound } }

    // MARK: Derived: editor and rooms

    var pill: EditorPillState {
        if offline { return .offline }
        if directing.editorPaused { return .paused }
        if missingTakes > 0, openTurnover != nil || isLogging { return .needsFootage }
        let cants = openQuestions.filter { $0.kind == "cant" }.count, asks = openQuestions.filter { $0.kind == "question" }.count
        if let t = openTurnover {
            let total = max(1, t.noteIDs.count), done = t.progress.values.filter { $0 == .done }.count
            switch t.state {
            case .waiting: return .waiting
            case .readBack: return t.readBackApproved ? .working("Starting", nil) : .readBackReady
            case .cutting:
                if cants > 0 { return .cant(cants) }
                if asks > 0 { return .asks(asks) }
                return t.kind == "assembly" ? .assembling(t.phase ?? "Assembling", t.percent) : .working("Cutting \(min(total, done + 1)) of \(total)", t.percent ?? Double(done) / Double(total))
            case .blocked: return cants > 0 ? .cant(cants) : asks > 0 ? .asks(asks) : .stopped
            case .failed: return .stopped
            default: break
            }
        }
        if cants > 0 { return .cant(cants) }
        if asks > 0 { return .asks(asks) }
        if isDelivering { return .working("Delivering \(delivery.doneCount + 1) of \(delivery.items.count)", delivery.items.isEmpty ? nil : Double(delivery.doneCount) / Double(delivery.items.count)) }
        if isPictureLocked, let item = directing.finishing?.first(where: { $0.state == "working" && $0.by.contains("editor") }) { return .working(item.title == "Sound mix" ? "Mixing sound" : item.title, item.progress) }
        if let cut = latestCut, !unreviewedAnswers.isEmpty, openTurnover == nil { return .cutReady("\(cut.name) ready") }
        if isLogging, let total = project?.assets.count, total > 0, cuts.isEmpty {
            return .working("Logging \(loggedCount) of \(total)", Double(loggedCount) / Double(total))
        }
        return .ready
    }
    var isPictureLocked: Bool { directing.pictureLocked }
    /// Before a film has a first cut, the window walks through Brief → Footage → First look.
    /// The director left onboarding early (Open Dailies while the editor is still logging).
    var onboardingDismissed = false
    var onboardingStep: OnboardingStep? {
        guard cuts.isEmpty, !onboardingDismissed else { return nil }
        if !brief.isComplete { return .brief }
        if !hasFootage { return .footage }
        if openTurnover?.kind == "assembly" { return .firstLook }
        // Footage is in but the editor hasn't logged every take yet: Logging footage.
        if isLogging { return .footage }
        return nil
    }
    /// Takes the editor has logged, out of all footage.
    var loggedCount: Int { project?.assets.filter { dailies.takes[$0.id] != nil }.count ?? 0 }
    var isLogging: Bool { hasFootage && (project?.assets.contains { dailies.takes[$0.id] == nil } ?? false) }
    var defaultRoom: Room {
        if !unreviewedAnswers.isEmpty { return .changes }
        if cuts.isEmpty { return .dailies }
        if isPictureLocked { return .finish }
        return .notes
    }
    func badge(for room: Room) -> (String, Bool)? {
        switch room {
        case .notes: let n = draftNotes.count + readyNotes.count; return n > 0 ? (String(n), true) : nil
        case .changes: let n = unreviewedAnswers.count; return n > 0 ? (String(n), false) : nil
        default: return nil
        }
    }
    func isEnabled(_ room: Room) -> Bool {
        switch room {
        case .finish: isPictureLocked
        // Nothing to watch or note before the first cut.
        case .screening, .notes, .changes: !cuts.isEmpty
        default: true
        }
    }
    func go(_ room: Room) {
        guard isEnabled(room) else { return }
        // Leaving the first look for a room: the assembly keeps building in the background.
        if onboardingStep == .firstLook { onboardingDismissed = true }
        if self.room == .screening && room != .screening { endScreening(showEndCard: false) }
        withAnimation(gateAnimation(Gate.Motion.glide)) { self.room = room }
        if room == .screening { startScreening() }
    }

    // MARK: Playback

    func preparePlayback(force: Bool = false) {
        guard !isPreview, let p = displayed, let sequence, let runtime else { return }
        let key = "\(p.editRevision):\(sequence.id)"
        guard force || key != renderKey else { return }
        renderKey = key; renderTask?.cancel(); isPreparing = true; pendingSeek = position
        if sequence.clips.isEmpty { player.pause(); player.replaceCurrentItem(with: nil); compiled = nil; isPreparing = false; return }
        renderTask = Task {
            do {
                let result = try await SequenceRenderer.compile(project: p, sequenceID: sequence.id, cacheDirectory: runtime.cacheDirectory, previewMaxDimension: 1920)
                try Task.checkCancellation()
                guard renderKey == key else { return }
                let target = pendingSeek ?? position
                player.pause(); playing = false; compiled = result; player.replaceCurrentItem(with: result.playerItem()); isPreparing = false; pendingSeek = nil
                seek(min(target, max(0, duration - 1 / fps)))
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; isPreparing = false } }
        }
    }
    func watch(_ cut: ReviewCut?) {
        player.pause(); playing = false
        watchedCutID = cut?.id == latestCut?.id ? nil : cut?.id
        loadDisplayed(force: true)
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = max(0, min(seconds, duration))
        if isPreparing || isPreview { pendingSeek = position; return }
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func togglePlayback() {
        guard !isPreview else { playing.toggle(); return }
        if player.rate > 0 { player.pause(); playing = false } else { if position >= duration - 0.03 { seek(0) }; player.play(); playing = true }
    }
    func pause() { player.pause(); playing = false }
    func step(frames: Double) { pause(); seek(position + frames / fps) }
    func shuttle(_ rate: Float) { guard !isPreview else { return }; if rate == 0 { pause() } else { player.rate = rate; playing = true } }
    /// Keeps the display awake while picture plays.
    private func keepAwake(_ on: Bool) {
        if on, playbackActivity == nil { playbackActivity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Playing a cut") }
        if !on, let a = playbackActivity { ProcessInfo.processInfo.endActivity(a); playbackActivity = nil }
    }
    /// Registers the inverse of a director action for Edit › Undo.
    func registerUndo(_ name: String, _ inverse: @escaping @MainActor (FilmModel) -> Void) {
        undoManager?.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { inverse(model) } }
        undoManager?.setActionName(name)
    }
    private func didReachEnd() {
        if room == .screening { screeningEnded = true }
        if playingChanges { nextChange() }
    }

    // MARK: Screening

    func startScreening() {
        screeningStartedAt = Date(); screeningMarkIDs = []; screeningEnded = false
        if position >= duration - 0.5 { seek(0) }
        if !isPreview { player.play(); playing = true }
    }
    /// Press N: drops a mark without stopping playback. Each mark becomes a numbered draft.
    func mark() {
        guard duration > 0 else { return }
        let t = min(position, max(0, duration - 1 / fps))
        if let c = addNote(text: "", time: t, state: .draft) {
            screeningMarkIDs.append(c.id); freshMarkID = c.id
            toast = Toast(title: "Mark \(c.number ?? screeningMarkIDs.count) at \(Timecode.format(t, fps: fps))", detail: "Keep watching. Write it after.", glass: room == .screening)
            Task { try? await Task.sleep(for: .milliseconds(1200)); if freshMarkID == c.id { freshMarkID = nil } }
        }
    }
    func endScreening(showEndCard: Bool = true) {
        if showEndCard && room == .screening { pause(); screeningEnded = true; return }
        screeningEnded = false; screeningStartedAt = nil
    }
    func writeNotesAfterScreening() {
        screeningEnded = false
        notesTab = .sheet
        selectedNoteID = draftNotes.first?.id
        if let first = draftNotes.first, let t = noteTime(first) { seek(t) }
        go(.notes); composerFocus += 1
    }

    // MARK: Notes actions

    @discardableResult
    func addNote(text: String, kind: NoteKind? = nil, time: Double? = nil, range: ClosedRange<Double>? = nil, region: CGRect? = nil, sceneID: String? = nil, scriptAction: ScriptAction? = nil, state: NoteState = .written) -> ReviewComment? {
        guard let store, let p = displayed ?? project else { return nil }
        do {
            let r = range.map { MediaRange(start: $0.lowerBound, end: $0.upperBound) }
            let mt = r == nil ? time.map { MediaTime(seconds: $0) } : nil
            let frameRegion = region.map { FrameRegion(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) }
            let c = try store.addComment(text: text, sequenceID: sequence?.id, revision: p.editRevision, cutID: watchedCut?.id, range: r, time: mt, region: frameRegion, extra: NoteFields(kind: kind, noteState: state, scriptAction: scriptAction, sceneID: sceneID))
            refresh(force: true)
            return c
        } catch { self.error = error.localizedDescription; return nil }
    }
    /// The composer's Add: writes up the selected draft, or adds a new note at the current anchor.
    func submitComposer() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let id = selectedNoteID, let c = note(id), c.lifecycle == .draft {
            perform { try $0.editNote(id: id, text: text, kind: .some(self.draftKind), region: self.region.map { .some(FrameRegion(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height)) }) }
            selectedNoteID = draftNotes.first { $0.id != id }?.id
        } else {
            switch anchorMode {
            case .moment: addNote(text: text, kind: draftKind, time: position)
            case .range: addNote(text: text, kind: draftKind, range: rangeSelection ?? position...min(duration, position + 1))
            case .region: addNote(text: text, kind: draftKind, time: position, region: region)
            case .scene: addNote(text: text, kind: draftKind, sceneID: stripScene(at: position).flatMap { s in dailies.scenes.first { $0.id == s.id }?.id })
            case .wholeCut: addNote(text: text, kind: draftKind)
            }
        }
        draftText = ""; draftKind = nil; region = nil; drawingRegion = false; rangeSelection = nil; anchorMode = .moment
    }
    func dropNote(_ id: String) { perform { try $0.dropNote(id: id) }; registerUndo("Drop Note") { $0.restoreNote(id) } }
    func restoreNote(_ id: String) { perform { try $0.restoreNote(id: id) }; registerUndo("Restore Note") { $0.dropNote(id) } }
    func editNote(_ id: String, text: String? = nil, kind: NoteKind?? = nil) { perform { _ = try $0.editNote(id: id, text: text, kind: kind) } }
    func select(_ c: ReviewComment) {
        selectedNoteID = c.id
        if let t = noteTime(c) { pause(); seek(t) }
        region = c.region.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        if c.lifecycle == .draft { draftText = ""; draftKind = nil; composerFocus += 1 }
    }
    func acceptOutside(_ id: String, text: String? = nil) { perform { try $0.acceptOutside(id: id, text: text) } }
    func declineOutside(_ id: String) { perform { try $0.declineOutside(id: id) } }

    // MARK: Turnover and read-back

    @AppStorage("defaultLatitude") @ObservationIgnored var defaultLatitude = Latitude.faithful.rawValue
    @AppStorage("waitForReadBack") @ObservationIgnored var waitForReadBack = true
    func turnOver(latitude: Latitude, waitForOK: Bool) {
        let ids = readyNotes.map(\.id)
        perform { _ = try $0.turnOver(noteIDs: ids, latitude: latitude, waitForOK: waitForOK, cutID: self.watchedCut?.id, sequenceID: self.sequence?.id) }
        sheet = nil
    }
    func assembleFromCircles() {
        perform { _ = try $0.turnOver(noteIDs: [], kind: "assembly", latitude: Latitude(rawValue: self.defaultLatitude) ?? .faithful, waitForOK: false, cutID: nil, sequenceID: self.sequence?.id) }
    }
    func approveReadBack() { guard let t = openTurnover else { return }; perform { _ = try $0.approveReadBack(turnoverID: t.id) } }
    func adjustReadBack(noteID: String, text: String) { guard let t = openTurnover else { return }; perform { _ = try $0.adjustReadBack(turnoverID: t.id, noteID: noteID, text: text) } }
    func flipConflict(noteID: String) { guard let t = openTurnover else { return }; perform { _ = try $0.flipConflict(turnoverID: t.id, noteID: noteID) } }
    func takeNotesBack() { guard let t = openTurnover else { return }; perform { try $0.cancelTurnover(t.id) } }
    func answer(_ q: EditorQuestion, choiceID: String?, text: String?) { perform { _ = try $0.answerQuestion(id: q.id, choiceID: choiceID, text: text) } }

    // MARK: Changes

    func acceptAnswer(_ noteID: String) { perform { try $0.acceptAnswer(noteID: noteID) }; registerUndo("Accept") { m in m.perform { try $0.unacceptAnswer(noteID: noteID) } } }
    func pickOption(_ noteID: String, _ label: String) { let old = note(noteID)?.latestAnswer?.pick; perform { try $0.pickOption(noteID: noteID, label: label) }; if let old { registerUndo("Pick Option") { $0.pickOption(noteID, old) } } }
    func reopen(_ noteID: String, text: String) {
        let turnoverID = note(noteID)?.turnoverID
        perform { try $0.reopenAnswer(noteID: noteID, text: text) }
        registerUndo("Reply") { m in m.perform { try $0.undoReopen(noteID: noteID, turnoverID: turnoverID) } }
    }
    func playChanges() {
        let reel = changeReel(in: watchedCut)
        guard !reel.isEmpty else { return }
        playingChanges = true; changeIndex = 0; seek(reel[0].lowerBound); if !isPreview { player.play(); playing = true }
    }
    func nextChange() {
        let reel = changeReel(in: watchedCut)
        changeIndex += 1
        guard reel.indices.contains(changeIndex) else { stopChanges(); return }
        seek(reel[changeIndex].lowerBound)
    }
    func previousChange() { changeIndex = max(0, changeIndex - 1); let reel = changeReel(in: watchedCut); if reel.indices.contains(changeIndex) { seek(reel[changeIndex].lowerBound) } }
    func stopChanges() { playingChanges = false; pause() }
    /// Keeps Play changes inside the reel: jumps over untouched picture.
    func tickChanges() {
        guard playingChanges else { return }
        let reel = changeReel(in: watchedCut)
        guard reel.indices.contains(changeIndex) else { return }
        if position >= reel[changeIndex].upperBound { nextChange() }
    }

    // MARK: Dailies

    func setCircle(_ assetID: String, _ on: Bool) { perform { try $0.setCircle(assetID: assetID, circled: on) }; registerUndo(on ? "Circle Take" : "Uncircle Take") { $0.setCircle(assetID, !on) } }
    func moveTake(_ assetID: String, to sceneID: String?) { let old = dailies.take(assetID).sceneID; perform { try $0.setTakeScene(assetID: assetID, sceneID: sceneID) }; registerUndo("Move Take") { $0.moveTake(assetID, to: old) } }
    func setUnusable(_ assetID: String, _ on: Bool) { perform { try $0.setUnusable(assetID: assetID, unusable: on) }; registerUndo(on ? "Mark Not Usable" : "Mark Usable") { $0.setUnusable(assetID, !on) } }
    @discardableResult
    func addScene(title: String = "New scene") -> String? {
        guard let store else { return nil }
        do { let s = try store.addScene(title: title); refresh(force: true); return s.id } catch { self.error = error.localizedDescription; return nil }
    }
    func moveTake(_ assetID: String, toSetup code: String?) { let old = dailies.take(assetID).setupCode; perform { try $0.setTakeSetup(assetID: assetID, setupCode: code) }; registerUndo("Move Take") { $0.moveTake(assetID, toSetup: old) } }
    var circledCount: Int { dailies.takes.values.filter(\.circled).count }
    var suggestedCount: Int { dailies.takes.values.filter { $0.suggestion != nil && !$0.circled }.count }

    // MARK: Locks

    func lockScene(_ id: String, _ on: Bool) { perform { try $0.lockScene(id: id, locked: on) }; registerUndo(on ? "Lock Scene" : "Unlock Scene") { $0.lockScene(id, !on) } }
    func lockPicture() { perform { try $0.lockPicture(cutID: self.watchedCut?.id, locked: true) }; sheet = nil; go(.finish) }
    func unlockPicture() { perform { try $0.lockPicture(cutID: nil, locked: false) } }
    var picturelockBlockers: [String] {
        var out: [String] = []
        let open = notes.filter { $0.visibleToEditor && ![.accepted, .dropped].contains($0.lifecycle) && !$0.inInbox }
        if !open.isEmpty { out.append("\(open.count) notes still open") }
        if !openQuestions.isEmpty { out.append("\(openQuestions.count) questions waiting") }
        if !inbox.isEmpty { out.append("\(inbox.count) outside notes waiting") }
        return out
    }

    // MARK: Brief and footage

    func saveBrief(_ b: Brief) { brief = b; perform { try $0.saveBrief(b) } }
    func importFootage(_ urls: [URL]) {
        guard let runtime else { return }
        Task {
            for url in urls {
                do {
                    // Footage goes to the library; the editor builds the assembly from circles.
                    _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(url.path), "append": .bool(false)]))
                } catch { self.error = "\(url.lastPathComponent): \(error.localizedDescription)" }
                refresh(force: true)
            }
        }
    }
    func chooseFootage() {
        let panel = NSOpenPanel(); panel.title = "Bring footage"; panel.allowedContentTypes = [.movie, .audio, .image, .folder]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        var files: [URL] = []
        for url in panel.urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let items = (FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
                files += items.filter { ["mov", "mp4", "m4v", "mxf", "wav", "m4a", "mp3", "aif", "aiff", "jpg", "png"].contains($0.pathExtension.lowercased()) }
            } else { files.append(url) }
        }
        importFootage(files.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }

    // MARK: Editor

    func setEditorPaused(_ on: Bool) { perform { _ = try $0.updateDirectingState(summary: on ? "Paused the editor" : "Resumed the editor") { $0.editorPaused = on } } }
    /// Words a director can paste to their agent; in-app turnovers don't wake it.
    var editorRequest: String {
        guard let url else { return "" }
        if let t = openTurnover { return t.kind == "assembly" ? "Build the assembly for my Direction film at \(url.path) from my circled takes." : "Pick up turnover \(t.number) in my Direction film at \(url.path): read it back, then cut." }
        return "Check my Direction film at \(url.path) for anything waiting on you."
    }
    func copyEditorRequest() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(editorRequest, forType: .string); toast = Toast(title: "Copied for your editor", detail: "Paste it into Claude Code or Codex.", editor: true) }

    // MARK: Helpers

    func perform(_ body: (ProjectStore) throws -> Void) {
        guard let store else { return }
        do { try body(store); refresh(force: true) } catch { self.error = error.localizedDescription; refresh(force: true) }
    }
}

/// UserDefaults keys for Settings › Notifications. Default on.
enum NotificationKey {
    static let cutReady = "notifyCutReady", question = "notifyQuestion", cant = "notifyCant", delivery = "notifyDelivery"
}
