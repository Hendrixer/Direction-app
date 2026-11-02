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

/// Locking picture locks every scene with it; unlocking picture opens those again, so going back to the edit
/// never leaves the editor asking to unlock scenes the director never locked. A scene locked on its own stays.
@Test func scenesThatLockedWithThePictureOpenWithIt() throws {
    let (store, _, cut) = try directedStore()
    _ = try store.addScene(title: "Launch day")
    let own = try store.addScene(title: "The ridge")
    try store.lockScene(id: own.id, locked: true)
    try store.lockPicture(cutID: cut.id, locked: true)
    #expect(try store.dailies().scenes.allSatisfy(\.locked))
    try store.lockPicture(cutID: nil, locked: false)
    #expect(try store.dailies().scenes.filter(\.locked).map(\.id) == [own.id])

    // A film locked before scenes knew why: the ones that locked in the moment picture locked open too.
    try store.lockPicture(cutID: cut.id, locked: true)
    try store.mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Locked before") { d in
        for i in d.scenes.indices {
            d.scenes[i].lockedWithPicture = nil
            if d.scenes[i].id == own.id { d.scenes[i].lockedAt = (d.scenes[i].lockedAt ?? 0) - 3600 }
        }
    }
    try store.lockPicture(cutID: nil, locked: false)
    #expect(try store.dailies().scenes.filter(\.locked).map(\.id) == [own.id])
}

@Test func theLockedCutPlaysAndDeliversWithItsFinishing() throws {
    let (store, p, cut) = try directedStore()
    try store.lockPicture(cutID: cut.id, locked: true)
    #expect(try store.playedRevision(of: cut) == cut.editRevision)
    var grade = EditOperation("color"); grade.clipID = p.sequences[0].clips[0].id; var g = ColorGrade(); g.exposure = 0.2; grade.grade = g
    _ = try store.apply(.init(baseEditRevision: p.editRevision, summary: "Warm it", operations: [grade]))
    #expect(try store.playedRevision(of: cut) == cut.editRevision + 1)
    // Unlocked, a cut plays as it was made.
    try store.lockPicture(cutID: nil, locked: false)
    #expect(try store.playedRevision(of: cut) == cut.editRevision)
}

@Test func captionsPlacedAfterPictureLockPlayAndDeliverWithTheLockedCut() throws {
    let (store, _, cut) = try directedStore()
    var captions = MediaAsset(id: "asset-captions", name: "captions-1", path: "/captions-1.mov", duration: .init(seconds: 4), video: [.init(id: 1, width: 320, height: 180, frameRate: 30)]); captions.graphic = "captions-1"
    _ = try store.addAsset(captions, append: false, expectedRevision: try store.revision())
    try store.lockPicture(cutID: cut.id, locked: true)
    func edit(_ ops: String...) throws -> EditResult { try store.edit(EditBatch(baseEditRevision: try store.revision(), operations: ops.map { try op($0) })) }
    let placed = try edit(#"{"op":"placeGraphic","graphic":"captions-1","at":1,"seconds":3}"#)
    #expect(placed.committed)
    #expect(try store.playedRevision(of: cut) == placed.editRevision)
    expectError("picture_locked") { _ = try edit(#"{"op":"trim","clipID":"clip-main","edge":"tail","frames":-3}"#) }
    // The store's own lock rule lets the graphic come off again, and nothing else.
    var remove = EditOperation("remove"); remove.clipID = placed.operations[0].clipIDs?.first
    _ = try store.apply(.init(baseEditRevision: try store.revision(), summary: "Took the captions off", operations: [remove]))
    var trim = EditOperation("removeRange"); trim.range = MediaRange(start: 1, end: 2)
    expectError("picture_locked") { _ = try store.apply(.init(baseEditRevision: try store.revision(), summary: "Trim", operations: [trim])) }
}

@Test func creditsAndLicensesAreKeptWithTheFilm() throws {
    let (store, _, cut) = try directedStore()
    try store.lockPicture(cutID: cut.id, locked: true)
    expectError("invalid_credits") { _ = try store.saveCredits("  \n ") }
    let state = try store.saveCredits("Featuring\nMaya Chen\n\nCamera\nSam Ortiz\n")
    #expect(state.credits == "Featuring\nMaya Chen\n\nCamera\nSam Ortiz")
    #expect(state.finishing?.first { $0.id == "titles" }.map { [$0.state, $0.detail] } == ["done", "Credits written: Featuring \u{00B7} Maya Chen \u{00B7} Camera \u{00B7} Sam Ortiz"])
    // A license is copied into the film, never over another, and recorded.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("licenses-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let chosen = folder.appendingPathComponent("North Light.pdf")
    try Data("first".utf8).write(to: chosen)
    let first = try store.addLicense(from: chosen)
    try Data("second".utf8).write(to: chosen)
    let second = try store.addLicense(from: chosen)
    #expect(first.path == "Licenses/North Light.pdf" && second.path == "Licenses/North Light 2.pdf" && second.original == "North Light.pdf")
    #expect(try String(contentsOf: store.url.appendingPathComponent(first.path), encoding: .utf8) == "first")
    #expect(try String(contentsOf: store.url.appendingPathComponent(second.path), encoding: .utf8) == "second")
    let saved = try store.directingState()
    #expect(saved.licenses == [first, second] && saved.credits == state.credits)
    #expect(saved.finishing?.first { $0.id == "licenses" }.map { [$0.state, $0.detail] } == ["done", "Every track needs a license before you publish. License on file: North Light.pdf. License on file: North Light 2.pdf."])
}

@Test func aLaterLoggingBatchKeepsTheScenesBeforeIt() throws {
    let (store, _, _) = try directedStore()
    _ = try store.logDailies(Dailies(scenes: [DailiesScene(id: "scene-2", number: 2, title: "The ridge")], takes: [:]))
    #expect(try store.dailies().scenes.map(\.id) == ["scene-1", "scene-2"])
}

@Test func aCutIsDeliveredWithAnAnswerForEveryNoteOrNotAtAll() throws {
    let (store, p, cut) = try directedStore()
    let one = try store.addComment(text: "Tighter on her.", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 1), extra: NoteFields(kind: .picture))
    let two = try store.addComment(text: "Lose the second um.", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 2), extra: NoteFields(kind: .pace))
    let t = try store.turnOver(noteIDs: [one.id, two.id], latitude: .faithful, waitForOK: false, cutID: cut.id, sequenceID: nil)
    let cuts = try store.cuts().count
    expectError("note_unanswered") { _ = try store.completeTurnover(id: t.id, revision: nil, sequenceID: nil, answers: [AnswerInput(noteID: one.id, summary: "Reframed to 1.6×.")]) }
    // A bad answer late in the list leaves no cut and no answers behind.
    expectError("invalid_rule") { _ = try store.completeTurnover(id: t.id, revision: nil, sequenceID: nil, answers: [AnswerInput(noteID: one.id, summary: "Reframed to 1.6×."), AnswerInput(noteID: two.id, summary: "Cut it.", rule: RuleSuggestion(text: " ", scope: "house"))]) }
    #expect(try store.cuts().count == cuts)
    #expect(try store.notes().first { $0.id == one.id }?.answers?.isEmpty ?? true)
    _ = try store.completeTurnover(id: t.id, revision: nil, sequenceID: nil, answers: [AnswerInput(noteID: one.id, summary: "Reframed to 1.6×."), AnswerInput(noteID: two.id, summary: "Couldn\u{2019}t: it\u{2019}s under the music cue. Trim the cue and I can.")])
    #expect(try store.cuts().count == cuts + 1)
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

@Test func anAnswerCanOfferARuleAndTheDirectorKeepsItInTheStyleOrTheHouseStyle() throws {
    let (store, p, cut) = try directedStore()
    let styles = store.url.deletingLastPathComponent().appendingPathComponent("Styles-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: styles) }
    try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
    let style = try StyleLibrary.create(name: "Desk Talk", summary: "", rules: [StyleRule(area: "music", text: "Music 24 dB under the voice.")], in: styles)
    var brief = Brief(); brief.logline = "Maya builds it."; brief.feeling = "Proud."; brief.style = style.id
    try store.saveBrief(brief, styles: styles)

    let note = try store.addComment(text: "Never put words over my face. Ever.", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 1), extra: NoteFields(kind: .picture))
    let t = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: false, cutID: cut.id, sequenceID: nil)
    expectError("invalid_rule") { _ = try store.completeTurnover(id: t.id, revision: nil, sequenceID: nil, answers: [AnswerInput(noteID: note.id, summary: "Moved the title.", rule: RuleSuggestion(text: " ", scope: "house"))]) }
    _ = try store.completeTurnover(id: t.id, revision: nil, sequenceID: nil, answers: [AnswerInput(noteID: note.id, summary: "Moved the title off your face.", rule: RuleSuggestion(text: "Text never covers my face.", area: "graphics", scope: "house"))])
    #expect(try store.notes().first { $0.id == note.id }?.answers?.last?.rule?.text == "Text never covers my face.")

    // Kept for the film's style: the style in the folder and the film's own copy both have it, and the answer knows where it went.
    let kept = try store.keepRule("Text never covers my face.", area: "graphics", inFilmStyle: true, noteID: note.id, styles: styles)
    #expect(kept.styleID == "desk-talk" && kept.styleName == "Desk Talk")
    let master = try StyleLibrary.read(style.url), copy = try store.style()
    #expect(master.rules.last?.text == "Text never covers my face." && copy?.rules.last?.kept?.film == p.name)
    #expect(try store.notes().first { $0.id == note.id }?.answers?.last?.keptRule == kept)

    // Kept for every film, in place of a style rule it overrides: the house style gets it, the style loses the old one.
    let old = try #require(try StyleLibrary.read(style.url).rules.first { $0.area == "music" })
    let house = try store.keepRule("Music 25 dB under my voice.", area: "music", inFilmStyle: false, replacing: [old.id], styles: styles)
    #expect(house.styleID == StyleLibrary.houseID && StyleLibrary.house(in: styles).rules.map(\.text) == ["Music 25 dB under my voice."])
    #expect(try store.style()?.rules.contains { $0.id == old.id } == false)
    let applied = try store.appliedStyle(styles: styles)
    #expect(applied.rules.map(\.styleName) == ["House style", "Desk Talk"])

    // A film whose style has left the folder keeps rules only in the house style.
    try FileManager.default.removeItem(at: style.url)
    expectError("style_not_found") { _ = try store.keepRule("Hard cuts only.", area: nil, inFilmStyle: true, styles: styles) }
}
