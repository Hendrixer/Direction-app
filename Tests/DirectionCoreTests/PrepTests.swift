import Testing
import Foundation
@testable import DirectionCore

/// Prep (specs/script.md, specs/breakdown.md): a script comes in, the editor writes its picture, the director
/// keeps the last word, and the breakdown's shot numbers become the slates Dailies files takes by.
struct PrepTests {
    private let essay = """
    ---
    stage: plan
    ---
    # The Chat Box

    ## Cold open

    [Black. The question types on.]

    Open any app you used five years ago. It has a chat box now. I build these for a living. [me at the desk, dark]

    ## Everyone added one

    It started with the obvious ones. Writing apps. Code editors. Then the calendar got one. Then my thermostat.

    [ON CAMERA]

    So here's what I think actually happened.

    SCOTT: Nobody asked for it. Not once.
    """

    @Test func proseBecomesSectionsAndBeatsWithTheWritersPictureIdeas() {
        let r = ScriptImport.read(essay, fileName: "The Chat Box.md")
        #expect(r.sections.map(\.title) == ["Cold open", "Everyone added one"])
        // The film's own title isn't a section; the front matter isn't words.
        #expect(!r.rows.contains { $0.sound.text.contains("stage") || $0.sound.text.contains("Chat Box") })
        #expect(r.rows[0].sound.text == "Open any app you used five years ago. It has a chat box now.")
        #expect(r.rows[0].hint == "Black. The question types on.")
        #expect(r.rows[1].sound.text == "I build these for a living." && r.rows[1].hint == "me at the desk, dark")
        // A picture idea inside a paragraph belongs to the paragraph's first beat, and leaves the words.
        #expect(r.rows[0].sound.text.contains("[") == false)
        #expect(r.rows.allSatisfy { $0.sound.kind == .voice || $0.sound.text.hasPrefix("So here") || $0.sound.text.hasPrefix("Nobody") })
        let turn = r.rows.first { $0.sound.text.hasPrefix("So here") }!
        #expect(turn.sound.kind == .onCamera)
        let named = r.rows.last!
        #expect(named.sound.kind == .onCamera && named.sound.speaker == "SCOTT" && named.sound.text == "Nobody asked for it. Not once.")
        #expect(r.rows.allSatisfy { $0.section != nil })
        // Spoken words at 2.5 a second.
        #expect(r.rows[1].seconds == 2.5)
        #expect(r.words == r.rows.reduce(0) { $0 + $1.sound.text.split(separator: " ").count })
    }

    @Test func aTwoColumnScriptKeepsBothColumns() {
        let text = """
        | Picture | Sound |
        |---|---|
        | Black. A title types on. | Room tone. |
        | Me at the desk, wide. | VO: I build these for a living. |
        | On camera. | SCOTT: Here's what happened. |
        """
        let r = ScriptImport.read(text, fileName: "av.md")
        #expect(r.rows.count == 3)
        #expect(r.rows[1].picture.text == "Me at the desk, wide." && r.rows[1].picture.yours == true)
        #expect(r.rows[1].sound.kind == .voice && r.rows[1].sound.text == "I build these for a living.")
        #expect(r.rows[2].sound.kind == .onCamera && r.rows[2].sound.speaker == "SCOTT")
    }

    @Test func aScreenplayReadsAsScenesDialogueAndAction() {
        let text = """
        Title: Launch
        Author: Someone

        INT. MAYA'S OFFICE - DAY

        Maya sits at the window.

        MAYA
        (quietly)
        So we started with the edit.

        MAYA (V.O.)
        Everyone said, start with the camera.

        CUT TO:
        """
        let r = ScriptImport.read(text, fileName: "launch.fountain")
        #expect(r.sections.map(\.title) == ["INT. MAYA'S OFFICE - DAY"])
        #expect(r.rows.count == 3)
        #expect(r.rows[0].sound.kind == .silence && r.rows[0].picture.text == "Maya sits at the window." && r.rows[0].picture.yours == true)
        #expect(r.rows[1].sound.kind == .onCamera && r.rows[1].sound.speaker == "Maya" && r.rows[1].sound.text == "So we started with the edit.")
        #expect(r.rows[2].sound.kind == .voice && r.rows[2].sound.text == "Everyone said, start with the camera.")
    }

    @Test func whatTheDirectorTypesTheEditorKeepsUnlessANoteAsks() throws {
        let store = try seededStore()
        var s = try store.importScript(essay, fileName: "The Chat Box.md")
        let (one, two) = (s.rows[0].id, s.rows[1].id)
        _ = try store.beginScriptPass()
        s = try store.updateScript(pictures: [PictureInput(rowID: one, text: "Apps opening their chat panels.", size: .medium), PictureInput(rowID: two, text: "Me at the desk from behind.", size: .wide)]).0
        #expect(s.row(one)?.picture.pass == 1 && s.row(two)?.picture.board == .wide)

        _ = try store.editRow(two, picture: "Me at the desk, close. I laugh once.")
        var (after, refused) = try store.updateScript(pictures: [PictureInput(rowID: two, text: "Something else.")])
        #expect(after.row(two)?.picture.text == "Me at the desk, close. I laugh once." && refused.count == 1)
        // The words are the script's: changed only where a note asks.
        (after, refused) = try store.updateScript(sounds: [SoundInput(rowID: one, text: "Different words.")])
        #expect(after.row(one)?.sound.text.hasPrefix("Open any app") == true && refused.count == 1)

        let note = try store.addScriptNote(rowIDs: [two], kind: .picture, text: "Make it my hands.")
        #expect(note.number == 1)
        expectError("no_notes") { _ = try store.turnOverScriptNotes(); _ = try store.turnOverScriptNotes() }
        _ = try store.beginScriptPass()
        (after, refused) = try store.updateScript(pictures: [PictureInput(rowID: two, text: "My hands on the keys.", size: .close)], replies: [note.id: "Row 2 is your hands now."])
        #expect(refused.isEmpty && after.row(two)?.picture.text == "My hands on the keys." && after.row(two)?.picture.pass == 2)
        #expect(after.notes[0].state == .done && after.notes[0].reply == "Row 2 is your hands now.")
        expectError("note_turned_over") { _ = try store.editScriptNote(note.id, text: "No") }
    }

    @Test func aNewDraftKeepsThePictureOfWordsThatDidntChange() throws {
        let store = try seededStore()
        let first = try store.importScript(essay, fileName: "The Chat Box.md")
        _ = try store.updateScript(pictures: [PictureInput(rowID: first.rows[0].id, text: "Apps opening their chat panels.")])
        let note = try store.addScriptNote(rowIDs: [first.rows[1].id], kind: .pace, text: "Faster.")
        let draft = essay.replacingOccurrences(of: "I build these for a living.", with: "I make these for a living.")
        let second = try store.importScript(draft, fileName: "The Chat Box.md")
        #expect(second.rows[0].id == first.rows[0].id && second.rows[0].picture.text == "Apps opening their chat panels.")
        #expect(second.rows[1].sound.text == "I make these for a living." && second.rows[1].picture.isEmpty && second.rows[1].id != first.rows[1].id)
        // A note on words that are gone goes with them.
        #expect(second.notes.first { $0.id == note.id }?.state == .dropped)
        #expect(second.revision > first.revision)
    }

    private let story = """
    # Night walk

    ## Leaving
    Maya locks the studio at midnight. The street is empty and wet. Nobody's out.

    [her breath in the cold]
    She stops on the bridge and calls her dad. He says, "You're up late."

    ## Home
    Her flat is cold.
    """

    /// A story comes in as beats: its part of the story on each, and nothing heard until someone says what.
    @Test func aStoryComesInAsBeatsWithNothingWrittenToSay() throws {
        let store = try seededStore()
        let s = try store.importScript(story, fileName: "Night walk.md", as: .story)
        #expect(s.isStory && s.sections.map(\.title) == ["Leaving", "Home"])
        #expect(s.rows.compactMap(\.story) == ["Maya locks the studio at midnight.", "The street is empty and wet. Nobody's out.", "She stops on the bridge and calls her dad.", "He says, \"You're up late.\"", "Her flat is cold."])
        #expect(s.rows.allSatisfy { $0.sound.text.isEmpty && $0.soundUndecided && $0.picture.isEmpty })
        #expect(s.rows[2].hint == "her breath in the cold" && s.rows[4].section == s.sections[1].id)
        #expect(s.source?.words == 32 && s.rows.allSatisfy { $0.seconds >= 2 })
        // The same file as a script is narration, as before.
        let script = ScriptImport.read(story, fileName: "Night walk.md")
        #expect(script.rows.allSatisfy { $0.story == nil && !$0.sound.text.isEmpty })
    }

    /// A treatment numbers its beats: each is one row as the writer wrote it, timed from its times, and the
    /// rest (the idea, the rules, questions) is the writer's notes, never rows.
    @Test func aTreatmentKeepsItsBeatsAndItsNotes() throws {
        let treatment = """
        *Working title: Porch · 30 seconds · no dialogue*

        ## The idea

        A man fixes a porch light, and the street comes out to watch.

        ## The story

        **1 · Dark · 0:00–0:06.** Night. He climbs the ladder. The bulb is dead.

        **2 · Light · 0:06–0:18.** He screws in a new one. It flickers, then holds. Neighbours' doors open one by one.

        Beat 3: He waves, and they wave back.

        **What it leaves you with:** small fixes are public.

        ## Questions

        * **Whose porch?** Ours, or a friend's?
        * **Music:** none until the light holds?
        """
        let store = try seededStore()
        let s = try store.importScript(treatment, fileName: "Porch.md", as: .story)
        #expect(s.sections.map(\.title) == ["The story"])
        #expect(s.rows.count == 3 && s.rows.allSatisfy { $0.section == s.sections[0].id })
        #expect(s.rows[0].story == "1 · Dark · 0:00–0:06. Night. He climbs the ladder. The bulb is dead.")
        #expect(s.rows[0].seconds == 6 && s.rows[1].seconds == 12 && s.rows[2].seconds >= 2)
        let notes = try #require(s.storyNotes)
        #expect(notes.contains("Working title: Porch") && notes.contains("## The idea") && notes.contains("small fixes are public") && notes.contains("**Whose porch?**"))
        #expect(!notes.contains("He climbs the ladder"))
        // A story without numbered beats is laid out sentence by sentence, as before, with no notes.
        #expect(ScriptImport.story(story, fileName: "Night walk.md").notes == nil)
    }

    /// The Script room shows a beat by its writer's title, without the number and times the row already gives.
    @Test func aBeatIsShownByItsTitle() {
        let lead = ScriptImport.beatLead("1 · Dark · 0:00–0:06. Night. He climbs the ladder.")
        #expect(lead.title == "Dark" && lead.body == "Night. He climbs the ladder.")
        // Only times: no title. One plain phrase is the beat's first sentence, kept.
        #expect(ScriptImport.beatLead("2 · 0:06–0:18. He screws in a new one.") == (nil, "He screws in a new one."))
        #expect(ScriptImport.beatLead("Beat 3: He waves. They wave back.") == (nil, "He waves. They wave back."))
        #expect(ScriptImport.beatLead("Scene 4 — He leaves.") == (nil, "He leaves."))
        #expect(ScriptImport.beatLead("Maya locks the door. 2 · not a lead.") == (nil, "Maya locks the door. 2 · not a lead."))
    }

    /// The editor writes what we hear on a story's beats, never words for anyone; what the director wrote stays.
    @Test func theEditorWritesWhatWeHearInAStory() throws {
        let store = try seededStore()
        let s = try store.importScript(story, fileName: "Night walk.md", as: .story)
        let r = s.rows.map(\.id)
        let (after, refused) = try store.updateScript(pictures: [PictureInput(rowID: r[2], text: "Maya on the bridge, phone to her ear.", size: .medium)], sounds: [
            SoundInput(rowID: r[0], kind: .effect, text: "Keys in the lock.", seconds: 4),
            SoundInput(rowID: r[2], kind: .onCamera, speaker: "Maya", text: "Calling her dad: the hello", ownWords: true, seconds: 5),
            SoundInput(rowID: r[3], kind: .voice, speaker: "Her dad", text: "You're up late.", seconds: 9),
        ])
        #expect(refused.isEmpty)
        #expect(after.rows[0].sound.kind == .effect && after.rows[0].seconds == 4)
        #expect(after.rows[2].sound.ownWords == true && after.rows[2].seconds == 5 && !after.rows[2].hasWrittenWords)
        // Words the story quotes are said as written: their time comes from them.
        #expect(after.rows[3].hasWrittenWords && after.rows[3].seconds == 1.5)
        #expect(after.rows[1].soundUndecided && after.rows[2].line == "Calling her dad: the hello" && after.rows[1].line == "The street is empty and wet. Nobody's out.")

        _ = try store.editRow(r[1], sound: "Rain on parked cars.", soundKind: .effect)
        let (kept, no) = try store.updateScript(sounds: [SoundInput(rowID: r[1], kind: .music, text: "Piano.")])
        #expect(kept.rows[1].sound.text == "Rain on parked cars." && no.count == 1)
        _ = try store.editRow(r[2], ownWords: false)
        #expect(try store.script()?.rows[2].sound.ownWords == nil)

        // A new draft of the story keeps the beats whose part of the story didn't change, and what we hear on them.
        let draft = try store.importScript(story.replacingOccurrences(of: "Her flat is cold.", with: "Her flat is cold and dark."), fileName: "Night walk.md", as: .story)
        #expect(draft.rows[2].id == r[2] && draft.rows[2].picture.text == "Maya on the bridge, phone to her ear." && draft.rows[2].sound.ownWords == nil && draft.rows[2].sound.speaker == "Maya")
        #expect(draft.rows[4].id != r[4] && draft.rows[4].story == "Her flat is cold and dark.")
    }

    @Test func okTheScriptAndItKnowsWhenItMovesOn() throws {
        let store = try seededStore()
        let s = try store.importScript(essay, fileName: "The Chat Box.md")
        #expect(try store.okScript().isOK)
        #expect(try store.script()?.changedSinceOK == false)
        _ = try store.editRow(s.rows[0].id, picture: "Black.")
        #expect(try store.script()?.changedSinceOK == true)
    }

    /// A breakdown of the essay: narration, the desk at night, and screen recordings.
    private func brokenDown(_ store: ProjectStore) throws -> (AVScript, Breakdown) {
        let s = try store.importScript(essay, fileName: "The Chat Box.md")
        let r = s.rows.map(\.id)
        let (b, refused, _) = try store.updateBreakdown(setups: [
            SetupInput(name: "Screen recordings", noCamera: true),
            SetupInput(name: "Desk at night", needs: "After dark, lamp off"),
            SetupInput(name: "Narration", needs: "The good mic"),
        ], shots: [
            ShotInput(setup: "Screen recordings", rowIDs: [r[0]], what: "Apps opening their chat panels.", source: .screen),
            ShotInput(setup: "Desk at night", rowIDs: [r[3]], what: "Close, in profile, lit by the screen.", size: .close, source: .shoot),
            ShotInput(setup: "Desk at night", rowIDs: [r[1]], what: "Wide from behind.", size: .wide, source: .shoot),
            ShotInput(setup: "Narration", rowIDs: Array(r.prefix(5)), what: "The narration, read through.", source: .sound),
        ])
        #expect(refused.isEmpty)
        return (s, b)
    }

    /// The editor can lay out every setup first and fill them a page at a time; empty ones go at the OK.
    @Test func setupsWaitForTheirShotsUntilTheOK() throws {
        let store = try seededStore()
        let s = try store.importScript(essay, fileName: "The Chat Box.md")
        var b = try store.updateBreakdown(setups: [SetupInput(name: "Desk at night"), SetupInput(name: "Kitchen"), SetupInput(name: "Screen recordings", noCamera: true)]).0
        #expect(b.setups.count == 3 && b.shots.isEmpty)
        b = try store.updateBreakdown(shots: [ShotInput(setup: "Desk at night", rowIDs: [s.rows[0].id], what: "Wide from behind.", source: .shoot)]).0
        #expect(b.setups.count == 3 && b.shots.map(\.code) == ["1A"])
        b = try store.okBreakdown()
        #expect(b.setups.map(\.name) == ["Desk at night"])
    }

    @Test func setupsAreNumberedInTheOrderTheyreNeededAndShotsLetteredByRow() throws {
        let store = try seededStore()
        let (_, b) = try brokenDown(store)
        #expect(b.setups.map(\.name) == ["Narration", "Desk at night", "Screen recordings"])
        #expect(b.shots.map(\.code) == ["1A", "2A", "2B", "3A"])
        #expect(b.shot(code: "2A")?.what == "Wide from behind." && b.shot(code: "2B")?.size == .close)
        #expect(b.shot(code: "1A")?.seconds == b.shot(code: "1A").map { s in s.rowIDs.compactMap { try? store.script()?.row($0)?.seconds }.reduce(0, +) })
    }

    @Test func okTheBreakdownAndItsShotsBecomeSlatesInDailies() throws {
        let store = try seededStore()
        let (s, _) = try brokenDown(store)
        let b = try store.okBreakdown()
        let d = try store.dailies()
        #expect(d.scenes.map(\.title) == ["Narration", "Desk at night", "Screen recordings"])
        #expect(d.scenes[1].setups.map(\.code) == ["2A", "2B"] && d.scenes[1].number == 2)
        // After the OK a new shot takes the next letter and nothing else moves.
        let desk = b.setups.first { $0.name == "Desk at night" }!
        let (later, _, _) = try store.updateBreakdown(shots: [ShotInput(setupID: desk.id, rowIDs: [s.rows[0].id], what: "Hands on the keys.", source: .shoot)])
        #expect(later.shots.map(\.code) == ["1A", "2A", "2B", "2C", "3A"])
        #expect(later.shot(code: "2C")?.addedAfterOK == true)
        #expect(try store.dailies().scenes[1].setups.map(\.code) == ["2A", "2B", "2C"])
        let (_, refused, _) = try store.updateBreakdown(shots: [ShotInput(id: later.shot(code: "2A")!.id, setupID: later.setups[2].id)])
        #expect(refused.count == 1)
    }

    /// The words name shots by number. When the shots are numbered again the numbers follow their shots, and a
    /// number that names no shot, or one taken out, comes back for the editor to fix.
    @Test func shotNumbersInTheWordsFollowTheirShots() throws {
        let store = try seededStore()
        let (s, b) = try brokenDown(store)
        let wide = b.shot(code: "2A")!, close = b.shot(code: "2B")!
        _ = try store.updateBreakdown(shots: [ShotInput(id: wide.id, how: "On a tripod in the same spot as 2B. Shoot 4K; it plays 2X slower.")])
        // A shot on the row between them takes 2B, and the close moves to 2C, in the words too.
        let (added, _, toFix) = try store.updateBreakdown(shots: [ShotInput(setup: "Desk at night", rowIDs: [s.rows[2].id], what: "Hands on the keys, as in 9Q.", source: .shoot)])
        let hands = added.shots.first { $0.what.hasPrefix("Hands") }!
        #expect(hands.code == "2B" && added.shot(close.id)?.code == "2C")
        #expect(added.shot(wide.id)?.how == "On a tripod in the same spot as 2C. Shoot 4K; it plays 2X slower.")
        #expect(toFix == ["2B names 9Q, but no shot has that number."])
        // Taking the hands out gives the close 2B again; words that named the hands come back.
        _ = try store.updateBreakdown(shots: [ShotInput(id: hands.id, what: "Hands on the keys."), ShotInput(id: wide.id, why: "Cut with 2B.")])
        let (gone, _, fix) = try store.updateBreakdown(remove: [hands.id])
        #expect(gone.shot(close.id)?.code == "2B")
        #expect(gone.shot(wide.id)?.how == "On a tripod in the same spot as 2B. Shoot 4K; it plays 2X slower.")
        #expect(fix == ["2A names 2B: that shot was taken out, and 2B is another shot now."])
    }

    /// How to shoot it is the editor's until the director changes it; then it's theirs.
    @Test func howToShootItStaysTheDirectorsOnceTheyChangeIt() throws {
        let store = try seededStore()
        let (_, b) = try brokenDown(store)
        let wide = b.shot(code: "2A")!
        var after = try store.updateBreakdown(shots: [ShotInput(id: wide.id, how: "On a tripod behind the chair. Record 10 seconds.", why: "It opens the film.")]).0
        #expect(after.shot(wide.id)?.how == "On a tripod behind the chair. Record 10 seconds." && after.shot(wide.id)?.why == "It opens the film.")
        _ = try store.editShot(wide.id, how: "Handheld, from the door.")
        after = try store.updateBreakdown(shots: [ShotInput(id: wide.id, how: "On a tripod again.")]).0
        #expect(after.shot(wide.id)?.how == "Handheld, from the door." && after.shot(wide.id)?.yours?.contains("how") == true)
    }

    @Test func aSpokenSlateOrAFileNameFilesTheTake() throws {
        #expect(Slate.spoken(["2C,", "take", "1."]) == .init(code: "2C", take: 1))
        #expect(Slate.spoken(["Two", "C", "take", "three"]) == .init(code: "2C", take: 3))
        #expect(Slate.spoken(["Scene", "two", "charlie,", "take", "twenty", "one"]) == .init(code: "2C", take: 21))
        #expect(Slate.spoken(["2C", "T4"]) == .init(code: "2C", take: 4))
        #expect(Slate.spoken(["So", "I", "went", "to", "a", "take", "out", "place"]) == nil)
        #expect(Slate.fileName("2C T1.mov") == .init(code: "2C", take: 1))
        #expect(Slate.fileName("5a_take3.mp4") == .init(code: "5A", take: 3))
        #expect(Slate.fileName("C0012.MP4") == nil && Slate.fileName("1080p export.mov") == nil)

        let store = try seededStore()
        _ = try brokenDown(store)
        _ = try store.okBreakdown()
        let asset = try store.read().assets[0]
        try store.saveTranscript(SourceTranscript(assetID: asset.id, audioTrackID: asset.audio[0].id, words: [
            TranscriptWord(text: "2B,", range: .init(start: .init(seconds: 0.4), duration: .init(seconds: 0.3))),
            TranscriptWord(text: "take", range: .init(start: .init(seconds: 0.8), duration: .init(seconds: 0.2))),
            TranscriptWord(text: "2.", range: .init(start: .init(seconds: 1.1), duration: .init(seconds: 0.2))),
        ]))
        #expect(try store.fileBySlate() == [asset.id: "2B"])
        let dailies = try store.dailies(), take = dailies.takes[asset.id]!
        #expect(take.setupCode == "2B" && take.code == "T2" && !take.isLogged && take.sceneID == dailies.scenes[1].id)
        // Filed once: it isn't filed again.
        #expect(try store.fileBySlate().isEmpty)
    }

    @Test func coverageShowsWhatsInWhatsMissingAndWhatsLeftToMakeOrAdd() throws {
        let store = try seededStore()
        let (_, b0) = try brokenDown(store)
        var b = b0
        b = try store.editShot(b.shot(code: "3A")!.id, source: .have)
        _ = try store.okBreakdown()
        var c = try store.coverage()
        #expect(c[b.shot(code: "2A")!.id] == .planned && c[b.shot(code: "3A")!.id] == .needsFootage)
        // One take of 2A in: 2B, from the same setup, is missing; the narration's setup wasn't shot yet.
        let asset = try store.read().assets[0]
        try store.file(assetID: asset.id, in: b.shot(code: "2A")!, take: 1, breakdown: try store.breakdown()!)
        c = try store.coverage()
        #expect(c[b.shot(code: "2A")!.id] == .got([asset.id]) && c[b.shot(code: "2B")!.id] == .missing && c[b.shot(code: "1A")!.id] == .planned)
        _ = try store.attachFootage(shotID: b.shot(code: "3A")!.id, assetID: asset.id)
        #expect(try store.coverage()[b.shot(code: "3A")!.id]?.isIn == true)
        #expect(try store.breakdown()?.shot(code: "3A")?.haveAssetID == asset.id)
    }

    @Test func theDirectorsShotFieldsAreTheirsUntilANoteAsks() throws {
        let store = try seededStore()
        let (_, b) = try brokenDown(store)
        let wide = b.shot(code: "2A")!
        _ = try store.editShot(wide.id, what: "Wide, from the doorway.")
        var after = try store.updateBreakdown(shots: [ShotInput(id: wide.id, what: "Something else.", size: .medium)]).0
        #expect(after.shot(wide.id)?.what == "Wide, from the doorway." && after.shot(wide.id)?.size == .medium)
        let note = try store.addBreakdownNote(shotIDs: [wide.id], kind: .picture, text: "From behind after all.")
        _ = try store.turnOverBreakdownNotes()
        after = try store.updateBreakdown(shots: [ShotInput(id: wide.id, what: "Wide from behind.")], replies: [note.id: "Back to behind."]).0
        #expect(after.shot(wide.id)?.what == "Wide from behind." && after.notes[0].state == .done)
    }
}
