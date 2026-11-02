import Testing
import Foundation
import DirectionCore
@testable import DirectionApp

/// The prep rooms' one button, their place in the room order, and the editor's job text for them
/// (specs/script.md, specs/breakdown.md).
@MainActor
struct PrepModelTests {
    @Test func theRoomsRunInTheOrderAFilmIsMade() {
        #expect(Room.allCases == [.script, .breakdown, .dailies, .screening, .notes, .changes, .finish])
        #expect(Room.script.shortcut == "1" && Room.dailies.shortcut == "3")
        let m = PrepFixtures.film(room: .script, script: PrepFixtures.script())
        // A film that starts from a script works in its rooms from the start.
        #expect(m.onboardingStep == nil)
        #expect(!m.isEnabled(.breakdown))
        m.script?.okAt = 1
        #expect(m.isEnabled(.breakdown))
    }

    @Test func scriptsOneButtonFollowsWhereItIs() {
        let empty = PrepFixtures.film(room: .script, script: nil)
        // A film without footage starts with Bring footage; one that's past it can still start a script.
        #expect(empty.onboardingStep == .footage)
        empty.onboardingDismissed = true
        #expect(empty.primaryAction?.title == "Bring in a script\u{2026}")
        var s = PrepFixtures.script()
        let m = PrepFixtures.film(room: .script, script: s)
        // Row 8 has no picture yet.
        #expect(m.primaryAction?.title == "OK script" && m.primaryAction?.enabled == false)
        s.rows[7].picture = AVPicture(text: "An empty chat box.", board: .made)
        m.script = s
        #expect(m.primaryAction?.enabled == true)
        s.notes = [PrepNote(number: 1, rowIDs: [s.rows[0].id], text: "Faster.")]
        m.script = s
        #expect(m.primaryAction?.title == "Turn over" && m.primaryAction?.count == "1")
        s.notes[0].state = .done; s.okAt = 1
        m.script = s
        #expect(m.primaryAction?.title == "Open Breakdown")
    }

    @Test func breakdownsOneButtonGoesFromOKToFootageToTheAssembly() {
        let m = PrepFixtures.film(room: .breakdown, script: PrepFixtures.script(), breakdown: PrepFixtures.breakdown(ok: false))
        #expect(m.primaryAction?.title == "OK breakdown" && m.primaryAction?.enabled == true)
        m.breakdown = PrepFixtures.breakdown(ok: true)
        #expect(m.primaryAction?.title == "Bring footage")
        var t = TakeInfo(assetID: "take-1"); t.setupCode = "2A"; t.code = "T1"
        m.dailies.takes["take-1"] = t
        #expect(m.primaryAction?.title == "Assemble from circles" && m.primaryAction?.enabled == false)
        m.dailies.takes["take-1"]?.circled = true
        #expect(m.primaryAction?.enabled == true)
    }

    @Test func theShootListGoesSetupBySetupWithWhatsIn() {
        let m = PrepFixtures.film(room: .breakdown, script: PrepFixtures.script(), breakdown: PrepFixtures.breakdown(ok: true))
        var t = TakeInfo(assetID: "take-1"); t.setupCode = "2A"; t.code = "T1"
        m.dailies.takes["take-1"] = t
        let list = m.shootList
        #expect(list.contains("2  DESK AT NIGHT  \u{2014}  After dark"))
        #expect(list.contains("\u{2713} 2A  Wide from behind.") && list.contains("\u{2610} 2B  Hands on the keyboard."))
        // Made shots and footage you have aren't shot.
        #expect(!list.contains("6A") && !list.contains("TO MAKE"))
    }

    @Test func theEditorsPrepJobsSayWhatThisPassIs() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-prep-job-" + UUID().uuidString + ".direction")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = try ProjectStore.create(at: path, name: "The Chat Box")
        let s = try store.importScript(PrepFixtures.essay, fileName: "The Chat Box.md")
        var v = try EditorJobs.prepValues(.script, store: store)
        #expect(v["task"]?.contains("The director brought in \u{201C}The Chat Box.md\u{201D}") == true && v["notes"] == "None this pass.")
        _ = try store.addScriptNote(rowIDs: [s.rows[2].id, s.rows[3].id, s.rows[4].id], kind: .pace, text: "Too many screens.")
        _ = try store.turnOverScriptNotes()
        v = try EditorJobs.prepValues(.script, store: store)
        #expect(v["notes"]?.contains("Note 1") == true && v["notes"]?.contains("Rows 3\u{2013}5") == true && v["task"]?.contains("turned over 1 note") == true)
        for job in ["script", "breakdown"] {
            let t = EditorJobs.template(job)
            #expect(t?.contains("{{task}}") == true && t?.contains("{{notes}}") == true && t?.contains("{{skill}}") == true, "\(job)")
        }
        _ = try store.okScript()
        v = try EditorJobs.prepValues(.breakdown, store: store)
        #expect(v["task"]?.contains("Break it down into shots, grouped by setup") == true)
        #expect(EditorJobs.rowList([1, 2, 3, 7, 9]) == "1\u{2013}3, 7 and 9")
    }
}
