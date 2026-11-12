import Testing
import Foundation
import DirectionCore
import DirectionTools
@testable import DirectionApp

/// The Cut room (specs/cut.md): watching, notes and the editor's answers on one cut.
@MainActor
struct CutRoomTests {
    /// Five rooms, and the one for the cut opens whatever it needs: Screening, Notes and Changes are gone.
    @Test func oneRoomForTheCut() {
        #expect(Room.allCases == [.script, .breakdown, .dailies, .cut, .finish])
        #expect(Room.cut.title == "Cut" && Room.cut.shortcut == "4" && Room.finish.shortcut == "5")
        let m = ChangesFixtures.cut4()
        #expect(m.defaultRoom == .cut)
        m.room = .dailies
        m.watchThrough()
        #expect(m.room == .cut && m.watchingCut)
        // Esc goes back to the sheet; going to another room leaves watching too.
        m.endScreening()
        #expect(m.room == .cut && !m.watchingCut)
        m.watchThrough()
        m.go(.dailies)
        #expect(!m.watchingCut)
    }

    /// Each answer sits under the note it answers, ahead of the notes for the next turnover. An answer acted on
    /// stays where it was until you leave; once none is left to look at, the answered notes fold to one line.
    @Test func eachAnswerSitsUnderItsNoteThenFolds() {
        let m = ChangesFixtures.cut4()
        let answered = m.reviewAnswers.map(\.id)
        #expect(answered.count == 7)
        #expect(m.sheetAnswers.map(\.id) == answered)
        #expect(m.sheetNotesBelow.allSatisfy { !answered.contains($0.id) })
        #expect(Array(m.sheetRows.prefix(answered.count).map(\.id)) == answered)
        m.acceptAnswerFromChanges("note-1")
        #expect(m.status(m.note("note-1")!) == .accepted && m.sheetAnswers.first?.id == "note-1")
        for n in 2...7 { ChangesFixtures.accept(m, n) }
        m.changes.sticky = []
        #expect(m.toReview.isEmpty && m.sheetAnswers.isEmpty)
        #expect(m.answersLine == "all 7 answered")
        m.changes.showAllAnswers = true
        #expect(m.sheetAnswers.count == 7)
    }

    /// ↑ and ↓ walk the answers, then the notes; the sheet only ever has one row selected.
    @Test func arrowsWalkTheAnswersThenTheNotes() {
        let m = ChangesFixtures.cut4()
        m.notes.append(SampleFilm.note(8, "Hold the last shot longer.", time: SampleFilm.tc(3, 20)))
        m.selectedAnswerNoteID = nil; m.selectedNoteID = nil
        m.selectAdjacentNote(1)
        #expect(m.selectedAnswerNoteID == "note-1" && m.selectedNoteID == nil)
        for _ in 0..<7 { m.selectAdjacentNote(1) }
        #expect(m.selectedNoteID == "note-8" && m.selectedAnswerNoteID == nil)
        m.selectAdjacentNote(-1)
        #expect(m.selectedAnswerNoteID == "note-7" && m.selectedNoteID == nil)
    }

    /// The one steel button follows what's waiting: Accept while answers wait, Turn over once you've written a
    /// note, Start cutting while a read-back waits, Lock picture once everything is accepted.
    @Test func theOneButtonFollowsWhatsWaiting() {
        let m = ChangesFixtures.cut4()
        // Six can be accepted at once; the one with two versions waits for your pick.
        #expect(m.primaryAction?.title == "Accept" && m.primaryAction?.count == "6")
        m.notes.append(SampleFilm.note(8, "Hold the last shot longer.", time: SampleFilm.tc(3, 20)))
        #expect(m.primaryAction?.title == "Turn over" && m.primaryAction?.count == "1")
        m.notes.removeAll { $0.id == "note-8" }
        for n in 1...7 { ChangesFixtures.accept(m, n) }
        #expect(m.showsLockBar && m.primaryAction?.title == "Lock picture\u{2026}")
        let r = SampleFilm.make()
        SampleFilm.withTurnover(r, state: .readBack, readBack: true)
        #expect(r.primaryAction?.title == "Start cutting")
        // While you watch through, nothing in the titlebar asks for a click.
        m.watchingCut = true
        #expect(m.primaryAction == nil)
    }

    /// The Cut tab counts what's waiting on you: the editor's answers and questions first, in its color, then
    /// marks to write up and outside notes, in yours.
    /// A read-back's change sits beside its plan when it's a measure; a longer one goes under the plan, so the plan
    /// keeps the row's width (an editor once wrote "+0 s (graphic on V2 over the opening)" there).
    @Test func aLongChangeGoesUnderThePlan() {
        for short in ["\u{2212}4.2 s", "1.6\u{00D7}", "crop", "\u{2212}6 dB", "+12.4 s"] { #expect(ReadBackLineView.besidePlan(short), "\(short)") }
        #expect(!ReadBackLineView.besidePlan("+0 s (graphic on V2 over the opening)"))
    }

    @Test func theCutTabCountsTheEditorsWorkFirst() {
        let m = ChangesFixtures.question()
        #expect(m.badge(for: .cut)?.0 == "8" && m.badge(for: .cut)?.1 == false)
        m.questions = []
        #expect(m.badge(for: .cut)?.0 == "7" && m.badge(for: .cut)?.1 == false)
        let d = SampleFilm.make()
        #expect(d.badge(for: .cut)?.0 == "2" && d.badge(for: .cut)?.1 == true)
    }

    /// An older cut, picked from the crumb, is looked back at: every answer it gave shows, done, and esc or the
    /// sheet's Back goes to the latest.
    @Test func anOlderCutIsLookedBackAt() {
        let m = ChangesFixtures.cut4()
        for n in 1...7 { ChangesFixtures.accept(m, n) }
        m.watch(m.cuts.first { $0.name == "Cut 3" })
        #expect(m.looksBack && m.primaryAction?.title == "Watch Cut 3")
        m.watch(m.latestCut)
        #expect(!m.looksBack && m.watchedCutID == nil)
    }

    /// Marks dropped while watching through wait on the sheet as notes to write, the first one open.
    @Test func watchingThroughEndsOnTheMarks() {
        let m = ScreeningFixtures.screening(marks: 3, at: SampleFilm.tc(2, 0))
        m.endScreening()
        #expect(!m.watchingCut && m.selectedNoteID == "note-1" && m.notesTab == .sheet)
        #expect(m.position == SampleFilm.tc(0, 18, 4))
    }

    /// Turning over with answers you haven't looked at keeps them: what you don't push back on stays in the cut.
    @Test func turningOverKeepsTheAnswersYouDidntReplyTo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("direction-cut-room-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProjectStore.create(at: directory.appendingPathComponent("Film.direction"), name: "Kept")
        var format = EditOperation("format"); format.width = 640; format.height = 360
        _ = try store.apply(.init(baseEditRevision: store.revision(), operations: [format]))
        let first = try store.createCut(name: "Assembly", sequenceID: nil, revision: nil)
        let one = try store.addComment(text: "Tighter on her.", sequenceID: nil, revision: store.revision(), cutID: first.id, extra: NoteFields(kind: .picture))
        let two = try store.addComment(text: "Let it sit.", sequenceID: nil, revision: store.revision(), cutID: first.id, extra: NoteFields(kind: .feeling))
        let t = try store.turnOver(noteIDs: [one.id, two.id], latitude: .faithful, waitForOK: false, cutID: first.id, sequenceID: nil)
        _ = try store.reportTurnover(id: t.id, state: .cutting, readBack: nil, progress: nil, phase: nil, percent: nil, message: nil)
        _ = try store.completeTurnover(id: t.id, revision: nil, sequenceID: nil, answers: [AnswerInput(noteID: one.id, summary: "Reframed to 1.6\u{00D7}."), AnswerInput(noteID: two.id, summary: "Held the wide.")])

        let m = FilmModel()
        m.runtime = try ToolRuntime(store: store)
        m.refresh(force: true)
        #expect(m.unreviewedAnswers.count == 2)
        m.reopen(two.id, text: "Not quite. Longer.")
        m.refresh(force: true)
        #expect(m.note(two.id)?.lifecycle == .reopened && m.readyNotes.map(\.id) == [two.id])
        m.turnOver(latitude: .faithful, waitForOK: true)
        m.refresh(force: true)
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(m.note(one.id)?.lifecycle == .accepted)
        // The note you replied to goes with the turnover; the one you didn't stays in the cut, accepted.
        #expect(m.note(two.id)?.noteState == .turnedOver)
        #expect(m.unreviewedAnswers.isEmpty)
    }
}
