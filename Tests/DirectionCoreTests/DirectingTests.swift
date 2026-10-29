import Testing
import Foundation
@testable import DirectionCore

/// A store with one take logged into scene 1 and a first cut named.
private func directedStore() throws -> (ProjectStore, Project, ReviewCut) {
    let store = try seededStore()
    _ = try store.logDailies(Dailies(scenes: [DailiesScene(id: "scene-1", number: 1, title: "Cold open")], takes: ["asset-fixture": {
        var t = TakeInfo(assetID: "asset-fixture"); t.sceneID = "scene-1"; t.code = "T1"; t.suggestion = "Steadiest"; return t
    }()]))
    let p = try store.read()
    let cut = try store.createCut(name: "Assembly", sequenceID: nil, revision: nil)
    return (store, p, cut)
}

@Test func notesAreNumberedForLifeAndNeverReused() throws {
    let (store, p, cut) = try directedStore()
    let one = try store.addComment(text: "Too long to her face.", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 1), extra: NoteFields(kind: .pace))
    let two = try store.addComment(text: "", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 2), extra: NoteFields(noteState: .draft))
    try store.dropNote(id: two.id)
    let three = try store.addComment(text: "Let it sit.", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 3), extra: NoteFields(kind: .feeling))
    #expect([one.number, two.number, three.number] == [1, 2, 3])
    #expect(try store.notes().first { $0.id == two.id }?.lifecycle == .dropped)
}

@Test func draftsDroppedAndInboxNotesStayPrivate() throws {
    let (store, p, cut) = try directedStore()
    let draft = try store.addComment(text: "", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 2), extra: NoteFields(noteState: .draft))
    let outside = try store.addComment(text: "Logo bigger?", author: "Tom Reyes", sequenceID: nil, revision: p.editRevision, extra: NoteFields(authorRole: "outside", person: Person(name: "Tom Reyes", role: "Client"), assignNumber: false))
    #expect(!draft.visibleToEditor)
    #expect(!outside.visibleToEditor && outside.inInbox && outside.number == nil)
    try store.acceptOutside(id: outside.id)
    let accepted = try store.notes().first { $0.id == outside.id }!
    #expect(accepted.visibleToEditor && accepted.number == 2)
}

@Test func turnoverWaitsForTheReadBackOKThenDeliversANamedCut() throws {
    let (store, p, cut) = try directedStore()
    let note = try store.addComment(text: "Tighter on her.", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 1), extra: NoteFields(kind: .picture))
    let t = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: true, cutID: cut.id, sequenceID: nil)
    #expect(try store.notes().first { $0.id == note.id }?.lifecycle == .turnedOver)
    expectError("turnover_open") { _ = try store.turnOver(noteIDs: [note.id], latitude: .exact, waitForOK: false, cutID: nil, sequenceID: nil) }
    expectError("note_turned_over") { _ = try store.editNote(id: note.id, text: "Changed my mind") }

    var reported = try store.reportTurnover(id: t.id, state: nil, readBack: [ReadBackLine(noteID: note.id, plan: "Reframe to 1.6× on Maya.", delta: "crop")], progress: nil, phase: "Reading back", percent: nil, message: nil)
    #expect(reported.state == .readBack)
    expectError("readback_not_approved") { _ = try store.reportTurnover(id: t.id, state: .cutting, readBack: nil, progress: nil, phase: nil, percent: nil, message: nil) }
    reported = try store.adjustReadBack(turnoverID: t.id, noteID: note.id, text: "Not that tight.")
    #expect(reported.adjustments[note.id] == "Not that tight.")
    reported = try store.approveReadBack(turnoverID: t.id)
    #expect(reported.state == .cutting)

    let (closed, newCut) = try store.completeTurnover(id: t.id, revision: nil, sequenceID: nil, answers: [AnswerInput(noteID: note.id, summary: "Reframed to 1.6× on Maya.", delta: "crop", start: 0.5, end: 2)])
    #expect(closed.state == .delivered && closed.resultCutID == newCut.id)
    #expect(newCut.name == "Cut 2")
    let answered = try store.notes().first { $0.id == note.id }!
    #expect(answered.lifecycle == .answered && answered.latestAnswer?.range?.start.seconds == 0.5)

    try store.reopenAnswer(noteID: note.id, text: "Still too much sky.")
    #expect(try store.notes().first { $0.id == note.id }?.lifecycle == .reopened)
}

@Test func questionsNeedConcreteChoices() throws {
    let (store, _, _) = try directedStore()
    expectError("invalid_question") { _ = try store.ask(EditorQuestion(id: "q", turnoverID: nil, kind: "question", noteIDs: [], text: "Which?", detail: nil, choices: [.init(id: "a", label: "Only one")], allowsText: true, answer: nil, createdAt: 0)) }
    let q = try store.ask(EditorQuestion(id: "q", turnoverID: nil, kind: "question", noteIDs: [], text: "Which reading?", detail: nil, choices: [.init(id: "t2", label: "Use T2"), .init(id: "t5", label: "Use T5")], allowsText: true, answer: nil, createdAt: 0))
    expectError("invalid_choice") { _ = try store.answerQuestion(id: q.id, choiceID: "t9", text: nil) }
    #expect(try store.answerQuestion(id: q.id, choiceID: "t5", text: nil).answer?.choiceID == "t5")
}

@Test func lockedScenesAreUntouchableButOtherworkContinues() throws {
    let (store, p, _) = try directedStore()
    try store.lockScene(id: "scene-1", locked: true)
    var trim = EditOperation("removeRange"); trim.range = MediaRange(start: 1, end: 2)
    expectError("scene_locked") { _ = try store.apply(.init(baseEditRevision: p.editRevision, summary: "Trim", operations: [trim])) }
    try store.lockScene(id: "scene-1", locked: false)
    _ = try store.apply(.init(baseEditRevision: p.editRevision, summary: "Trim", operations: [trim]))
}

@Test func pictureLockStopsTimingButNotColor() throws {
    let (store, p, _) = try directedStore()
    try store.lockPicture(cutID: nil, locked: true)
    var trim = EditOperation("removeRange"); trim.range = MediaRange(start: 1, end: 2)
    expectError("picture_locked") { _ = try store.apply(.init(baseEditRevision: p.editRevision, summary: "Trim", operations: [trim])) }
    var grade = EditOperation("color"); grade.clipID = p.sequences[0].clips[0].id; var g = ColorGrade(); g.exposure = 0.2; grade.grade = g
    _ = try store.apply(.init(baseEditRevision: p.editRevision, summary: "Warm it", operations: [grade]))
    #expect(try store.directingState().finishing?.count == FinishingItem.defaults.count)
}

@Test func pictureLockWaitsForOpenNotes() throws {
    let (store, p, cut) = try directedStore()
    _ = try store.addComment(text: "Open note.", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 1))
    expectError("notes_open") { try store.lockPicture(cutID: cut.id, locked: true) }
}

@Test func theEditorCanSuggestButNeverCircle() throws {
    let (store, _, _) = try directedStore()
    try store.setCircle(assetID: "asset-fixture", circled: true)
    var t = TakeInfo(assetID: "asset-fixture"); t.circled = false; t.suggestion = "Warmer read"
    let logged = try store.logDailies(Dailies(scenes: try store.dailies().scenes, takes: ["asset-fixture": t]))
    #expect(logged.take("asset-fixture").circled)
    #expect(logged.take("asset-fixture").suggestion == "Warmer read")
}

@Test func deletingASceneSendsItsTakesToUnsortedAndCanBeUndone() throws {
    let (store, _, _) = try directedStore()
    try store.setCircle(assetID: "asset-fixture", circled: true)
    let (scene, takes) = try store.deleteScene(id: "scene-1")
    #expect(try store.dailies().scenes.isEmpty)
    #expect(try store.dailies().take("asset-fixture").sceneID == nil)
    #expect(try store.dailies().take("asset-fixture").circled)
    try store.restoreScene(scene, takes: takes)
    #expect(try store.dailies().take("asset-fixture").sceneID == "scene-1")
    try store.lockScene(id: "scene-1", locked: true)
    expectError("scene_locked") { _ = try store.deleteScene(id: "scene-1") }
}
