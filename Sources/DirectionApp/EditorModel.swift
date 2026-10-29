import Foundation
import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers
import Observation
import DirectionCore
import DirectionMedia
import DirectionTools

enum InspectorTab: String, CaseIterable { case feedback = "Notes", transcript = "Transcript", media = "Footage" }

@MainActor @Observable
final class EditorModel {
    var project: Project?
    var displayedProject: Project?
    var selectedSequenceID: String?
    var selectedAssetID: String?
    var selectedClipID: String?
    var pinnedRevision: Int?
    var selectedCutID: String?
    var comments: [ReviewComment] = []
    var cuts: [ReviewCut] = []
    var events: [ProjectEvent] = []
    var jobs: [JobRecord] = []
    var words: [TimelineWord] = []
    var transcripts: [SourceTranscript] = []
    var selectedWords: Set<String> = []
    var transcriptDraft = ""
    var position = 0.0
    var playing = false
    var selectionStart = 0.0
    var selectionEnd = 0.0
    var commentScope = "moment"
    var commentFocusRequest = 0
    var commentFocusPending = false
    var notesNavigationRequest = 0
    var commentDraft = ""
    var commentRegion: FrameRegion?
    var annotating = false
    var panel: InspectorTab = .feedback
    var recentProjects: [ProjectEntry] = []
    var selectedCommentID: String?
    var showMedia = false
    var showTools = false
    var showExport = false
    var showActivity = false
    var isPreparing = false
    var pendingUpdate = false
    var activity = "Ready for your direction"
    var error: String?
    var busyCount = 0
    var projectURL: URL?
    var exportPreset = "h264"
    var transcriptionLanguage = "en-US"
    @ObservationIgnored var runtime: ToolRuntime?
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var compiled: CompiledSequence?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var cursor: Int64 = -1
    @ObservationIgnored private var renderKey = ""
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var playbackEndObserver: NSObjectProtocol?
    @ObservationIgnored private var previewSeekPosition: Double?

    var sequence: DirectionCore.Sequence? { try? displayedProject?.sequence(selectedSequenceID) }
    var duration: Double { sequence?.duration.seconds ?? 0 }
    var isWorkingCut: Bool { pinnedRevision == nil && displayedProject?.editRevision == project?.editRevision }
    var canEdit: Bool { isWorkingCut && busyCount == 0 && project != nil }
    var selectedAsset: MediaAsset? { let visible = displayedProject ?? project; return visible?.assets.first { $0.id == selectedAssetID } ?? selectedClip?.assetID.flatMap { id in visible?.assets.first { $0.id == id } } ?? visible?.assets.first }
    var selectedClip: Clip? { sequence?.clips.first { $0.id == selectedClipID } ?? sequence?.clips.first { $0.kind == .video } }
    var cutLabel: String {
        if let id = selectedCutID, let cut = cuts.first(where: { $0.id == id }) { return cut.name }
        guard let revision = pinnedRevision else { return "Working cut" }
        let noteCutID = comments.first(where: { $0.id == selectedCommentID })?.cutID
        let matching = cuts.filter { $0.editRevision == revision && $0.sequenceID == sequence?.id }
        return matching.first(where: { $0.id == noteCutID })?.name ?? matching.last?.name ?? "Earlier cut"
    }
    var activeJobs: [JobRecord] { jobs.filter { !$0.isTerminal } }
    var cliPath: String { let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/direction").path; return FileManager.default.fileExists(atPath: bundled) ? bundled : URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("direction").path }

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1 / 20, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { guard let self, time.seconds.isFinite, !self.isPreparing else { return }; self.position = time.seconds; self.playing = self.player.rate > 0 }
        }
        playbackEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let finishedID = ObjectIdentifier(item)
            MainActor.assumeIsolated {
                guard let self, let current = self.player.currentItem, ObjectIdentifier(current) == finishedID else { return }
                self.player.pause(); self.playing = false
            }
        }
    }

    func start() async {
        recentProjects = (try? ProjectLibrary().list()) ?? []
        if let index = CommandLine.arguments.firstIndex(of: "--project"), CommandLine.arguments.count > index + 1 { open(URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
        else if let path = UserDefaults.standard.string(forKey: "lastProject"), FileManager.default.fileExists(atPath: path) { open(URL(fileURLWithPath: path)) }
        while !Task.isCancelled {
            refresh()
            do { try await Task.sleep(for: .milliseconds(350)) } catch { break }
        }
    }

    func open(_ url: URL) {
        do {
            let store = try ProjectStore(url: url)
            try ProjectLibrary().register(store)
            recentProjects = (try? ProjectLibrary().list()) ?? []
            if let runtime { Task { await runtime.cancelAll() } }
            renderTask?.cancel(); player.pause(); player.replaceCurrentItem(with: nil); compiled = nil
            runtime = try ToolRuntime(store: store); projectURL = url; pinnedRevision = nil; selectedCutID = nil; cursor = -1; renderKey = ""; position = 0; selectedSequenceID = nil; selectedAssetID = nil; selectedClipID = nil; words = []; selectedWords = []; selectedCommentID = nil; commentDraft = ""; commentScope = "moment"; selectionStart = 0; selectionEnd = 0; commentRegion = nil; annotating = false; error = nil
            UserDefaults.standard.set(url.path, forKey: "lastProject")
            refresh(force: true)
        } catch { self.error = error.localizedDescription }
    }

    func chooseProject() {
        let panel = NSOpenPanel(); panel.title = "Open Direction project"; panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func createProject() {
        let panel = NSSavePanel(); panel.title = "Create Direction project"; panel.nameFieldStringValue = "Untitled.direction"; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let target = url.pathExtension == "direction" ? url : url.appendingPathExtension("direction")
            do { _ = try ProjectStore.create(at: target, name: target.deletingPathExtension().lastPathComponent); open(target) } catch { self.error = error.localizedDescription }
        }
    }

    func chooseMedia() {
        guard runtime != nil else { createProject(); return }
        let panel = NSOpenPanel(); panel.title = "Import footage"; panel.allowedContentTypes = [.movie, .audio, .image]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importMedia(panel.urls) }
    }

    func importMedia(_ urls: [URL]) {
        guard let runtime else { return }
        perform {
            for url in urls {
                self.activity = "Importing \(url.lastPathComponent)"
                let append = (try runtime.store.read().sequence(self.selectedSequenceID).clips.isEmpty)
                let response = try await runtime.invoke("direction_import", arguments: .object(["path": .string(url.path), "append": .bool(append)]))
                self.selectedAssetID = response.value["asset"]["id"].string
                self.refresh(force: true)
            }
            self.activity = "Footage imported · ready for your agent"
        }
    }

    func appendAsset(_ asset: MediaAsset) {
        guard let p = project else { return }
        var op = EditOperation("insert"); op.assetID = asset.id
        apply([op], summary: "Added \(asset.name)", base: p.editRevision)
    }

    func refresh(force: Bool = false) {
        guard let runtime else { return }
        do {
            let latestCursor = try runtime.store.eventCursor()
            guard force || latestCursor != cursor else { return }
            let current = try runtime.store.read()
            project = current
            if selectedSequenceID == nil || !current.sequences.contains(where: { $0.id == selectedSequenceID }) { selectedSequenceID = current.sequences.first?.id }
            if pinnedRevision == nil {
                if playing && !force && displayedProject?.editRevision != current.editRevision { pendingUpdate = true }
                else {
                    let changedContext = displayedProject?.id != current.id || displayedProject?.editRevision != current.editRevision
                    displayedProject = current; pendingUpdate = false
                    if changedContext { resetCommentAnchor() }
                }
            }
            var feedback: [String: ReviewComment] = [:], since: Int64 = 0
            while true { let page = try runtime.store.comments(since: since); for c in page { feedback[c.id] = c }; guard page.count == 500, let last = page.last else { break }; since = last.cursor }
            comments = feedback.values.sorted { $0.createdAt < $1.createdAt }
            cuts = try runtime.store.cuts(); jobs = try runtime.store.jobs(); transcripts = try runtime.store.transcripts()
            let newEvents = try runtime.store.events(since: max(0, cursor)); events.append(contentsOf: newEvents); events = Array(events.suffix(100))
            if let last = newEvents.last(where: { $0.kind == "edit.committed" }) { activity = last.summary }
            cursor = latestCursor
            updateTranscript(); preparePreview()
        } catch { self.error = error.localizedDescription }
    }

    func updateTranscript() {
        guard let sequence else { words = []; transcriptDraft = ""; return }
        let projected = TranscriptEditing.words(in: sequence, transcripts: transcripts)
        if projected != words { words = projected; transcriptDraft = projected.map(\.text).joined(separator: " "); selectedWords.formIntersection(Set(projected.map(\.id))) }
    }

    func preparePreview(force: Bool = false) {
        guard let p = displayedProject, let sequence, let runtime else { return }
        let key = "\(p.editRevision):\(sequence.id)"
        guard force || key != renderKey else { return }
        renderKey = key; renderTask?.cancel(); isPreparing = true; previewSeekPosition = position
        if sequence.clips.isEmpty { player.pause(); player.replaceCurrentItem(with: nil); compiled = nil; isPreparing = false; return }
        renderTask = Task {
            do {
                let result = try await SequenceRenderer.compile(project: p, sequenceID: sequence.id, cacheDirectory: runtime.cacheDirectory, previewMaxDimension: 1920)
                try Task.checkCancellation()
                guard renderKey == key else { return }
                let target = previewSeekPosition ?? position
                player.pause(); playing = false; compiled = result; player.replaceCurrentItem(with: result.playerItem()); isPreparing = false; previewSeekPosition = nil; seek(min(target, max(0, duration - 1 / sequence.frameRate.value)))
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; isPreparing = false } }
        }
    }

    func followWorkingCut() { player.pause(); playing = false; pinnedRevision = nil; selectedCutID = nil; refresh(force: true) }
    func review(_ cut: ReviewCut) { showRevision(cut.editRevision, sequenceID: cut.sequenceID); selectedCutID = cut.id }
    func showRevision(_ revision: Int, sequenceID: String? = nil) {
        guard let runtime else { return }
        do { player.pause(); playing = false; displayedProject = try runtime.store.read(revision: revision); pinnedRevision = revision; selectedCutID = nil; if let sequenceID { selectedSequenceID = sequenceID }; resetCommentAnchor(); renderKey = ""; updateTranscript(); preparePreview() } catch { self.error = error.localizedDescription }
    }
    func selectSequence(_ id: String) { selectedSequenceID = id; selectedClipID = nil; selectedCutID = nil; position = 0; resetCommentAnchor(); updateTranscript(); preparePreview(force: true) }
    func seek(_ seconds: Double) { guard seconds.isFinite else { return }; position = max(0, min(seconds, duration)); if isPreparing { previewSeekPosition = position; return }; player.seek(to: CMTime(seconds: position, preferredTimescale: 600_000), toleranceBefore: .zero, toleranceAfter: .zero) }
    func togglePlayback() { if player.rate > 0 { player.pause(); playing = false } else { if position >= duration - 0.03 { seek(0) }; player.play(); playing = true } }
    func frameStep(_ direction: Double) { player.pause(); playing = false; seek(position + direction / (sequence?.frameRate.value ?? 30)) }
    func markIn() { showNotes(); selectionStart = min(position, max(0, duration - 0.01)); selectionEnd = max(selectionEnd, min(duration, selectionStart + 1)); commentScope = "range" }
    func markOut() { showNotes(); selectionEnd = max(0.01, min(position, duration)); selectionStart = min(selectionStart, max(0, selectionEnd - 0.01)); commentScope = "range" }

    /// Navigation is an event even when the requested note and anchor are unchanged.
    func showNotes() { panel = .feedback; notesNavigationRequest += 1 }

    func toggleRegionAnnotation() {
        guard duration > 0 else { return }
        if annotating { annotating = false; return }
        if commentScope == "cut" { setWholeVideoComment(false) }
        selectedCommentID = nil; commentRegion = nil; annotating = true
        player.pause(); playing = false
        showNotes()
    }

    /// Seeking chooses the temporal anchor; the composer never needs raw time fields.
    func beginMomentComment(at seconds: Double) {
        guard duration > 0, seconds.isFinite else { return }
        player.pause(); playing = false
        seek(seconds)
        commentScope = "moment"
        selectionStart = position; selectionEnd = position
        selectedCommentID = nil; commentRegion = nil; annotating = false
        panel = .feedback
        requestCommentFocus()
    }

    func selectCommentRange(from start: Double, to end: Double, focus: Bool = true) {
        guard duration > 0, start.isFinite, end.isFinite else { return }
        let lower = max(0, min(duration, min(start, end)))
        let upper = max(0, min(duration, max(start, end)))
        guard upper - lower >= min(0.01, duration) else {
            if focus { beginMomentComment(at: lower) }
            return
        }
        player.pause(); playing = false
        selectionStart = lower; selectionEnd = upper; commentScope = "range"
        selectedCommentID = nil; commentRegion = nil; annotating = false
        panel = .feedback
        seek(lower)
        if focus { requestCommentFocus() }
    }

    func setWholeVideoComment(_ enabled: Bool) {
        if enabled { commentScope = "cut" }
        else { commentScope = selectionEnd > selectionStart && selectionStart >= 0 && selectionEnd <= duration ? "range" : "moment" }
    }

    func requestCommentFocus() {
        commentFocusPending = true
        commentFocusRequest += 1
    }

    private func resetCommentAnchor() {
        position = max(0, min(duration, position))
        commentScope = "moment"
        selectionStart = position; selectionEnd = position
        selectedCommentID = nil; commentRegion = nil; annotating = false
        commentFocusPending = false
    }

    func addComment() {
        guard let runtime, let displayedProject, let sequence else { return }
        do {
            let range = commentScope == "range" ? MediaRange(start: selectionStart, end: selectionEnd) : nil
            let time: MediaTime? = commentScope == "moment" ? .init(seconds: min(position, max(0, duration - 1 / sequence.frameRate.value))) : nil
            let comment = try runtime.store.addComment(text: commentDraft, sequenceID: sequence.id, revision: displayedProject.editRevision, cutID: selectedCutID, range: range, time: time, region: commentScope == "cut" ? nil : commentRegion)
            commentDraft = ""; annotating = false; commentRegion = nil; refresh(force: true); selectedCommentID = comment.id
        } catch { self.error = error.localizedDescription }
    }

    func seekComment(_ comment: ReviewComment) {
        if displayedProject?.editRevision != comment.editRevision || selectedSequenceID != comment.sequenceID { showRevision(comment.editRevision, sequenceID: comment.sequenceID) }
        selectedCommentID = comment.id
        player.pause(); playing = false; showNotes(); commentRegion = comment.region
        commentScope = comment.scope
        if let range = comment.range { selectionStart = range.start.seconds; selectionEnd = range.end.seconds }
        seek(comment.range?.start.seconds ?? comment.time?.seconds ?? 0)
        if comment.range == nil { selectionStart = position; selectionEnd = position }
    }
    func accept(_ comment: ReviewComment) { guard let runtime else { return }; do { _ = try runtime.store.reply(commentID: comment.id, text: "Accepted by director", author: "Director", status: "accepted", asDirector: true); refresh(force: true) } catch { self.error = error.localizedDescription } }
    func reopen(_ comment: ReviewComment) { guard let runtime else { return }; do { _ = try runtime.store.reply(commentID: comment.id, text: "Reopened by director", author: "Director", status: "open", asDirector: true); refresh(force: true) } catch { self.error = error.localizedDescription } }
    func saveCut() { guard let runtime, let p = displayedProject else { return }; do { let cut = try runtime.store.createCut(name: "Cut " + String(format: "%02d", cuts.count + 1), sequenceID: selectedSequenceID, revision: p.editRevision); refresh(); review(cut) } catch { self.error = error.localizedDescription } }
    func restoreDisplayed() { guard let runtime, let revision = pinnedRevision, let current = project?.editRevision else { return }; do { _ = try runtime.store.restore(revision: revision, expectedRevision: current, key: UUID().uuidString); followWorkingCut() } catch { self.error = error.localizedDescription } }

    func transcribe(_ asset: MediaAsset, trackID: Int32? = nil) {
        guard let runtime else { return }
        perform {
            var args: [String: JSONValue] = ["assetID": .string(asset.id), "language": .string(self.transcriptionLanguage)]
            if let trackID { args["trackID"] = .number(Double(trackID)) }
            let result = try await runtime.invoke("direction_transcribe", arguments: .object(args))
            let job = try result.value.decode(JobRecord.self)
            self.refresh(); _ = try await runtime.waitForJob(job.id); self.refresh(force: true); self.activity = "Local transcript ready"
        }
    }

    func applyTranscriptDraft() { guard let runtime, let p = project else { return }; let draft = transcriptDraft; perform { _ = try await runtime.invoke("direction_edit_transcript", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "sequenceID": .string(self.selectedSequenceID ?? p.sequences[0].id), "editedText": .string(draft)])); self.refresh(force: true) } }
    func deleteSelectedWords() {
        guard let runtime, let p = project else { return }; let ids = selectedWords
        perform { _ = try await runtime.invoke("direction_edit_transcript", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "sequenceID": .string(self.selectedSequenceID ?? p.sequences[0].id), "deleteWordIDs": .array(ids.sorted().map(JSONValue.string))])); self.selectedWords = []; self.refresh(force: true) }
    }
    func updateAudio(asset: MediaAsset, track: AudioStream, muted: Bool? = nil, gain: Double? = nil, extra: [String: JSONValue] = [:]) {
        guard let runtime, let p = project else { return }
        var a: [String: JSONValue] = ["assetID": .string(asset.id), "trackID": .number(Double(track.id)), "baseEditRevision": .number(Double(p.editRevision))]
        if let muted { a["muted"] = .bool(muted) }; if let gain { a["gainDB"] = .number(gain) }; a.merge(extra) { _, new in new }
        perform { _ = try await runtime.invoke("direction_audio", arguments: .object(a)); self.refresh(force: true) }
    }
    func apply(_ ops: [EditOperation], summary: String, base: Int? = nil) {
        guard let runtime, let p = project else { return }
        do { _ = try runtime.store.apply(.init(baseEditRevision: base ?? p.editRevision, sequenceID: selectedSequenceID, summary: summary, operations: ops)); refresh(force: true) } catch { self.error = error.localizedDescription }
    }
    func updateGrade(_ grade: ColorGrade) { guard let clip = selectedClip else { return }; var op = EditOperation("color"); op.clipID = clip.id; op.grade = grade; apply([op], summary: "Adjusted color on \(clip.name)") }
    func setFormat(width: Int, height: Int) { var op = EditOperation("format"); op.width = width; op.height = height; apply([op], summary: "Changed canvas to \(width) × \(height)") }

    func chooseExport() {
        guard let runtime, let displayedProject, let sequence else { return }
        let panel = NSSavePanel(); panel.title = "Export \(cutLabel)"; panel.nameFieldStringValue = (project?.name ?? "Direction") + (exportPreset == "prores" ? ".mov" : ".mp4"); panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A new destination is required even if a save dialog offers replacement.
        if FileManager.default.fileExists(atPath: url.path) { error = "Choose a new filename. Direction preserves existing footage and exports."; return }
        showExport = false
        perform {
            let response = try await runtime.invoke("direction_export", arguments: .object(["path": .string(url.path), "preset": .string(self.exportPreset), "revision": .number(Double(displayedProject.editRevision)), "sequenceID": .string(sequence.id)]))
            let job = try response.value.decode(JobRecord.self); self.refresh(); _ = try await runtime.waitForJob(job.id); self.refresh(force: true); self.activity = "Export complete · \(url.lastPathComponent)"; NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    func cancelJob(_ job: JobRecord) { guard let runtime else { return }; perform { _ = try await runtime.invoke("direction_cancel_job", arguments: .object(["jobID": .string(job.id)])); self.refresh(force: true) } }
    func perform(_ operation: @escaping @MainActor () async throws -> Void) { busyCount += 1; Task { defer { busyCount -= 1 }; do { try await operation() } catch { self.error = error.localizedDescription; refresh(force: true) } } }
    func copyMCPConfig() {
        let config: JSONValue = .object(["mcpServers": .object(["direction": .object(["command": .string(cliPath), "args": .array([.string("mcp"), .string("--project"), .string(projectURL?.path ?? "/path/to/Project.direction")])])])])
        if let data = try? config.data(pretty: true) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string) }
    }
}
