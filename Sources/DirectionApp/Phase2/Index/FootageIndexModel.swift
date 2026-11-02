import SwiftUI
import DirectionCore
import DirectionMedia

/// Shots, sounds and search for Dailies (specs/footage-index.md).
@MainActor @Observable final class FootageIndexModel {
    /// Takes looked at so far, while the index is working; nil when idle. The pill reads it.
    var looking: IndexProgress?
    /// Each take's index as the store has it, and its state with dead jobs accounted for.
    var takes: [String: TakeIndex] = [:]
    var states: [String: IndexState] = [:]
    /// The live index job, here or in the MCP server.
    var job: JobRecord?
    /// Takes with sound that still need their words, while Direction transcribes them: "Listening · 1 of 2".
    var listening: IndexProgress?

    // MARK: Search (frame 60)

    /// The field shows from ⌘F until esc clears it.
    var searching = false
    var query = ""
    var circledOnly = false
    /// "Search words only": transcripts alone.
    var wordsOnly = false
    var results: [FootageSearch.Hit] = []
    /// The query the results are for, so the header doesn't change while typing.
    var searchedQuery = ""
    var searchFocus = 0
    /// Opening a take from a result starts it at the shot.
    var openAt: (assetID: String, time: Double)?

    /// Previews set these instead of reading a store.
    var previewShots: [String: [Shot]] = [:]
    var previewSounds: [String: [IndexSound]] = [:]
    var previewStillLooking: Int?

    @ObservationIgnored private var shotCache: [String: (stamp: Double, shots: [Shot], sounds: [IndexSound])] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastAutoStart = Date.distantPast
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var lastGrow = Date.distantPast
    @ObservationIgnored private weak var film: FilmModel?
    @ObservationIgnored private var startingTranscription = false
    @ObservationIgnored private var transcribeAttempts: [String: Int] = [:]
    @ObservationIgnored private var startingSync = false
    /// Opening a film counts as work having finished, so its old decoded audio goes too.
    @ObservationIgnored private var workedSinceAudioDrop = true
    /// Tries per set of takes still to compare, so new footage is always compared.
    @ObservationIgnored private var syncAttempts: [String: Int] = [:]
    /// Takes with sound whose sound hasn't been compared with the others yet.
    var unsynced = 0

    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {
        self.film = film
        guard let store = film.store, film.project != nil else { return }
        do {
            let fresh = try store.indexTakes()
            if fresh != takes { takes = fresh }
            let running = film.jobs.first { $0.kind == "index" && !$0.isTerminal }
            if running != job { job = running }
            let assets = film.footage.filter { !$0.isImage }
            var s: [String: IndexState] = [:]
            for a in assets {
                guard let t = takes[a.id], t.fingerprint == TakeIndex.fingerprint(a) else { s[a.id] = job != nil ? .looking : .waiting; continue }
                s[a.id] = t.state == .looking && job == nil ? .waiting : t.state
            }
            if s != states { states = s }
            let done = s.values.filter { $0 == .done || $0 == .failed }.count
            let progress = job != nil && !assets.isEmpty ? IndexProgress(done: done, total: assets.count) : nil
            if progress != looking { looking = progress }
            shotCache = shotCache.filter { takes[$0.key]?.updatedAt == $0.value.stamp }
            autoStart(film, assets: assets)
            listen(film, assets: assets)
            sync(film, assets: assets)
            dropAudioWhenIdle(film)
            // "Results will grow": search again as takes are looked at, every few seconds at most.
            if searching, !searchedQuery.isEmpty, job != nil, Date().timeIntervalSince(lastGrow) > 3 { lastGrow = Date(); search(film, now: true) }
        } catch { film.error = error.localizedDescription }
    }

    /// Footage arrived and Settings says to look at it automatically. At most every few seconds,
    /// so a take that keeps failing doesn't restart the job in a loop. Takes looked at before
    /// Direction read text on screen are read once too.
    private func autoStart(_ film: FilmModel, assets: [MediaAsset]) {
        guard !film.isPreview, job == nil, SharedSettings.lookAutomatically else { return }
        let unread = { (a: MediaAsset) in !a.video.isEmpty && self.states[a.id] == .done && self.takes[a.id].map(FootageIndexer.needsScreenText) == true }
        guard assets.contains(where: { states[$0.id] == .waiting || unread($0) }) else { return }
        // Too soon after the last start: look again once it's allowed, since nothing else may change in between.
        let wait = 5 - Date().timeIntervalSince(lastAutoStart)
        guard wait <= 0 else {
            guard retryTask == nil else { return }
            retryTask = Task { [weak self, weak film] in
                try? await Task.sleep(for: .seconds(wait + 0.1))
                self?.retryTask = nil
                if let film { self?.refresh(film) }
            }
            return
        }
        lastAutoStart = Date()
        lookAtFootage(film)
    }

    /// Takes with sound whose words aren't settled yet.
    @ObservationIgnored private(set) var unsettledWords: Set<String> = []

    /// Ready for the editor to log: Direction has looked at it (when it looks by itself), its words
    /// are in or settled, and its sound has been compared with the others (footage-index.md ›
    /// Logging in batches).
    func readyToLog(_ asset: MediaAsset) -> Bool {
        let looked = asset.isImage || !SharedSettings.lookAutomatically || [.done, .failed].contains(state(asset.id))
        return looked && !unsettledWords.contains(asset.id) && unsynced == 0
    }

    /// Direction is still looking at or listening to footage that arrived, so logging waits. A take
    /// that just arrived counts as waiting before its index job exists.
    var busy: Bool { looking != nil || listening != nil || unsynced > 0 || (SharedSettings.lookAutomatically && states.values.contains(.waiting)) }

    /// Once nothing is transcribing, listening or cutting, the decoded audio goes: it's most of the
    /// cache, and anything that needs it again decodes it again in seconds. On opening the film, and
    /// again each time work finishes.
    private func dropAudioWhenIdle(_ film: FilmModel) {
        guard !film.isPreview, let id = film.project?.id else { return }
        let idle = !busy && !film.isLogging && film.runs.active == nil && !film.jobs.contains { !$0.isTerminal }
        guard idle else { workedSinceAudioDrop = true; return }
        guard workedSinceAudioDrop else { return }
        workedSinceAudioDrop = false
        Task.detached(priority: .background) {
            let bytes = CacheCleanup.dropDecodedAudio(projectID: id)
            if bytes > 0 { DirectionLog.info("Dropped \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) of decoded audio from the cache of \(id)", "cache") }
        }
    }

    /// Takes that recorded the same moment are found by their sound before logging, so the editor
    /// logs them as angles of one moment (footage-index.md › Sync). Seconds of work on this Mac;
    /// tried twice at most for the same takes in a session.
    private func sync(_ film: FilmModel, assets: [MediaAsset]) {
        let checked = Set(film.dailies.syncChecked ?? [])
        let speaking = assets.filter { !$0.audio.isEmpty && $0.duration.seconds >= 10 }
        let running = film.jobs.contains { $0.kind == "sync" && !$0.isTerminal }
        // Something compared before that isn't footage now counts too: the takes are compared again without it.
        let stray = checked.isSubset(of: speaking.map(\.id)) ? 0 : 1
        let waiting = speaking.filter { !checked.contains($0.id) }.map(\.id).sorted()
        let attempt = waiting.joined(separator: ",") + (stray > 0 ? "+" : "")
        unsynced = film.isPreview || syncAttempts[attempt, default: 0] >= 2 ? 0 : waiting.count + stray
        guard unsynced > 0, !running, !startingSync, let runtime = film.runtime else { return }
        startingSync = true; syncAttempts[attempt, default: 0] += 1
        Task {
            do { _ = try await runtime.invoke("direction_sync_takes") }
            catch { DirectionLog.error("Couldn\u{2019}t compare the takes\u{2019} sound: \(error.localizedDescription)", "sync") }
            startingSync = false
            film.refresh(force: true)
        }
    }

    /// Every take with sound gets its words before the editor logs it (footage-index.md › Listening).
    /// The app transcribes them itself, one at a time, so the job outlives an editor run. A job that
    /// was cancelled or whose process exited, or a transcript stuck in a loop, is started again, twice
    /// at most; one that failed (no speech, say) is left for Transcribe Again.
    private func listen(_ film: FilmModel, assets: [MediaAsset]) {
        let speaking = assets.filter { !$0.audio.isEmpty }
        let heard = Set(film.transcripts.filter { !$0.words.isEmpty && !$0.looksLooped }.map(\.assetID))
        let jobs = film.jobs.filter { $0.kind == "transcription" }
        func settled(_ a: MediaAsset) -> Bool {
            if heard.contains(a.id) || transcribeAttempts[a.id, default: 0] >= 2 { return true }
            guard let last = jobs.first(where: { $0.assetID == a.id }) else { return false }
            return last.status == "failed"
        }
        let waiting = speaking.filter { !settled($0) }
        unsettledWords = film.isPreview ? [] : Set(waiting.map(\.id))
        listening = waiting.isEmpty || film.isPreview ? nil : IndexProgress(done: speaking.count - waiting.count, total: speaking.count)
        guard !film.isPreview, !startingTranscription, !jobs.contains(where: { !$0.isTerminal }), let next = waiting.first, let runtime = film.runtime else { return }
        startingTranscription = true
        transcribeAttempts[next.id, default: 0] += 1
        Task {
            do { _ = try await runtime.invoke("direction_transcribe", arguments: .object(["assetID": .string(next.id)])) }
            catch { transcribeAttempts[next.id] = 2; DirectionLog.error("Couldn\u{2019}t transcribe \(next.name): \(error.localizedDescription)") }
            startingTranscription = false
            film.refresh(force: true)
        }
    }

    /// Transcribe Again on a take: its words are made fresh with the engine in Settings.
    func transcribeAgain(_ assetID: String, film: FilmModel) {
        guard let runtime = film.runtime else { return }
        transcribeAttempts[assetID] = 0
        Task {
            do { _ = try await runtime.invoke("direction_transcribe", arguments: .object(["assetID": .string(assetID)])) }
            catch { film.error = error.localizedDescription }
            film.refresh(force: true)
        }
    }

    /// Film › Look at Footage, or footage arriving.
    func lookAtFootage(_ film: FilmModel, assetIDs: [String]? = nil) {
        guard let runtime = film.runtime else { return }
        Task { do { try await runtime.lookAtFootage(assetIDs: assetIDs) } catch { film.error = error.localizedDescription }; film.refresh(force: true) }
    }

    /// "Try again" on a take whose index failed. A running job picks it up as waiting.
    func retry(_ assetID: String, film: FilmModel) {
        guard let store = film.store else { return }
        if var t = takes[assetID] { t.state = .waiting; t.error = nil; try? store.saveTakeIndex(t, summary: "Looking at a take again") }
        lookAtFootage(film, assetIDs: job == nil ? [assetID] : nil)
    }

    // MARK: A take's index

    func state(_ assetID: String) -> IndexState { states[assetID] ?? (previewShots[assetID] != nil ? .done : .waiting) }
    func shots(_ assetID: String) -> [Shot] { load(assetID).shots }
    func sounds(_ assetID: String) -> [IndexSound] { load(assetID).sounds }
    func shot(at time: Double, in assetID: String) -> Shot? { shots(assetID).last { $0.start <= time + 0.001 } }

    private func load(_ assetID: String) -> (shots: [Shot], sounds: [IndexSound]) {
        if let s = previewShots[assetID] { return (s, previewSounds[assetID] ?? []) }
        guard let store = film?.store, let t = takes[assetID] else { return ([], []) }
        if let hit = shotCache[assetID], hit.stamp == t.updatedAt { return (hit.shots, hit.sounds) }
        let shots = (try? store.shots(assetID: assetID)) ?? [], sounds = (try? store.sounds(assetID: assetID)) ?? []
        shotCache[assetID] = (t.updatedAt, shots, sounds)
        return (shots, sounds)
    }

    /// Takes still being looked at, for "Still looking at 126 takes."
    var stillLooking: Int { previewStillLooking ?? states.values.filter { $0 == .waiting || $0 == .looking }.count }

    // MARK: Search

    /// Typing searches after 250 ms; toggles search at once.
    func search(_ film: FilmModel, now: Bool = false) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; searchedQuery = ""; return }
        guard let store = film.store else { searchedQuery = q; return }
        let options = FootageSearch.Options(circledOnly: circledOnly, wordsOnly: wordsOnly, limit: 60)
        let dailies = film.dailies
        searchTask = Task {
            if !now { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            let hits = await Task.detached(priority: .userInitiated) {
                try? FootageIndexer.refreshWords(store: store)
                return (try? FootageSearch.search(q, store: store, dailies: dailies, options: options)) ?? []
            }.value
            guard !Task.isCancelled else { return }
            // The grid shows one card per take: its best shot.
            var seen = Set<String>()
            results = hits.filter { seen.insert($0.assetID).inserted }
            searchedQuery = q
        }
    }

    func clearSearch() { searchTask?.cancel(); query = ""; results = []; searchedQuery = ""; searching = false; wordsOnly = false }

    /// Results grouped by scene in scene order; takes outside a scene last.
    func groups(_ film: FilmModel) -> [(scene: DailiesScene?, hits: [FootageSearch.Hit])] {
        let byScene = Dictionary(grouping: results) { film.dailies.take($0.assetID).sceneID ?? "" }
        var out: [(DailiesScene?, [FootageSearch.Hit])] = film.scenes.compactMap { s in byScene[s.id].map { (s, $0) } }
        if let rest = byScene.filter({ k, _ in film.scene(k) == nil }).values.flatMap({ $0 }) as [FootageSearch.Hit]?, !rest.isEmpty { out.append((nil, rest)) }
        return out
    }
}

struct IndexProgress: Equatable { var done: Int; var total: Int }

/// Where a take's words are, for its transcript in Dailies.
enum TakeTranscriptStatus: Equatable { case words, transcribing, waiting, failed(String), none }

extension FilmModel {
    func transcriptStatus(_ assetID: String) -> TakeTranscriptStatus {
        if transcripts.contains(where: { $0.assetID == assetID && !$0.words.isEmpty && !$0.looksLooped }) { return .words }
        let jobs = self.jobs.filter { $0.kind == "transcription" }
        if let last = jobs.first(where: { $0.assetID == assetID }) {
            if !last.isTerminal { return .transcribing }
            // Nothing said in it (b-roll): no dialogue, not a failure. Jobs from before codes say so in words.
            if last.status == "failed", last.errorCode == "no_speech" || (last.errorCode == nil && last.error?.hasPrefix("No timed speech") == true) { return .none }
            if last.status == "failed" { return .failed(last.error ?? "Transcription stopped.") }
        }
        guard asset(assetID)?.audio.isEmpty == false else { return .none }
        return index.listening != nil ? .waiting : .none
    }
}
