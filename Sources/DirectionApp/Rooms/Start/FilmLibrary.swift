import Foundation
import SwiftUI
import AppKit
import DirectionCore

/// What the Films list knows about one film, read from its store off the main thread.
struct FilmIndexCard: Sendable {
    var summary: FilmSummary
    /// Drafts, answers to review, questions or a read-back waiting on the director.
    var needsYou: Bool
    var progress: Double?
    var footage: [String]
    var brief: Brief
    /// When the film's database last changed; the store is only opened again after it does.
    var stamp: Double
}

/// Reads each film's store (read-only use) for its Films card, and keeps the result until the film changes.
@MainActor @Observable final class FilmLibraryIndex {
    static let shared = FilmLibraryIndex()
    private(set) var cards: [String: FilmIndexCard] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    func card(_ path: String) -> FilmIndexCard? { cards[path] }

    /// Re-reads films whose store changed since the last look.
    func refresh(_ entries: [ProjectEntry]) {
        for (i, e) in entries.enumerated() where e.available && !loading.contains(e.path) {
            loading.insert(e.path)
            let known = cards[e.path]?.stamp
            Task.detached(priority: .utility) { [weak self] in
                let card = try? Self.load(e, index: i, known: known)
                await MainActor.run {
                    self?.loading.remove(e.path)
                    if let card { self?.cards[e.path] = card }
                }
            }
        }
    }

    /// The card as the list shows it; a plain one until the store has been read.
    func summary(for e: ProjectEntry) -> FilmSummary {
        if let card = cards[e.path] {
            // Stage first, then the last-opened time; an editor activity line stands alone.
            var s = card.summary
            if !s.editorBusy { s.status += " \u{00B7} " + FilmDates.short(e.lastOpened) }
            return s
        }
        return FilmSummary(id: e.path, name: e.name, path: e.path, duration: nil, status: e.available ? FilmDates.short(e.lastOpened) : "Can't find this film", art: [.dusk, .night, .day, .hands, .room][abs(e.path.hashValue) % 5])
    }

    nonisolated static func load(_ e: ProjectEntry, index: Int, known: Double?) throws -> FilmIndexCard? {
        let stamp = modified(e.path)
        if stamp == known { return nil }
        let store = try ProjectStore(url: URL(fileURLWithPath: e.path))
        let p = try store.read()
        let cuts = try store.cuts().sorted { $0.createdAt < $1.createdAt }
        let notes = try store.notes(), turnovers = try store.turnovers(), questions = try store.questions()
        let state = try store.directingState(), dailies = try store.dailies(), brief = try store.brief()
        let latest = cuts.last, open = turnovers.last { $0.state.isOpen }
        let drafts = notes.filter { $0.lifecycle == .draft }.count
        let unreviewed = latest.map { cut in notes.filter { $0.lifecycle == .answered && $0.answers?.last?.cutID == cut.id && $0.answers?.last?.state == "unreviewed" }.count } ?? 0
        let asks = questions.filter { $0.answer == nil }.count
        let readBack = open?.state == .readBack && open?.readBackApproved == false

        var status: String, busy = false, progress: Double?
        if let t = open, t.state == .cutting || t.state == .waiting || (t.state == .readBack && t.readBackApproved) {
            busy = true
            if t.kind == "assembly" { status = "Editor is building the assembly"; progress = t.percent }
            else {
                let done = t.progress.values.filter { $0 == .done }.count
                status = "Editor is cutting Cut \(cuts.count + 1) \u{00B7} \(done) of \(t.noteIDs.count) notes"
                progress = t.percent ?? Double(done) / Double(max(1, t.noteIDs.count))
            }
        } else if state.pictureLocked {
            let items = state.finishing ?? FinishingItem.defaults
            status = "\(latest?.name ?? "Picture") \u{00B7} Finishing \u{00B7} \(items.filter { $0.state == "done" }.count) of \(items.count) done"
        } else if let latest {
            let stage = asks > 0 ? (asks == 1 ? "The editor has a question" : "The editor has \(asks) questions")
                : unreviewed > 0 ? "\(unreviewed) \(unreviewed == 1 ? "answer" : "answers") to review"
                : readBack ? "Read-back waiting for you" : "You're giving notes"
            status = "\(latest.name) \u{00B7} \(stage)"
        } else if !brief.isComplete { status = "New film \u{00B7} Write the brief" }
        else if p.assets.isEmpty { status = "Brief \u{00B7} No footage yet" }
        else { status = "Dailies \u{00B7} \(dailies.takes.values.filter(\.circled).count) circled \u{00B7} No cuts yet" }

        let cutSequence = latest.flatMap { cut in (try? store.read(revision: cut.editRevision)).flatMap { try? $0.sequence(cut.sequenceID) } }
        let duration = cutSequence.map { Timecode.duration($0.duration.seconds) } ?? (p.assets.isEmpty ? nil : "\(p.assets.count) takes")
        let posterAsset = cutSequence?.clips.first { $0.kind == .video }?.assetID
        let thumbnail = (p.assets.first { $0.id == posterAsset } ?? p.assets.first { $0.thumbnailPath != nil })?.thumbnailPath
        let summary = FilmSummary(id: e.path, name: p.name, path: e.path, duration: duration, status: status, editorBusy: busy,
                                  waiting: drafts > 0 ? "\(drafts) \(drafts == 1 ? "note" : "notes") waiting" : nil, locked: state.pictureLocked,
                                  art: [.dusk, .night, .day, .hands, .room][index % 5], thumbnail: thumbnail)
        return FilmIndexCard(summary: summary, needsYou: drafts > 0 || unreviewed > 0 || asks > 0 || readBack, progress: progress, footage: Array(p.assets.prefix(50).map(\.path)), brief: brief, stamp: modified(e.path))
    }

    /// The latest change to the film's database or its write-ahead log.
    nonisolated static func modified(_ path: String) -> Double {
        ["project.sqlite", "project.sqlite-wal"].compactMap { name in
            (try? FileManager.default.attributesOfItem(atPath: path + "/" + name)[.modificationDate] as? Date)?.timeIntervalSince1970
        }.max() ?? 0
    }

    /// Renames a film from the list, without opening it.
    func rename(_ path: String, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let store = try ProjectStore(url: URL(fileURLWithPath: path))
        let p = try store.read()
        guard p.name != name else { return }
        _ = try store.update(expectedRevision: p.editRevision, key: UUID().uuidString, request: Data("rename:\(name)".utf8), summary: "Named the film \(name)") { $0.name = name }
        try ProjectLibrary().register(store)
    }

    // MARK: Trash

    private static let trashedKey = "trashedFilms"
    static var trashed: Set<String> { Set(UserDefaults.standard.stringArray(forKey: trashedKey) ?? []) }
    static func noteTrashed(_ path: String) { UserDefaults.standard.set(Array(trashed.union([path])), forKey: trashedKey) }
    /// A film is at this path again (a new film took a trashed one's name): show it.
    static func noteRestored(_ path: String) {
        guard trashed.contains(path) else { return }
        UserDefaults.standard.set(Array(trashed.subtracting([path])), forKey: trashedKey)
    }
}

extension AppModel {
    /// The Films grid: sample films in previews, otherwise the library's films read from their stores.
    var summaries: [FilmSummary] {
        if let previewFilms { return previewFilms }
        // Trashing moves the package away, so a film still at a trashed path is a new one that took its
        // name ("Untitled film" after an empty one was discarded). Hide only what's really gone.
        let trashed = FilmLibraryIndex.trashed
        return films.filter { !(trashed.contains($0.path) && !$0.available) }.map { FilmLibraryIndex.shared.summary(for: $0) }
    }
    /// Films that are on this Mac to open, for the film menu: never one that was trashed or is missing.
    var openableFilms: [ProjectEntry] { previewFilms != nil ? [] : films.filter(\.available) }
    /// A film's name for a menu: its title from the library, else its package's name.
    func filmName(_ url: URL) -> String { films.first { $0.path == url.path }?.name ?? url.deletingPathExtension().lastPathComponent }
    /// Films with something waiting on the director.
    var waitingCount: Int {
        if let previewFilms { return previewFilms.filter { $0.waiting != nil }.count }
        return summaries.filter { FilmLibraryIndex.shared.card($0.path)?.needsYou == true }.count
    }
    func lastOpened(_ path: String) -> Double { films.first { $0.path == path }?.lastOpened ?? 0 }
}

enum FilmDates {
    /// "Today 14:20", "Yesterday", "Oct 12".
    static func short(_ time: Double) -> String {
        guard time > 0 else { return "" }
        let date = Date(timeIntervalSince1970: time), cal = Calendar.current
        if cal.isDateInToday(date) { return "Today " + date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
