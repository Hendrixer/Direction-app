import SwiftUI
import AVFoundation
import DirectionCore

/// Made media, services and spend (specs/made-media.md): the film's made clips and where they came from.
@MainActor @Observable final class MadeModel {
    /// Every made clip in the film, oldest first. Previews set it directly.
    var records: [MadeRecord] = []
    /// The chip whose provenance popover is open (Changes), by asset.
    var provenanceID: String?
    /// The row open in Dailies › Made, set by Show in Dailies.
    var dailiesID: String?
    /// The clip Play it alone is playing.
    private(set) var playingID: String?
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {
        guard let store = film.store, let fresh = try? store.madeRecords(), fresh != records else { return }
        records = fresh
    }

    func record(_ assetID: String?) -> MadeRecord? { assetID.flatMap { id in records.first { $0.assetID == id } } }

    /// What an answer made: clips for its note, from the turnover that delivered its cut.
    func records(for note: ReviewComment, in cut: ReviewCut?, film: FilmModel) -> [MadeRecord] {
        let mine = records.filter { $0.noteID == note.id }
        guard let cut, let turnover = film.turnovers.first(where: { $0.resultCutID == cut.id }) else { return mine }
        return mine.filter { $0.turnoverID == nil || $0.turnoverID == turnover.id }
    }

    /// The made clip a note's answer introduced in this cut (History): only from the turnover that delivered it.
    func introduced(_ note: ReviewComment, in cut: ReviewCut, film: FilmModel) -> MadeRecord? {
        guard let t = film.turnovers.first(where: { $0.resultCutID == cut.id }) else { return nil }
        return records.first { $0.noteID == note.id && $0.turnoverID == t.id }
    }

    /// The made clip an option's version uses: one of the note's made clips that's in that option's cut.
    func record(for note: ReviewComment, option: NoteOption, answer: NoteAnswer, film: FilmModel) -> MadeRecord? {
        let candidates = records(for: note, in: film.reviewCut, film: film)
        guard !candidates.isEmpty else { return nil }
        let inCut = answer.pick ?? answer.preferred
        guard let revision = option.revision ?? (option.label == inCut ? answer.revision : nil), let project = CutProjects.project(film, revision: revision) else { return nil }
        let used = Set(project.sequences.flatMap(\.clips).compactMap(\.assetID))
        return candidates.first { used.contains($0.assetID) }
    }

    // MARK: Play it alone

    /// Plays only the made file, from its start. Again stops it.
    func playAlone(_ record: MadeRecord, film: FilmModel) {
        if playingID == record.assetID { stop(); return }
        guard !film.isPreview, let path = film.asset(record.assetID)?.path else { playingID = record.assetID; return }
        film.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: path)))
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        player.play()
        playingID = record.assetID
    }
    func stop() { player.pause(); player.replaceCurrentItem(with: nil); playingID = nil }
    var playerForPicture: AVPlayer { player }

    /// Show in Dailies: the Made group with this clip open.
    func showInDailies(_ record: MadeRecord, film: FilmModel) {
        provenanceID = nil
        dailiesID = record.assetID
        film.openTakeID = nil
        film.go(.dailies)
    }
}

extension MadeRecord {
    /// "Music · OpenRouter · Oct 28 14:02".
    var provenanceLine: String {
        let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
        return [kind == .changedShot ? "New shot" : kind.label, serviceName, f.string(from: Date(timeIntervalSince1970: createdAt))].joined(separator: " \u{00B7} ")
    }
    /// "0:24".
    var lengthText: String? { seconds.map(MadeFormat.length) }
    var icon: String {
        switch kind { case .music: "music.note"; case .soundEffect: "waveform"; case .voice: "mic"; case .shot, .changedShot: "film"; case .still: "photo" }
    }
}
