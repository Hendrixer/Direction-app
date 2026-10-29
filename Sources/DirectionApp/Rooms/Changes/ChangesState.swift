import SwiftUI
import ObjectiveC
import DirectionCore

// Owner: Changes and Finish agent. State and derived data shared by the Changes room (29–33)
// and the lock bar (34). Kept beside FilmModel so drafts and the open reel survive room switches.

enum AnswersTab: String, CaseIterable, Identifiable {
    case review, accepted, all
    var id: String { rawValue }
    var title: String { switch self { case .review: "To review"; case .accepted: "Accepted"; case .all: "All" } }
}

/// Where an answer stands for the director.
enum AnswerStatus: Equatable { case unreviewed, accepted, reopened }

/// Changes-room state that has to outlive the view: tabs, reply drafts, the reel overlay, history.
@MainActor @Observable
final class ChangesState {
    enum Mode { case answers, history }
    var mode: Mode = .answers
    /// nil follows the room: To review while anything waits, Accepted once nothing does.
    var chosenTab: AnswersTab?
    /// Rows acted on during this visit stay in To review (done) until the director leaves the tab.
    var sticky: Set<String> = []
    var replyingNoteID: String?
    /// Reply drafts by note, kept across rooms; esc keeps them.
    var drafts: [String: String] = [:]
    /// Play changes is on screen (31). It stays up on the end card after the reel finishes.
    var reelOpen = false
    var historyCutID: String?
    var historyNoteID: String?
    var revertNoteID: String?
    /// Compare whole cuts (A/B of the previous cut and the selected one).
    var comparingCuts = false
    var confirmAcceptAll = false
    /// The lock bar's selected tile.
    var lockSceneID: String?
    var lockAnchorID: String?
    var unlockSceneID: String?
    /// The A/B card the director clicked (it gets the ring and the sound).
    var optionFocus: Int?
    /// Set for a moment after Use A or Use B, while the other card fades.
    var optionChosen: String?
    /// The A/B players on screen, so the room's keys can drive them.
    @ObservationIgnored weak var ab: ABPlayback?
}

private nonisolated(unsafe) var changesStateKey: UInt8 = 0

/// Revision-pinned projects are immutable, so they're read once per film and kept.
@MainActor
enum CutProjects {
    /// Previews have no store; fixtures register the projects of earlier cuts here.
    static var preview: [Int: Project] = [:]
    private static var cache: [String: Project] = [:]
    static func project(_ model: FilmModel, revision: Int) -> Project? {
        if model.isPreview { return preview[revision] ?? (model.project?.editRevision == revision ? model.project : nil) }
        if model.project?.editRevision == revision, let p = model.project { return p }
        let key = "\(model.url?.path ?? ""):\(revision)"
        if let p = cache[key] { return p }
        guard let p = try? model.store?.read(revision: revision) else { return nil }
        cache[key] = p
        return p
    }
}

extension FilmModel {
    var changes: ChangesState {
        if let s = objc_getAssociatedObject(self, &changesStateKey) as? ChangesState { return s }
        let s = ChangesState()
        objc_setAssociatedObject(self, &changesStateKey, s, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return s
    }

    // MARK: Cuts

    /// The cut the Changes room reviews: the one on screen.
    var reviewCut: ReviewCut? { watchedCut }
    func cutBefore(_ cut: ReviewCut?) -> ReviewCut? { cut.flatMap { c in cuts.last { $0.createdAt < c.createdAt } } }
    func cutProject(_ cut: ReviewCut?) -> Project? { cut.flatMap { CutProjects.project(self, revision: $0.editRevision) } }
    func cutSequence(_ cut: ReviewCut?) -> DirectionCore.Sequence? { cut.flatMap { c in try? cutProject(c)?.sequence(c.sequenceID) } }
    func cutDuration(_ cut: ReviewCut?) -> Double? { cutSequence(cut)?.duration.seconds }
    func cut(atRevision revision: Int?) -> ReviewCut? { revision.flatMap { r in cuts.last { $0.editRevision <= r } } }

    // MARK: Answers

    var reviewAnswers: [ReviewComment] { answers(in: reviewCut) }
    func status(_ c: ReviewComment, in cut: ReviewCut? = nil) -> AnswerStatus {
        let cut = cut ?? reviewCut
        guard let a = answer(c, in: cut) else { return .unreviewed }
        if a.state == "accepted" { return .accepted }
        if a.state == "reopened" { return .reopened }
        let isLatest = c.latestAnswer?.cutID == cut?.id
        if isLatest && c.lifecycle == .accepted { return .accepted }
        if isLatest && c.lifecycle == .reopened { return .reopened }
        return .unreviewed
    }
    var toReview: [ReviewComment] { reviewAnswers.filter { status($0) == .unreviewed } }
    var acceptedAnswers: [ReviewComment] { reviewAnswers.filter { status($0) == .accepted } }
    var answersTab: AnswersTab { changes.chosenTab ?? (toReview.isEmpty && !reviewAnswers.isEmpty ? .accepted : .review) }
    func answers(for tab: AnswersTab) -> [ReviewComment] {
        switch tab {
        case .review: reviewAnswers.filter { status($0) == .unreviewed || changes.sticky.contains($0.id) }
        case .accepted: acceptedAnswers
        case .all: reviewAnswers
        }
    }
    func count(for tab: AnswersTab) -> Int {
        switch tab { case .review: toReview.count; case .accepted: acceptedAnswers.count; case .all: reviewAnswers.count }
    }
    func hasOptions(_ c: ReviewComment) -> Bool { !(answer(c, in: reviewCut)?.options ?? []).isEmpty }
    func answerRange(_ c: ReviewComment, in cut: ReviewCut? = nil) -> ClosedRange<Double>? {
        answer(c, in: cut ?? reviewCut)?.range.map { $0.start.seconds...max($0.start.seconds, $0.end.seconds) }
    }
    /// The scene an answer changed, as it sits in the cut on screen.
    func answerScene(_ c: ReviewComment) -> StripScene? {
        if let r = answerRange(c) { return stripScene(at: r.lowerBound) }
        if let id = c.sceneID { return stripScenes.first { $0.id == id } }
        return nil
    }
    func answerSceneTitle(_ c: ReviewComment) -> String? {
        if let s = answerScene(c) { return s.title.isEmpty ? "Scene \(s.number)" : s.title }
        return scene(c.sceneID)?.title
    }
    /// The answer's delta. The answers list keeps "A / B" for options; the changelog shows the picked version's delta.
    func deltaText(_ c: ReviewComment, in cut: ReviewCut? = nil, picked: Bool = false) -> String {
        guard let a = answer(c, in: cut ?? reviewCut) else { return "" }
        if let d = a.delta, !d.isEmpty { return d }
        if picked, let pick = a.pick, let d = a.options?.first(where: { $0.label == pick })?.delta { return d }
        return (a.options?.count ?? 0) > 1 ? (a.options ?? []).map(\.label).joined(separator: " / ") : ""
    }
    func kindLabel(_ c: ReviewComment) -> String { c.isUnasked ? "Unasked" : c.kind?.label ?? "Note" }
    /// Editor diamonds on the strip, one per answer.
    var answerMarks: [StripMark] {
        reviewAnswers.compactMap { c in answerRange(c).map { StripMark(id: c.id, time: $0.lowerBound, kind: .editor) } }
    }
    func noteLabel(_ c: ReviewComment) -> String { c.number.map { "note \($0)" } ?? "this change" }

    /// What the director sees in the Done column: "Accepted" or "Used B".
    func doneLabel(_ c: ReviewComment) -> String {
        if let pick = answer(c, in: reviewCut)?.pick, hasOptions(c) { return "Used \(pick)" }
        return "Accepted"
    }

    // MARK: Director actions on answers

    /// Selects an answer and cues the picture a handle before its change.
    func selectAnswer(_ c: ReviewComment, cue: Bool = true) {
        selectedAnswerNoteID = c.id
        if cue, let r = answerRange(c) { pause(); seek(max(0, r.lowerBound - handleSeconds)) }
    }
    var selectedAnswer: ReviewComment? { selectedAnswerNoteID.flatMap { id in reviewAnswers.first { $0.id == id } } }
    /// Keeps the current tab and row in place while the director works through the list.
    private func holdList(_ id: String) {
        if changes.chosenTab == nil { changes.chosenTab = answersTab }
        changes.sticky.insert(id)
    }
    private func selectNext(after id: String) {
        let list = answers(for: answersTab)
        let start = (list.firstIndex { $0.id == id } ?? -1) + 1
        if let next = (list[min(start, list.count)...] + list[..<min(start, list.count)]).first(where: { status($0) == .unreviewed && $0.id != id }) { selectAnswer(next) }
    }
    func acceptAnswerFromChanges(_ id: String, advance: Bool = true) {
        guard let c = note(id), status(c) == .unreviewed else { return }
        if hasOptions(c) && answer(c, in: reviewCut)?.pick == nil { comparingNoteID = id; selectedAnswerNoteID = id; return }
        holdList(id)
        if isPreview { previewAccept(id) } else { acceptAnswer(id) }
        if advance { selectNext(after: id) }
    }
    /// Use A or Use B: writes the pick and accepts the answer.
    func useOption(_ id: String, _ label: String) {
        holdList(id)
        if isPreview { previewAccept(id, pick: label) } else { pickOption(id, label); acceptAnswer(id) }
        if comparingNoteID == id { comparingNoteID = nil }
        selectNext(after: id)
    }
    /// From the A/B stage: the unchosen card fades to 40%, then the stage returns to one picture.
    func chooseOption(_ id: String, _ label: String) {
        guard comparingNoteID == id, changes.optionChosen == nil else { useOption(id, label); return }
        withAnimation(gateAnimation(Gate.Motion.settle)) { changes.optionChosen = label }
        Task {
            try? await Task.sleep(for: .seconds(Gate.Motion.settleDuration + 0.04))
            useOption(id, label)
            changes.optionChosen = nil
        }
    }
    var acceptableRemaining: [ReviewComment] { toReview.filter { !hasOptions($0) || answer($0, in: reviewCut)?.pick != nil } }
    func acceptAllRemaining() {
        for c in acceptableRemaining { holdList(c.id); if isPreview { previewAccept(c.id) } else { acceptAnswer(c.id) } }
    }
    /// Opens the reply thread under an answer (32).
    func replyToAnswer(_ id: String? = nil) {
        guard let id = id ?? selectedAnswerNoteID, let c = note(id), answer(c, in: reviewCut) != nil, !isPictureLocked else { return }
        if changes.reelOpen { closeReel() }
        if room != .changes { go(.changes) }
        changes.mode = .answers
        comparingNoteID = nil
        selectAnswer(c)
        withAnimation(gateAnimation(Gate.Motion.glide)) { changes.replyingNoteID = id }
    }
    func cancelReply() { withAnimation(gateAnimation(Gate.Motion.glide)) { changes.replyingNoteID = nil } }
    /// Sends "Not quite…": reopens the note for the next turnover. Never starts cutting.
    func sendReply(_ id: String) {
        let text = (changes.drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        holdList(id)
        reopen(id, text: text)
        if error == nil || isPreview { changes.drafts[id] = nil }
        cancelReply()
        selectNext(after: id)
    }
    func acceptSelectedAnswer() { if let id = selectedAnswerNoteID { acceptAnswerFromChanges(id) } }

    // MARK: Reel

    /// Opens Play changes (31), from the start or from one answer.
    func openChangesReel(from noteID: String? = nil) {
        if room != .changes { go(.changes) }
        changes.mode = .answers
        changes.replyingNoteID = nil
        comparingNoteID = nil
        let reel = changeReel(in: watchedCut)
        guard !reel.isEmpty else { return }
        changes.reelOpen = true
        playChanges()
        if let noteID, let c = note(noteID), let r = answerRange(c), let i = reel.firstIndex(where: { $0.overlaps(r) }) {
            changeIndex = i; seek(reel[i].lowerBound)
        }
    }
    func closeReel() {
        let current = playingAnswer
        stopChanges()
        changes.reelOpen = false
        if let current { selectedAnswerNoteID = current.id }
    }
    /// Answers in film order: the reel's order.
    var reelAnswers: [ReviewComment] {
        reviewAnswers.filter { answerRange($0) != nil }.sorted { (answerRange($0)?.lowerBound ?? 0) < (answerRange($1)?.lowerBound ?? 0) }
    }
    /// The change under the playhead, or the next one inside the current reel passage.
    var playingAnswer: ReviewComment? {
        let list = reelAnswers
        if let inside = list.last(where: { answerRange($0)?.contains(position) ?? false }) { return inside }
        let reel = changeReel(in: watchedCut)
        let passage = reel.indices.contains(changeIndex) ? reel[changeIndex] : reel.first { $0.contains(position) }
        if let passage { return list.first { r in answerRange(r).map { passage.overlaps($0) && $0.lowerBound >= position } ?? false } ?? list.last { r in answerRange(r).map { passage.overlaps($0) } ?? false } }
        return nil
    }
    /// True while the playhead is on untouched picture either side of a change.
    var inHandle: Bool { !reelAnswers.contains { answerRange($0)?.contains(position) ?? false } }

    // MARK: Revert (33)

    static let revertPrefix = "Put this back the way it was in"
    func revertText(_ c: ReviewComment) -> String {
        let before = cutBefore(cuts.first { $0.id == answer(c, in: historyCut)?.cutID } ?? historyCut)?.name ?? "the cut before"
        return "\(Self.revertPrefix) \(before)."
    }
    /// A revert is a reopen whose last words ask for the old version back.
    func revertReply(_ c: ReviewComment) -> FeedbackReply? {
        guard c.lifecycle == .reopened || c.noteState == .turnedOver, let last = c.replies.last(where: { $0.author == "Director" }), last.text.hasPrefix(Self.revertPrefix) else { return nil }
        return last
    }
    func revertChange(_ id: String) {
        guard let c = note(id) else { return }
        reopen(id, text: revertText(c))
        changes.revertNoteID = nil
    }
    /// Put back: the change stays as the editor made it.
    func putBack(_ id: String) {
        if isPreview { previewAccept(id) } else { acceptAnswer(id) }
    }
    var historyCut: ReviewCut? { changes.historyCutID.flatMap { id in cuts.first { $0.id == id } } ?? reviewCut ?? latestCut }
    func showCutHistory() {
        if room != .changes { go(.changes) }
        if changes.reelOpen { closeReel() }
        changes.historyCutID = changes.historyCutID ?? watchedCut?.id
        withAnimation(gateAnimation(Gate.Motion.settle)) { changes.mode = .history }
    }
    func showAnswers() { withAnimation(gateAnimation(Gate.Motion.settle)) { changes.mode = .answers; changes.comparingCuts = false } }
    /// Compare whole cuts: the A/B layout with the cut before and this one, synced.
    func compareWholeCuts(_ cut: ReviewCut) {
        changes.historyCutID = cut.id
        comparingNoteID = nil
        withAnimation(gateAnimation(Gate.Motion.settle)) { changes.mode = .answers; changes.comparingCuts = true }
    }

    // MARK: Previews

    /// Snapshots have no store: mirror what the store does so the frames can show the result.
    private func previewAccept(_ id: String, pick: String? = nil) {
        guard let i = notes.firstIndex(where: { $0.id == id }), var a = notes[i].answers?.last else { return }
        a.state = "accepted"; if let pick { a.pick = pick } else if a.options != nil && a.pick == nil { a.pick = a.preferred }
        notes[i].answers![notes[i].answers!.count - 1] = a
        notes[i].status = "accepted"; notes[i].noteState = .accepted
    }
}

/// A button label with a small (`.ico.s`) symbol: "✓ Accept", "↺ History".
struct SmallIconLabel: View {
    var title: String
    var icon: String
    var size: CGFloat = 10
    init(_ title: String, icon: String, size: CGFloat = 10) { self.title = title; self.icon = icon; self.size = size }
    var body: some View {
        Label { Text(title) } icon: { Image(systemName: icon).font(.system(size: size, weight: .semibold)) }
    }
}

// MARK: Formatting

enum ChangesFormat {
    /// "9 s shorter than Cut 3".
    static func lengthChange(_ delta: Double, than name: String) -> String {
        let s = Int(abs(delta).rounded())
        guard s > 0 else { return "Same length as \(name)" }
        let amount = s >= 60 ? Timecode.duration(Double(s)) : "\(s) s"
        return "\(amount) \(delta < 0 ? "shorter" : "longer") than \(name)"
    }
    /// "−9 s" for cut lists.
    static func signedSeconds(_ delta: Double) -> String {
        let s = Int(delta.rounded())
        return s == 0 ? "±0 s" : (s < 0 ? "\u{2212}" : "+") + "\(abs(s)) s"
    }
    /// "00:00–00:27", minutes and seconds.
    static func shortRange(_ a: Double, _ b: Double) -> String { "\(mmss(a))\u{2013}\(mmss(b))" }
    static func mmss(_ t: Double) -> String { let s = Int(max(0, t).rounded()); return String(format: "%02d:%02d", s / 60, s % 60) }
    /// "Oct 28 · 14:09".
    static func when(_ t: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d \u{00B7} HH:mm"; return f.string(from: Date(timeIntervalSince1970: t))
    }
    static func dayAndTime(_ t: Double, joiner: String = " at ") -> String {
        let d = DateFormatter(); d.dateFormat = "MMM d"
        let h = DateFormatter(); h.dateFormat = "HH:mm"
        let date = Date(timeIntervalSince1970: t)
        return "\(d.string(from: date))\(joiner)\(h.string(from: date))"
    }
    static func time(_ t: Double) -> String { let h = DateFormatter(); h.dateFormat = "HH:mm"; return h.string(from: Date(timeIntervalSince1970: t)) }
    /// The first clause of an answer, as a changelog line: "Cut the second street wide."
    static func headline(_ summary: String) -> String {
        var s = summary
        if let r = s.range(of: "; ") { s = String(s[..<r.lowerBound]) }
        else if let r = s.range(of: ". ") { s = String(s[..<r.lowerBound]) }
        s = s.trimmingCharacters(in: .whitespaces)
        if let last = s.last, !".!?\u{201D}".contains(last) { s += "." }
        return s
    }
}
