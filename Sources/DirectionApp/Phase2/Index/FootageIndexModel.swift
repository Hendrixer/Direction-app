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
    @ObservationIgnored private var lastGrow = Date.distantPast
    @ObservationIgnored private weak var film: FilmModel?

    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {
        self.film = film
        guard let store = film.store, let project = film.project else { return }
        do {
            takes = try store.indexTakes()
            job = film.jobs.first { $0.kind == "index" && !$0.isTerminal }
            let assets = project.assets.filter { !$0.isImage }
            var s: [String: IndexState] = [:]
            for a in assets {
                guard let t = takes[a.id], t.fingerprint == TakeIndex.fingerprint(a) else { s[a.id] = job != nil ? .looking : .waiting; continue }
                s[a.id] = t.state == .looking && job == nil ? .waiting : t.state
            }
            states = s
            let done = s.values.filter { $0 == .done || $0 == .failed }.count
            looking = job != nil && !assets.isEmpty ? IndexProgress(done: done, total: assets.count) : nil
            shotCache = shotCache.filter { takes[$0.key]?.updatedAt == $0.value.stamp }
            autoStart(film, assets: assets)
            // "Results will grow": search again as takes are looked at, every few seconds at most.
            if searching, !searchedQuery.isEmpty, job != nil, Date().timeIntervalSince(lastGrow) > 3 { lastGrow = Date(); search(film, now: true) }
        } catch { film.error = error.localizedDescription }
    }

    /// Footage arrived and Settings says to look at it automatically. At most every few seconds,
    /// so a take that keeps failing doesn't restart the job in a loop.
    private func autoStart(_ film: FilmModel, assets: [MediaAsset]) {
        guard !film.isPreview, job == nil, SharedSettings.lookAutomatically, Date().timeIntervalSince(lastAutoStart) > 5 else { return }
        guard assets.contains(where: { states[$0.id] == .waiting }) else { return }
        lastAutoStart = Date()
        lookAtFootage(film)
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
