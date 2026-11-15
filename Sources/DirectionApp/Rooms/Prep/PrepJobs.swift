import Foundation
import DirectionCore

/// The job text for the editor's prep passes (specs/script.md, specs/breakdown.md): what to do this pass,
/// and the director's notes in their words.
extension EditorJobs {
    static func prepValues(_ job: EditorJob, store: ProjectStore) throws -> [String: String] {
        let script = try store.script() ?? AVScript()
        // A film started from its footage brings its script in after: the pictures come from what's there first.
        // Only before a breakdown is OK'd: footage shot from an OK'd breakdown is that plan's, not a starting point.
        let takes = try store.breakdown()?.isOK == true ? 0 : try store.read().footage(film: store.url).count
        switch job {
        case .script:
            let story = script.isStory
            let empty = script.rows.enumerated().filter { $0.element.picture.isEmpty || (story && $0.element.soundUndecided) }.map { $0.offset + 1 }
            var task: [String] = []
            if !empty.isEmpty {
                let from = script.source.map { "\u{201C}\($0.fileName)\u{201D}, \($0.words) words" } ?? (story ? "a story" : "a script")
                task.append(empty.count == script.rows.count
                    ? story
                        ? "The director brought in a story, \(from). Direction laid it out as \(count(script.rows.count, "beat")). Write what we see and what we hear under every one."
                        : "The director brought in \(from): \(script.rows.count) rows, about \(Timecode.duration(script.seconds)) read aloud. Write what we see under every row."
                    : story ? "Write what we see and what we hear under the rows that don\u{2019}t have them yet: \(rowList(empty))." : "Write what we see under the rows that have no picture yet: \(rowList(empty)).")
            }
            if !script.turnedOver.isEmpty { task.append("The director turned over \(count(script.turnedOver.count, "note")) on the script. Answer each one: change the rows it names, then reply.") }
            var v = ["task": task.isEmpty ? (story ? "Read the A/V script and check every beat has a picture and a sound that fit the story and the style." : "Read the script and check every row has a picture that fits its words and the style.") : task.joined(separator: " "),
                     "notes": notes(script.turnedOver) { n in (n.rowIDs ?? []).compactMap { script.number(of: $0) }.isEmpty ? "" : "Rows \(rowList((n.rowIDs ?? []).compactMap { script.number(of: $0) }))" }]
            v["footage"] = takes == 0 ? "" : """
            The film already has its footage: \(count(takes, "take")), logged in Dailies. Before you write, read what's there with `direction_dailies` (and `direction_search_footage` for a moment you need). Where a row's picture can be a moment of a take, write it from that take, naming it ("Take 3: her hands stop on the keys"); write a new picture only where nothing there fits. The breakdown marks the ones you named as footage the director has.


            """
            if story {
                v["columns"] = "This film starts from a story, not a script: nobody\u{2019}s words are written. Direction laid the story out as beats, a row each, with the part of the story it came from (`story`). Both columns are yours to write: the picture, what the viewer sees, never how to shoot it; and the sound, what we hear. Later the breakdown turns them into shots, so write what someone could film, record on a screen, or make."
                v["write"] = "pictures and sounds"; v["whole"] = "story"; v["done"] = "a picture and a sound"
                v["theirs"] = "So is a sound they wrote. The story is the writer\u{2019}s: tell it as it is, in order."
                v["story"] = """
                5. What we hear, on every row, in the same `direction_script_update`: `sounds: [{rowID, kind, speaker?, text, ownWords?, seconds}]`. Someone talking in shot is `onCamera` with the speaker; talk recorded on its own (an interview, a narration) is `voice`. Never write words for anyone to say: the text says who talks and what about ("Maya, on why she nearly quit") with `ownWords: true`, and they find the words on the day. Words the story quotes are the writer\u{2019}s: use them as written, without `ownWords`. Otherwise it\u{2019}s `effect` with what we hear ("The lights clunk on, one by one."), `music` or `silence`. Give every row `seconds`: how long the beat plays on screen; where the story gives a beat its times, keep them.
                6. One row is one beat. When a beat needs two pictures, write both in order ("Her hand on the switch. Then the room, lit."); the breakdown makes them two shots.

                """
                if let notes = script.storyNotes {
                    v["story"]! += """
                    7. The writer\u{2019}s notes are below: what they wrote around the beats (the idea, the rules of the film, questions for the director). They aren\u{2019}t rows. Follow them in every picture and sound, and ask on a row when a question there is the director\u{2019}s to answer.

                    ## The writer\u{2019}s notes
                    \(notes)


                    """
                }
            } else {
                v["columns"] = "The A/V script has two columns. The sound is the script\u{2019}s own words; the picture is yours to write: what the viewer sees under each line, never how to shoot it. Later the breakdown turns your pictures into shots, so write pictures someone could film, record on a screen, or make."
                v["write"] = "pictures"; v["whole"] = "script"; v["done"] = "a picture"
                v["theirs"] = "The words are the script\u{2019}s: change them only where a note asks."
                v["story"] = ""
            }
            return v
        case .voiceOver:
            let ask = script.voiceOver ?? VoiceOverAsk(ask: "")
            var task: [String] = []
            if script.rows.isEmpty { task.append("The director asked for a voice-over\(ask.cutName.map { " for \($0)" } ?? ""): words they\u{2019}ll record later and lay over \(ask.cutName == nil ? "the film" : "the cut"). Watch it, then write it, line by line, timed to the picture.") }
            if !script.turnedOver.isEmpty { task.append("The director turned over \(count(script.turnedOver.count, "note")) on the voice-over. Answer each one: change the lines it names, then reply.") }
            let words = ask.ask.trimmingCharacters(in: .whitespacesAndNewlines)
            let quoted = words.isEmpty ? "" : words.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
            let watch: String
            if let name = ask.cutName, let seconds = ask.cutSeconds {
                let at = ask.cutRevision.map { "`revision: \($0)`" } ?? "its revision"
                watch = "It\u{2019}s written to \(name), \(Timecode.duration(seconds)) long. Read that cut, not the edit as it is now: pass \(at) to `direction_timeline`, `direction_frame`, `direction_watch` and `direction_transcript`. Watch it before you write: its outline, then the picture (`direction_frame` with `times` across it, `direction_watch` where a moment matters), and `direction_transcript` for anyone already talking."
            } else {
                watch = "There\u{2019}s no cut to write to yet: write it from the footage (`direction_dailies`, `direction_search_footage`), each line\u{2019}s `at` counted from the start as the footage would play."
            }
            return ["task": task.isEmpty ? "Read the voice-over against the cut and check every line fits its picture and its time." : task.joined(separator: " "),
                    "ask": quoted.isEmpty ? "> (Nothing more than a voice-over for the film.)" : quoted, "watch": watch,
                    "budget": ask.wordsThatFit.map { "That\u{2019}s about \($0) words for the whole cut, with room for the picture to breathe." } ?? "",
                    "notes": notes(script.turnedOver) { n in (n.rowIDs ?? []).compactMap { script.number(of: $0) }.isEmpty ? "" : "Lines \(rowList((n.rowIDs ?? []).compactMap { script.number(of: $0) }))" }]
        case .breakdown:
            let b = try store.breakdown()
            var task: [String] = []
            if b?.shots.isEmpty ?? true {
                task.append("The director OK\u{2019}d the script: \(script.rows.count) rows, about \(Timecode.duration(script.seconds)). Break it down into shots, grouped by setup.")
            } else if let b, script.revision > (b.scriptRevision ?? 0) {
                task.append("The script changed since the breakdown was made. Bring the breakdown up to date: shots for rows that are new or whose picture changed, and out with shots whose rows are gone.\(b.isOK ? " It\u{2019}s OK\u{2019}d, so numbers stay as they are; new shots take the next letter." : "")")
            }
            if let b, !b.turnedOver.isEmpty { task.append("The director turned over \(count(b.turnedOver.count, "note")) on the breakdown. Answer each one: change the shots it names, then reply.") }
            return ["task": task.isEmpty ? "Read the breakdown and check every row has a shot." : task.joined(separator: " "),
                    "footage": takes == 0 ? "" : "The film already has its footage (\(count(takes, "take")) in Dailies). A picture the script wrote from a take (\u{201C}Take 3: …\u{201D}) is a shot with source `have`, in a setup with `noCamera`; check it against `direction_dailies`. Only what the footage doesn\u{2019}t cover needs shooting or making.\n\n",
                    "notes": notes(b?.turnedOver ?? []) { n in (n.shotIDs ?? []).compactMap { b?.shot($0)?.code }.joined(separator: ", ") }]
        default:
            return [:]
        }
    }

    private static func notes(_ notes: [PrepNote], anchor: (PrepNote) -> String) -> String {
        guard !notes.isEmpty else { return "None this pass." }
        return notes.map { n in
            let on = anchor(n)
            return "- Note \(n.number) (id \(n.id))\(on.isEmpty ? "" : ", \(on)")\(n.kind.map { ", \($0.label)" } ?? ""): \u{201C}\(n.text)\u{201D}"
        }.joined(separator: "\n")
    }

    /// "1–3, 7 and 9".
    static func rowList(_ numbers: [Int]) -> String {
        var runs: [String] = [], i = 0
        let n = numbers.sorted()
        while i < n.count {
            var j = i
            while j + 1 < n.count, n[j + 1] == n[j] + 1 { j += 1 }
            runs.append(j > i ? "\(n[i])\u{2013}\(n[j])" : "\(n[i])"); i = j + 1
        }
        return runs.count > 1 ? runs.dropLast().joined(separator: ", ") + " and " + runs.last! : runs.first ?? ""
    }

    private static func count(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }

    /// What the director answered on rows or shots since the run asked, for the editor's next turn.
    static func prepAnswers(_ job: EditorJob, script: AVScript?, breakdown: Breakdown?, since: Double) -> [String] {
        func said(_ q: PrepQuestion) -> String {
            let choice = q.answer.flatMap { id in q.choices.first { $0.id == id }?.label }
            return "\u{201C}\(q.text)\u{201D} " + [choice.map { "I chose \u{201C}\($0)\u{201D}." }, q.answerText.map { "I said: \u{201C}\($0)\u{201D}" }].compactMap { $0 }.joined(separator: " ")
        }
        switch job {
        case .script, .voiceOver:
            return (script?.rows ?? []).enumerated().compactMap { i, r in r.question.flatMap { q in (q.answeredAt ?? 0) > since ? "You asked about \(job == .voiceOver ? "line" : "row") \(i + 1): " + said(q) : nil } }
        case .breakdown:
            return (breakdown?.shots ?? []).compactMap { s in s.question.flatMap { q in (q.answeredAt ?? 0) > since ? "You asked about \(s.code): " + said(q) : nil } }
        default: return []
        }
    }
}
