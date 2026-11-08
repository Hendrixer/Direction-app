import Foundation
import SwiftUI
import AppKit
import AVKit
import Observation
import DirectionCore
import DirectionMedia
import DirectionTools

enum Room: String, CaseIterable, Identifiable {
    case script, breakdown, dailies, cut, finish
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var shortcut: KeyEquivalent { KeyEquivalent(Character(String((Room.allCases.firstIndex(of: self) ?? 0) + 1))) }
}

enum ActiveSheet: String, Identifiable { case turnover, lockPicture, deliver, share, relink, brief
    case look
    /// Who's editing? (frame 56)
    case editorSetup
    /// Learn a technique from a video (techniques.md).
    case learnTechnique
    /// Make a style from a video (styles.md › From a video).
    case styleFromVideo
    var id: String { rawValue }
}

enum NotesTab: String { case sheet, questions, outside }
enum OnboardingStep: Int, Comparable { case brief, footage
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
    /// Prep: the A/V script and its breakdown (specs/script.md, specs/breakdown.md).
    var script: AVScript?
    var breakdown: Breakdown?
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
    /// An alert's text. Every one also goes in Direction's log.
    var error: String? { didSet { if let error, error != oldValue, !isPreview { DirectionLog.error("Alert in \(filmName): \(error)") } } }

    // MARK: Navigation
    var room: Room = .cut
    var sheet: ActiveSheet?
    /// What Direction is doing to get a video ready to learn from (a technique, a style), while it does.
    var learning: String?
    /// Brief references being studied, and why one couldn't be (styles.md › In the brief).
    var studyingReferences: Set<String> = []
    var referenceProblems: [String: String] = [:]
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
    /// Stepping a frame at a time: the time shows the frame too.
    var showsFrames = false
    var isPreparing = false

    // MARK: Notes
    var notesTab: NotesTab = .sheet
    var selectedNoteID: String?
    /// The words and kind of the note being written in its row.
    var draftText = ""
    var draftKind: NoteKind?
    /// A stretch on the strip while it's drawn or pulled; the note keeps it once you let go.
    var rangeSelection: ClosedRange<Double>?
    /// A box on the picture while it's drawn, moved or resized; the note keeps it once you let go.
    var region: CGRect?
    /// Draw a box: the next drag on the picture makes a note with it.
    var drawingRegion = false
    /// Mark a stretch: the next drag along the strip makes a note on it.
    var drawingStretch = false
    /// Bump to put the caret in the note being written.
    var composerFocus = 0
    var showDropped = false

    // MARK: Watching through
    /// The Cut room's full-screen mode: the cut straight through, N for marks (specs/cut.md › Watch through).
    var watchingCut = false
    var screeningStartedAt: Date?
    var screeningMarkIDs: [String] = []
    var freshMarkID: String?

    // MARK: Dailies
    var selectedSceneID: String?
    var openTakeID: String?

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
        // Previews show the editor as your own session unless a fixture says Direction starts it.
        if preview { runs.previewStarts = false }
        guard !preview else { return }
        player.automaticallyWaitsToMinimizeStalling = false
        let output = UserDefaults.standard.string(forKey: "audioOutput") ?? ""
        player.audioOutputDeviceUniqueID = output.isEmpty ? nil : output
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1 / 24, preferredTimescale: 600), queue: .main) { [weak self] time in
            // Not while a seek is on its way: the player still reports where it was, and the playhead
            // would jump back from where you clicked.
            MainActor.assumeIsolated { guard let self, time.seconds.isFinite, !self.isPreparing, !self.seeking else { return }; self.position = time.seconds; self.playing = self.player.rate > 0; self.keepAwake(self.playing) }
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
        copyStallingTakes()
    }

    /// Takes brought in before Direction copied files with open keyframes stall playback where a cut starts
    /// just before one: each gets its copy now, in place (SeekableCopy).
    func copyStallingTakes() {
        guard let store, let runtime else { return }
        Task {
            let copied = await SeekableCopy.copyTakes(in: store, checked: runtime.cacheDirectory.appendingPathComponent("keyframes-checked.json"))
            guard let first = copied.first else { return }
            refresh(force: true)
            toast = copied.count == 1
                ? Toast(title: "Made a copy of \(first.name) that plays from any frame", detail: "Its file was written in a way that stalled playback. The copy is in the film\u{2019}s Footage folder, with the same picture and sound; the original stays as it is.")
                : Toast(title: "Made copies of \(copied.count) takes that play from any frame", detail: "Their files were written in a way that stalled playback. The copies are in the film\u{2019}s Footage folder, with the same picture and sound; the originals stay as they are.")
        }
    }

    // Phase 2 areas, each refreshed with the film (Sources/DirectionApp/Phase2).
    let runs = EditorRunsModel(), index = FootageIndexModel(), looks = LooksModel(), graphics = GraphicsModel(), made = MadeModel()

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
        // The window's ⌘Z outlives the film: the next film's must not undo this one's steps.
        undoManager?.removeAllActions(withTarget: self)
        if let runtime { Task { await runtime.cancelAll() } }
    }

    // MARK: Loading

    /// Events that change only what the editor is doing, not the film: while it works they come several times a
    /// second, so they read only their own part again. Any other event reads the whole film.
    private static let workingKinds: Set<String> = ["editor.activity", "editor.run", "editor.status", "job.updated", "index.updated",
                                                    "graphic.updated", "graphic.words", "made.created", "look.updated", "look.proposed", "look.camera", "transcript.updated"]

    func refresh(force: Bool = false) {
        guard let store else { return }
        do {
            let latest = try store.eventCursor()
            guard force || latest != cursor else { return }
            let newEvents = try store.events(since: max(0, cursor))
            let kinds = Set(newEvents.map(\.kind))
            let whole = force || cursor < 0 || newEvents.count >= 500 || !kinds.isSubset(of: Self.workingKinds)
            func changed(_ k: String...) -> Bool { whole || !kinds.isDisjoint(with: k) }
            // Only what differs is set, so a room isn't drawn again for nothing.
            func set<T: Equatable>(_ path: ReferenceWritableKeyPath<FilmModel, T>, _ value: T) { if self[keyPath: path] != value { self[keyPath: path] = value } }
            if whole {
                set(\.project, try store.read())
                set(\.brief, try store.brief()); set(\.dailies, try store.dailies()); set(\.directing, try store.directingState())
                set(\.notes, try store.notes()); set(\.cuts, try store.cuts().sorted { $0.createdAt < $1.createdAt })
                set(\.turnovers, try store.turnovers()); set(\.questions, try store.questions())
                set(\.script, try store.script()); set(\.breakdown, try store.breakdown())
            }
            if changed("editor.status") { set(\.editorStatus, try store.editorStatus()) }
            if changed("transcript.updated") { set(\.transcripts, try store.transcripts()) }
            if changed("job.updated") { set(\.jobs, try store.jobs()) }
            if !newEvents.isEmpty { events = Array((events + newEvents).suffix(200)) }
            cursor = latest
            // Takes whose slate names a shot go to it as soon as their file name or first words say so.
            if whole, breakdown?.isOK == true, !((try? store.fileBySlate())?.isEmpty ?? true) { set(\.dailies, try store.dailies()) }
            if whole {
                announceDeliveredCuts()
                announceQuestions()
            }
            if changed("look.updated", "look.proposed", "look.camera") { loadDisplayed() }
            // The index first: whether the editor may start logging depends on what it's still doing.
            if changed("index.updated", "job.updated") { index.refresh(self) }
            runs.refresh(self)
            if changed("look.updated", "look.proposed", "look.camera") { looks.refresh(self) }
            if changed("graphic.updated", "graphic.words") { graphics.refresh(self) }
            if changed("made.created") { made.refresh(self) }
        } catch { self.error = error.localizedDescription }
    }

    private func announceDeliveredCuts() {
        for t in turnovers where t.state == .delivered && !knownDelivered.contains(t.id) {
            knownDelivered.insert(t.id)
            guard let cut = cuts.first(where: { $0.id == t.resultCutID }) else { continue }
            sweepToken += 1
            if t.kind == "assembly" {
                // Nothing to review yet: screen it (start.md › 06).
                let length = ((try? project?.sequence(cut.sequenceID))??.duration.seconds).map { " " + Timecode.duration($0) + "." } ?? ""
                toast = Toast(title: "The assembly is ready.\(length)", detail: "Nobody else sees it until you\u{2019}ve screened it. Watch it once all the way through.", editor: true, actionTitle: watchingCut ? nil : "Watch it", run: { [weak self] in self?.watchThrough() })
                onNotify?("The assembly is ready", "\(filmName) · screen it when you\u{2019}re ready", NotificationKey.cutReady)
                continue
            }
            let answers = notes.filter { $0.latestAnswer?.cutID == cut.id }.count
            // Nothing starts playing on its own: the notice offers the whole cut, or only what moved.
            toast = Toast(title: "\(cut.name) is ready", detail: "\(answers) answers · \(Timecode.duration(changesDuration(in: cut))) of changes to watch", editor: true,
                          actionTitle: "Play changes", run: { [weak self] in self?.openChangesReel() },
                          secondTitle: "Watch through", secondRun: { [weak self] in self?.watchThrough() })
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
        let revision = watchedCut.map(revision(of:)) ?? project?.editRevision ?? 0
        if force || displayed?.editRevision != revision || displayed == nil || takesMoved {
            displayed = (try? store.read(revision: revision)) ?? project
        }
        preparePlayback()
    }
    /// A take in the watched cut now plays from another file (relinked, or copied so it plays from any frame):
    /// the cut is read again, since every revision plays a take from where it is now.
    private var takesMoved: Bool {
        guard let shown = displayed, let now = project else { return false }
        let files = Dictionary(now.assets.map { ($0.id, $0.path) }, uniquingKeysWith: { a, _ in a })
        return shown.assets.contains { a in files[a.id].map { $0 != a.path } ?? false }
    }

    // MARK: Derived: cuts and sequences

    var latestCut: ReviewCut? { cuts.last }
    /// What a cut plays and delivers: the picture-locked cut with its finishing (ProjectStore.playedRevision).
    func revision(of cut: ReviewCut) -> Int { (try? store?.playedRevision(of: cut)) ?? cut.editRevision }
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
    /// The takes: what the director brought in, not the editor's graphics or its own sound files.
    var footage: [MediaAsset] {
        guard let p = project else { return [] }
        return store.map { p.footage(film: $0.url) } ?? p.assets
    }

    /// Scenes as they sit in the watched cut, from the clips on the story's layer, end to end from 0: a stretch
    /// with no story under it (a title card alone on V3, black at the end) is a plain passage of its own, so
    /// every moment of the cut has a place on the strip.
    var stripScenes: [StripScene] {
        guard let sequence else { return [] }
        let story = sequence.storyLayer
        let clips = sequence.clips.filter { $0.kind == .video && $0.layer == story }.sorted { $0.start < $1.start }
        var out: [StripScene] = []
        let changed = changedRanges(in: watchedCut)
        // What plays in a stretch with no story: the top picture there, if any.
        func passage(_ a: Double, _ b: Double) -> StripScene {
            let over = sequence.clips.filter { $0.kind == .video && $0.start.seconds < b && $0.end.seconds > a }.max { $0.layer < $1.layer }
            return StripScene(id: "passage-\(a)", number: 0, title: "", start: a, end: b, art: .room, thumbnail: asset(over?.assetID)?.thumbnailPath, passage: true)
        }
        for (i, clip) in clips.enumerated() {
            let scene = dailies.scene(for: clip.assetID)
            let start = clip.start.seconds, end = clip.end.seconds
            if start - (out.last?.end ?? 0) > 0.05 { out.append(passage(out.last?.end ?? 0, start)) }
            if let last = out.last, let scene, last.id == scene.id, abs(last.end - start) < 0.05 { out[out.count - 1].end = end; continue }
            let number = scene?.number ?? (i + 1)
            out.append(StripScene(id: scene?.id ?? clip.id, number: number, title: scene?.title ?? (dailies.scenes.isEmpty ? clip.name : ""), start: start, end: end, art: FootageArt.forScene(number), thumbnail: asset(clip.assetID)?.thumbnailPath, locked: scene?.locked ?? false))
        }
        if let last = out.last, duration - last.end > 0.05 { out.append(passage(last.end, duration)) }
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

    /// The program the editor runs on: the running one's, the one chosen for this film (or in Settings), or your
    /// own session's when it says which it is.
    var editorProgram: EditorProgram? {
        if let p = runs.active.flatMap({ EditorProgram(rawValue: $0.program) }) { return p }
        if let p = runs.runsOn.program { return p }
        let agent = editorStatus?.agent?.lowercased() ?? ""
        return agent.contains("claude") ? .claudeCode : agent.contains("codex") ? .codex : nil
    }

    var pill: EditorPillState {
        if offline { return .offline }
        if directing.editorPaused || runs.isPaused { return .paused }
        // The editor can't cut scenes whose takes are missing; say so until they're found.
        if missingTakes > 0 { return .needsFootage }
        // Direction starts the editor: a stopped run, no program yet, or work held for your Start.
        if runs.startsEditor {
            if runs.failed != nil { return .stopped }
            if !runs.ready { return .notSetUp }
            if let h = runs.held { return .readyToCut(h.job == .logFootage ? "Ready to log" : "Ready to cut") }
            if runs.stoppedLogging != nil { return .readyToCut("Ready to log") }
            if openTurnover.map({ runs.run(for: $0)?.state == .stopped }) == true { return .readyToCut("Ready to cut") }
        }
        // Spend questions (made-media.md) count as questions.
        let cants = openQuestions.filter { $0.kind == "cant" }.count, asks = openQuestions.filter { $0.kind != "cant" }.count
        if let t = openTurnover {
            let total = max(1, t.noteIDs.count), done = t.progress.values.filter { $0 == .done }.count
            switch t.state {
            // Once Direction has started the editor, a turnover nobody has read back yet is being read.
            case .waiting where runs.isWorking: return t.kind == "assembly" ? .assembling("Building the assembly", nil) : .readingBack("Reading back")
            case .waiting: return .waiting
            case .readBack: return t.readBackApproved ? .working("Starting", nil) : asks > 0 ? .asks(asks) : .readBackReady
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
        if isPictureLocked, runs.active?.job == .finish {
            let mine = (directing.finishing ?? []).filter { $0.by.contains("editor") }, done = mine.filter { ["done", "needsYou"].contains($0.state) }.count
            if !mine.isEmpty { return .working("Finishing \(min(mine.count, done + 1)) of \(mine.count)", Double(done) / Double(mine.count)) }
        }
        if isPictureLocked, let item = directing.finishing?.first(where: { $0.state == "working" && $0.by.contains("editor") }) { return .working(item.title == "Sound mix" ? "Mixing sound" : item.title, item.progress) }
        if let cut = latestCut, !unreviewedAnswers.isEmpty, openTurnover == nil { return .cutReady("\(cut.name) ready") }
        if assemblyAwaitsScreening, openTurnover == nil { return .cutReady("Assembly ready") }
        // Before logging, the index looks at every take (footage-index.md).
        if let l = index.looking { return .looking(l.done, l.total) }
        if let l = index.listening, isLogging { return .listening(l.done, l.total) }
        if isLogging, case let total = footage.count, total > 0, cuts.isEmpty || runs.active?.job == .logFootage {
            return .working("Logging \(loggedCount) of \(total)", Double(loggedCount) / Double(total))
        }
        // Prep: how far the picture column has come; the breakdown, by name.
        if runs.active?.job == .script, let s = script, case let done = s.rows.filter({ !$0.picture.isEmpty }).count, done < s.rows.count {
            return .working("Writing pictures \(done) of \(s.rows.count)", Double(done) / Double(max(1, s.rows.count)))
        }
        if runs.active?.job == .breakdown, let s = script, !s.rows.isEmpty {
            let covered = Set(breakdown?.shots.flatMap(\.rowIDs) ?? []).count
            return .working("Breaking down \(covered) of \(s.rows.count)", Double(covered) / Double(s.rows.count))
        }
        // Any other work: what the editor is doing right now, whether Direction started it or you did.
        if runs.isWorking || runs.ownSession != nil { return .working(runs.activityText ?? "Starting", nil) }
        return .ready
    }
    var isPictureLocked: Bool { directing.pictureLocked }
    /// Before a film has footage logged, the window walks through Brief → Footage; then it's the
    /// rooms. The assembly is built like any cut, from the room you asked for it in (start.md › 06).
    /// The director left onboarding early (Open Dailies while the editor is still logging).
    var onboardingDismissed = false
    var onboardingStep: OnboardingStep? {
        // A film that starts from a script works in its rooms from the start (specs/script.md).
        guard !onboardingDismissed, script == nil, cuts.isEmpty, openTurnover?.kind != "assembly" else { return nil }
        if !brief.isComplete { return .brief }
        if !hasFootage { return .footage }
        // Footage is in but the editor hasn't logged every take yet, or more is still coming in: Logging footage.
        if isLogging || importingFootage > 0 { return .footage }
        return nil
    }
    /// The only cut is the assembly, and it hasn't been screened or noted yet.
    var assemblyAwaitsScreening: Bool {
        guard cuts.count == 1, notes.isEmpty, turnovers.contains(where: { $0.kind == "assembly" && $0.state == .delivered && $0.resultCutID == cuts[0].id }) else { return false }
        if isPreview { return previewAssemblyReady }
        return project.map { UserDefaults.standard.integer(forKey: "screenings.\($0.id)") == 0 } ?? false
    }
    /// Snapshots of the first look once the assembly is in.
    var previewAssemblyReady = false
    /// Takes the editor has logged, out of all footage.
    var loggedCount: Int { footage.filter { dailies.isLogged($0.id) }.count }
    var isLogging: Bool { hasFootage && footage.contains { !dailies.isLogged($0.id) } }
    var defaultRoom: Room {
        // A film from a script works in prep until its footage is in.
        if cuts.isEmpty, let script { return !script.isOK ? .script : hasFootage ? .dailies : .breakdown }
        if cuts.isEmpty { return .dailies }
        if isPictureLocked && unreviewedAnswers.isEmpty { return .finish }
        return .cut
    }
    func badge(for room: Room) -> (String, Bool)? {
        switch room {
        // What waits on the director in the cut: the editor's answers and questions first, in its color; then
        // marks to write up and outside notes to decide, in yours.
        case .cut:
            let editor = unreviewedAnswers.count + openQuestions.count
            if editor > 0 { return (String(editor), false) }
            let n = draftNotes.count + inbox.count; return n > 0 ? (String(n), true) : nil
        // The editor's questions on the script and the breakdown, in its color, so they're seen before the room is.
        case .script: let n = script?.openQuestions.count ?? 0; return n > 0 ? (String(n), false) : nil
        case .breakdown: let n = breakdown?.shots.filter { $0.question?.isOpen == true }.count ?? 0; return n > 0 ? (String(n), false) : nil
        default: return nil
        }
    }
    /// The rooms this film uses. One started from its footage, with no script, has no prep: Script and
    /// Breakdown come back the moment a script or a story is brought in (File › Bring In a Script…).
    func isShown(_ room: Room) -> Bool {
        guard room == .script || room == .breakdown else { return true }
        return script != nil || breakdown != nil || (!hasFootage && cuts.isEmpty)
    }
    func isEnabled(_ room: Room) -> Bool {
        guard isShown(room) else { return false }
        return switch room {
        case .finish: isPictureLocked
        // Nothing to watch or note before the first cut.
        case .cut: !cuts.isEmpty
        // There’s nothing to break down until the script is OK’d.
        case .breakdown: script?.isOK == true || breakdown != nil
        default: true
        }
    }
    /// `force`: the room's reason to open is in the store already, ahead of the next refresh (a script just read).
    func go(_ room: Room, force: Bool = false) {
        guard force || isEnabled(room) else { return }
        if watchingCut && room != .cut { endScreening(writeUp: false) }
        // The cut stops where it is when you change rooms; nothing plays in a room you can't see it in.
        if self.room != room, playing || playingChanges { if playingChanges { stopChanges() } else { pause() } }
        // The room is there the moment its tab is clicked: nothing fades or slides in.
        var now = Transaction(); now.disablesAnimations = true
        withTransaction(now) { self.room = room }
    }
    /// W: the cut full screen, straight through, from wherever you are (specs/cut.md › Watch through).
    func watchThrough() {
        guard isEnabled(.cut) else { return }
        if room != .cut { go(.cut) }
        if changes.reelOpen { closeReel() }
        var now = Transaction(); now.disablesAnimations = true
        withTransaction(now) { watchingCut = true }
        startScreening()
    }

    // MARK: Playback

    func preparePlayback(force: Bool = false) {
        guard !isPreview, let p = displayed, let sequence, let runtime else { return }
        // The look is kept outside the revisions, so choosing one (or undoing it) changes the key too; so does a
        // take playing from another file.
        let looks = try? runtime.store.lookContext()
        let key = "\(p.editRevision):\(sequence.id):\(looks?.hashValue ?? 0):\(p.assets.map(\.path).hashValue)"
        guard force || key != renderKey else { return }
        renderKey = key; renderTask?.cancel(); isPreparing = true; pendingSeek = position
        if sequence.clips.isEmpty { player.pause(); player.replaceCurrentItem(with: nil); compiled = nil; isPreparing = false; return }
        renderTask = Task {
            do {
                let result = try await SequenceRenderer.compile(project: p, sequenceID: sequence.id, cacheDirectory: runtime.cacheDirectory, previewMaxDimension: 1920, looks: looks)
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
        // Another cut's answers start folded, the way the sheet first shows them.
        if (cut?.id ?? latestCut?.id) != watchedCut?.id { changes.sticky = []; changes.showAllAnswers = false; selectedAnswerNoteID = nil }
        watchedCutID = cut?.id == latestCut?.id ? nil : cut?.id
        loadDisplayed(force: true)
    }
    /// The playhead moves at once; the player follows. Seeks wait for the one before (the newest
    /// wins), so a drag across a long 4K cut doesn't pile up seeks that each cancel the last.
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = max(0, min(seconds, duration))
        if isPreparing || isPreview { pendingSeek = position; return }
        seekTarget = position
        if !seeking { chaseSeek() }
    }
    @ObservationIgnored private var seekTarget: Double?
    @ObservationIgnored private(set) var seeking = false
    private func chaseSeek() {
        guard let target = seekTarget else { seeking = false; return }
        seekTarget = nil; seeking = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.chaseSeek() } }
        }
    }
    func togglePlayback() {
        guard !isPreview else { playing.toggle(); return }
        if player.rate > 0 { player.pause(); playing = false } else { if position >= duration - 0.03 { seek(0) }; player.play(); playing = true }
    }
    func pause() { player.pause(); playing = false }
    /// ← / →: a frame at a time. The time under the picture says which frame for a few seconds after.
    func step(frames: Double) {
        pause(); seek(position + frames / fps)
        guard abs(frames) < fps else { return }
        showsFrames = true
        framesHide?.cancel()
        framesHide = Task { [weak self] in try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { self?.showsFrames = false } }
    }
    @ObservationIgnored private var framesHide: Task<Void, Never>?
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
        if watchingCut { endScreening() }
        if playingChanges { nextChange() }
    }

    // MARK: Screening

    func startScreening() {
        screeningStartedAt = Date(); screeningMarkIDs = []
        if position >= duration - 0.5 { seek(0) }
        if !isPreview { player.play(); playing = true }
    }
    /// N: a note on this moment, with no words yet. Watching or playing, the picture never stops and the mark
    /// waits to be written; paused in the Cut room, its row opens to write in. Anywhere the sheet isn't showing
    /// (another room, Play changes) it waits to be written too, so no hidden row takes the keyboard.
    func mark() {
        guard duration > 0 else { return }
        let t = min(position, max(0, duration - 1 / fps))
        if let c = addNote(text: "", time: t, state: .draft) {
            // Only a watch's marks are written one after another (saveWriting).
            if watchingCut { screeningMarkIDs.append(c.id) }
            freshMarkID = c.id
            // Watching through keeps its own undo for marks (WatchThrough.swift).
            if !watchingCut { registerUndo("Mark") { $0.dropNote(c.id) } }
            if watchingCut || playing || room != .cut || changes.reelOpen {
                toast = Toast(title: "Mark \(c.number ?? screeningMarkIDs.count) at \(Timecode.format(t, fps: fps))", detail: "Keep watching. Write it after.", glass: watchingCut)
            } else {
                made(c)
            }
            Task { try? await Task.sleep(for: .milliseconds(1200)); if freshMarkID == c.id { freshMarkID = nil } }
        }
    }
    /// Esc, or the end of the cut: back to the sheet. Marks from this watch wait there as notes to write, the
    /// first one open; without marks the playhead stays where you stopped (specs/cut.md › Watch through).
    func endScreening(writeUp: Bool = true) {
        let marked = screeningMarkIDs.filter { id in note(id)?.lifecycle == .draft }
        pause()
        var now = Transaction(); now.disablesAnimations = true
        withTransaction(now) { watchingCut = false }
        screeningStartedAt = nil
        guard writeUp, let first = marked.first else { return }
        notesTab = .sheet
        if let c = note(first) { beginWriting(c) }
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
    func dropNote(_ id: String) { perform { try $0.dropNote(id: id) }; registerUndo("Drop Note") { $0.restoreNote(id) } }
    func restoreNote(_ id: String) { perform { try $0.restoreNote(id: id) }; registerUndo("Restore Note") { $0.dropNote(id) } }
    func editNote(_ id: String, text: String? = nil, kind: NoteKind?? = nil) { perform { _ = try $0.editNote(id: id, text: text, kind: kind) } }
    /// Selects a note and seeks to it. Its stretch shows on the strip and its box on the picture.
    func select(_ c: ReviewComment) {
        if notesUI.editingNoteID != nil, notesUI.editingNoteID != c.id { saveWriting(advance: false) }
        selectedNoteID = c.id
        selectedAnswerNoteID = nil
        cancelDrawing()
        if let t = noteTime(c) { pause(); seek(t) }
    }
    func acceptOutside(_ id: String, text: String? = nil) { perform { try $0.acceptOutside(id: id, text: text) } }
    func declineOutside(_ id: String) { perform { try $0.declineOutside(id: id) } }

    // MARK: Turnover and read-back

    @AppStorage("defaultLatitude") @ObservationIgnored var defaultLatitude = Latitude.faithful.rawValue
    @AppStorage("waitForReadBack") @ObservationIgnored var waitForReadBack = true
    /// Settings › Editor and Cutting as the editor will read them with the turnover.
    var editorPreferences: EditorPreferences {
        let d = UserDefaults.standard
        let order = (d.string(forKey: "conflictOrder") ?? "").split(separator: ",").compactMap { NoteKind(rawValue: String($0)) }
        return EditorPreferences(twoWaysForFeeling: d.object(forKey: "cutFeelingTwoWays") as? Bool ?? true, askBeforeGuessing: d.object(forKey: "askBeforeGuessing") as? Bool ?? true,
                                 conflictOrder: order.count == NoteKind.allCases.count ? order : NoteKind.allCases, handleSeconds: handleSeconds,
                                 musicDuckDB: d.object(forKey: SettingsKey.ducking) as? Double ?? 6)
    }
    func turnOver(latitude: Latitude, waitForOK: Bool) {
        let ids = readyNotes.map(\.id), prefs = editorPreferences
        // What you didn't push back on stays in the cut, the way it does in a cutting room: answers you hadn't
        // looked at are accepted with the turnover (specs/cut.md › Turning over).
        for id in unreviewedAnswers.map(\.id) { perform { try $0.acceptAnswer(noteID: id) } }
        perform { _ = try $0.updateDirectingState(summary: "Updated the editor's instructions") { $0.preferences = prefs; $0.latitude = latitude; $0.waitForOK = waitForOK } }
        perform { _ = try $0.turnOver(noteIDs: ids, latitude: latitude, waitForOK: waitForOK, cutID: self.watchedCut?.id, sequenceID: self.sequence?.id) }
        sheet = nil
    }
    func assembleFromCircles() {
        let prefs = editorPreferences
        perform { _ = try $0.updateDirectingState(summary: "Updated the editor's instructions") { $0.preferences = prefs } }
        perform { _ = try $0.turnOver(noteIDs: [], kind: "assembly", latitude: Latitude(rawValue: self.defaultLatitude) ?? .faithful, waitForOK: false, cutID: nil, sequenceID: self.sequence?.id) }
    }
    func approveReadBack() { guard let t = openTurnover else { return }; perform { _ = try $0.approveReadBack(turnoverID: t.id) } }
    func adjustReadBack(noteID: String, text: String) { guard let t = openTurnover else { return }; perform { _ = try $0.adjustReadBack(turnoverID: t.id, noteID: noteID, text: text) } }
    func flipConflict(noteID: String) { guard let t = openTurnover else { return }; perform { _ = try $0.flipConflict(turnoverID: t.id, noteID: noteID) } }
    func takeNotesBack() {
        guard let t = openTurnover else { return }
        // A run Direction started for it stops first, and its unfinished cut is discarded.
        if runs.startsEditor, runs.run(for: t) != nil { runs.takeTurnoverBack(self); return }
        perform { try $0.cancelTurnover(t.id) }
    }
    func answer(_ q: EditorQuestion, choiceID: String?, text: String?) { perform { _ = try $0.answerQuestion(id: q.id, choiceID: choiceID, text: text) } }

    // MARK: Changes

    func acceptAnswer(_ noteID: String) { perform { try $0.acceptAnswer(noteID: noteID) }; registerUndo("Accept") { m in m.perform { try $0.unacceptAnswer(noteID: noteID) } } }
    /// Puts that option's version in the cut. Undo puts back the one that played before.
    @discardableResult
    func pickOption(_ noteID: String, _ label: String) -> Bool {
        guard let store else { return false }
        let answer = note(noteID)?.latestAnswer, oldPick = answer?.pick, playing = answer?.optionInCut
        do { try store.pickOption(noteID: noteID, label: label) } catch { self.error = error.localizedDescription; refresh(force: true); return false }
        refresh(force: true)
        if let back = oldPick ?? playing, oldPick != label { registerUndo("Use \(label)") { m in m.perform { try $0.pickOption(noteID: noteID, label: back, record: oldPick != nil) } } }
        return true
    }
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

    /// Not in Sync, and Use This Take's Sound (footage-index.md › Sync).
    func unsync(_ assetID: String) { perform { try $0.unsync(assetID: assetID) } }
    /// Use This Take's Sound. The cut changes through the editor like any other note: where it plays
    /// the group's takes with another take's sound, a sound note for the next turnover asks for this one.
    func useSyncSound(_ assetID: String) {
        let before = dailies.syncGroup(for: assetID)?.soundAssetID
        perform { try $0.setSyncSound(assetID: assetID) }
        guard before != assetID, let g = dailies.syncGroup(for: assetID), g.soundAssetID == assetID, let range = soundNoteRange(g, sound: assetID) else { return }
        let label = dailiesLabel(dailies.take(assetID))
        guard let note = addNote(text: "Use \(label)\u{2019}s sound here; it\u{2019}s in sync.", kind: .sound, range: range) else { return }
        registerUndo("Use This Take\u{2019}s Sound") { m in
            m.perform { try $0.dropNote(id: note.id) }
            if let before { m.perform { try $0.setSyncSound(assetID: before) } }
        }
        toast = Toast(title: "Note \(note.number.map(String.init) ?? "") added: use \(label)\u{2019}s sound", detail: "The editor changes the cut at the next turnover.", actionTitle: "Open the Cut", run: { [weak self] in self?.go(.cut) })
    }

    /// Where the cut plays a group's takes with another take's sound: its own, or sound laid in sync under it.
    func soundNoteRange(_ g: SyncGroup, sound: String) -> ClosedRange<Double>? {
        guard let clips = sequence?.clips else { return nil }
        let members = Set(g.takes.map(\.assetID)), story = sequence?.storyLayer ?? 0
        let off = clips.filter { c in
            guard c.kind == .video, c.layer == story, let id = c.assetID, members.contains(id) else { return false }
            let laid = clips.first { $0.synced == true && $0.kind == .audio && $0.start < c.end && $0.end > c.start }?.assetID
            return (laid ?? id) != sound
        }
        guard let a = off.map(\.start.seconds).min(), let b = off.map(\.end.seconds).max(), b > a else { return nil }
        return a...b
    }
    func setCircle(_ assetID: String, _ on: Bool) { perform { try $0.setCircle(assetID: assetID, circled: on) }; registerUndo(on ? "Circle Take" : "Uncircle Take") { $0.setCircle(assetID, !on) } }
    func moveTake(_ assetID: String, to sceneID: String?) { let old = dailies.take(assetID).sceneID; perform { try $0.setTakeScene(assetID: assetID, sceneID: sceneID) }; registerUndo("Move Take") { $0.moveTake(assetID, to: old) } }
    func setUnusable(_ assetID: String, _ on: Bool) { perform { try $0.setUnusable(assetID: assetID, unusable: on) }; registerUndo(on ? "Mark Not Usable" : "Mark Usable") { $0.setUnusable(assetID, !on) } }
    @discardableResult
    func addScene(title: String = "New scene") -> String? {
        guard let store else { return nil }
        do { let s = try store.addScene(title: title); refresh(force: true); return s.id } catch { self.error = error.localizedDescription; return nil }
    }
    func deleteScene(_ id: String) {
        guard let store else { return }
        do {
            let (scene, takes) = try store.deleteScene(id: id)
            if selectedSceneID == id { selectedSceneID = scenes.first { $0.id != id }?.id }
            refresh(force: true)
            registerUndo("Delete Scene") { m in m.perform { try $0.restoreScene(scene, takes: takes) }; m.selectedSceneID = scene.id }
        } catch { self.error = error.localizedDescription }
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

    /// The scenes, setups and takes a note can name with "@" (cut.md › Naming footage).
    var footageNames: [FootageName] { FootageNames.all(dailies, assets: project?.assets ?? []) }

    /// A new shape changes the cut at once, with black where its shots don't reach; with `fill`, a note asks the
    /// editor to fill the frame instead. Returns that note's id. A shape that can't change now stays as it was.
    @discardableResult
    func saveBrief(_ b: Brief, fill: Bool = false) -> String? {
        var b = b, note: String?
        if b.shape != brief.shape {
            let changed = reshape(b.shape, fill: fill)
            if changed.ok { note = changed.note } else { b.shape = brief.shape }
        }
        brief = b; perform { try $0.saveBrief(b) }
        // A reference taken out takes its study with it.
        if let store, !isPreview { ReferenceVideo.cleanUp(b, film: store.url) }
        return note
    }
    /// Files on their way in. The footage step shows logging from the first one, not the drop zone.
    var importingFootage = 0
    /// The files themselves, in the order they come in, so logging lists each one from the moment it's dropped.
    var incomingFootage: [URL] = []
    /// Files being copied into the film (Settings › Storage › Copy into library), while they are.
    var copyingFootage: FootageCopying?
    /// `places`: where the director filed each file in scene and setup folders, by its path; those takes
    /// go to their scenes as they come in, before the editor logs (FootageFolders). Music goes to the
    /// library's Sounds instead, for every film (library.md), unless `musicAsFootage`.
    func importFootage(_ urls: [URL], places: [String: FootagePlace] = [:], musicAsFootage: Bool = false) {
        guard let runtime, let store, !urls.isEmpty else { return }
        // Settings › Storage: link to the originals, or copy them into the film's Footage folder first.
        let copies = UserDefaults.standard.string(forKey: SettingsKey.footageImport) == "copy" ? MediaAsset.copies(in: store.url) : nil
        importingFootage += urls.count
        incomingFootage += urls
        if copies != nil { var c = copyingFootage ?? FootageCopying(); c.total += urls.count; copyingFootage = c }
        Task {
            var toldHDR = false, toldSeekable = false, music: [(url: URL, name: String)] = []
            for url in urls {
                var file = url
                do {
                    // A song isn't a take: it's kept with the director's sounds, and a note names it with "@".
                    if !musicAsFootage, MediaLibrary.shelf(for: url) == .sounds, await LibraryMeasuring.isMusic(url) {
                        music.append((url, try MediaLibrary.sounds.add(url).name))
                        if copies != nil, var c = copyingFootage { c.done += 1; copyingFootage = c.done >= c.total ? nil : c }
                        importingFootage = max(0, importingFootage - 1); incomingFootage.removeAll { $0 == url }
                        continue
                    }
                    // HDR comes in as an SDR copy Direction makes in the Footage folder, and a file with open
                    // keyframes as a copy that plays from any frame, so neither is copied first.
                    let hdr = await SDRCopy.isHDR(url), seekable = hdr ? false : await SeekableCopy.isNeeded(url)
                    if hdr, !toldHDR {
                        toldHDR = true
                        toast = Toast(title: "Making SDR copies", detail: "Your HDR clips come in as SDR copies in the film\u{2019}s Footage folder. The originals stay as they are.")
                    }
                    if seekable, !toldSeekable {
                        toldSeekable = true
                        toast = Toast(title: "Making copies that play from any frame", detail: "Some of your clips were written in a way that stalls playback. They come in as copies in the film\u{2019}s Footage folder, with the same picture and sound. The originals stay as they are.")
                    }
                    if let copies, !hdr, !seekable { file = try await copyIn(url, to: copies) }
                    else if copies != nil, var c = copyingFootage { c.done += 1; copyingFootage = c.done >= c.total ? nil : c }
                    // Footage goes to the library; the editor builds the assembly from circles.
                    var args: [String: JSONValue] = ["path": .string(file.path), "append": .bool(false)]
                    // The film's rate comes from its first footage unless Settings › Cutting names one.
                    if let rate = Double(UserDefaults.standard.string(forKey: SettingsKey.frameRate) ?? "match") { args["frameRate"] = .number(rate) }
                    let imported = try await runtime.invoke("direction_import", arguments: .object(args))
                    if let place = places[url.path], let id = imported.value["asset"]["id"].string { perform { try $0.fileTakes([id: place]) } }
                } catch {
                    // Dropping a folder again brings in what's new; what's already in isn't a problem.
                    if (error as? DirectionError)?.code != "already_imported" { self.error = "\(url.lastPathComponent): \(error.localizedDescription)" }
                    // A copy no take uses isn't kept.
                    if file != url { refresh(force: true); if project?.assets.contains(where: { $0.path == file.path }) == false { try? FileManager.default.removeItem(at: file) } }
                }
                importingFootage = max(0, importingFootage - 1); incomingFootage.removeAll { $0 == url }
                refresh(force: true)
            }
            if let first = music.first {
                LibraryModel.shared.load(); LibraryModel.shared.measure()
                let songs = music.map(\.url)
                toast = Toast(title: music.count == 1 ? "\(first.name) is music, so it\u{2019}s in your Library" : "\(music.count) songs are in your Library",
                              detail: "Sounds you keep are there for every film, not taken as footage. " + (music.count == 1 ? "Name it in a note with @\(first.name)." : "Name one in a note with @ and its name."),
                              actionTitle: "Bring In as Footage", run: { [weak self] in self?.importFootage(songs, places: places, musicAsFootage: true) })
            }
        }
    }
    /// Copies one file into the Footage folder off the main thread, with how far it's got for the logging page and Dailies.
    func copyIn(_ url: URL, to folder: URL) async throws -> URL {
        let temp = folder.appendingPathComponent(".\(UUID().uuidString).copying")
        let size = max(1, (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.doubleValue ?? 1)
        let watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                let written = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? NSNumber)?.doubleValue ?? 0
                self?.copyingFootage?.current = min(1, written / size)
            }
        }
        defer {
            watch.cancel()
            if var c = copyingFootage { c.done += 1; c.current = 0; copyingFootage = c.done >= c.total ? nil : c }
        }
        return try await Task.detached(priority: .userInitiated) { try FootageFiles.copy(url, into: folder, via: temp) }.value
    }
    /// Dropped on the film: footage and sound come in, folders opened, held for the brief while it's being
    /// written. A script or a story becomes the A/V script.
    func bring(_ drop: FootageDrop) {
        if !drop.footage.isEmpty {
            if onboardingStep != nil { OnboardingSession.of(self).add(drop.footage, places: drop.places, wait: true) } else { importFootage(drop.footage, places: drop.places) }
        }
        // A new draft is the film's kind; the first file could be a script or a story, so Direction asks.
        if drop.footage.isEmpty, let script = drop.scripts.first {
            if self.script != nil { bringScript(script) } else if !isPreview, let kind = Self.askKind(script) { bringScript(script, as: kind) }
        }
        else if drop.footage.isEmpty { toast = Toast(title: "Those aren\u{2019}t video, sound or script files.") }
    }
    func chooseFootage() {
        let panel = NSOpenPanel(); panel.title = "Bring footage"; panel.allowedContentTypes = [.movie, .audio, .image, .folder]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        let drop = FootageFiles.route(panel.urls)
        importFootage(drop.footage, places: drop.places)
    }

    // MARK: Editor

    /// Pause Editor / Resume Editor. A session Direction started is interrupted after its current tool
    /// call and resumed with its saved session; your own session reads the flag.
    func setEditorPaused(_ on: Bool) {
        perform { _ = try $0.updateDirectingState(summary: on ? "Paused the editor" : "Resumed the editor") { $0.editorPaused = on } }
        guard runs.startsEditor else { return }
        if on { runs.pause(self) } else { runs.resume(self) }
    }
    /// Paused: by you, or a run Direction started.
    var editorIsPaused: Bool { directing.editorPaused || runs.isPaused }
    /// Who's editing? for this film: it keeps the choice, and the next new film starts from it.
    func chooseEditor(_ c: EditorRunsOn) {
        EditorSetup.choose(c)
        guard store != nil else { runs.choice = c; return }
        if directing.editor != c.rawValue { perform { _ = try $0.updateDirectingState(summary: "Who edits: \(c.label)") { $0.editor = c.rawValue } } }
        runs.choice = c
    }
    /// Speed and quality: the film's own, and what the next new film starts with. A run that hasn't
    /// started picks it up when it launches.
    func setQuality(_ q: FilmQuality) {
        EditorSetup.setDefaultQuality(q)
        guard store != nil, directing.quality != q else { return }
        perform { _ = try $0.updateDirectingState(summary: "Speed and quality: \(q.label)") { $0.quality = q } }
    }
    /// A film just started asks who's editing it, before any of its work starts.
    func askWhoEdits() { if sheet == nil { sheet = .editorSetup } }
    /// Try again: a new run of the same job when Direction starts the editor, else the request to copy.
    func retryEditor() { if runs.startsEditor && runs.failed != nil { runs.retry(self) } else { copyEditorRequest() } }
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
    /// "The editor stopped" (specs/editor.md › Notifications). Not in Settings; on unless set.
    static let editorStopped = "notifyEditorStopped"
}
