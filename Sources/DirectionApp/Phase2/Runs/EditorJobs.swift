import Foundation
import DirectionCore
import DirectionTools

/// The job text Direction writes for each run, from the versioned templates in
/// Resources/Editor/jobs (specs/editor.md › The job text), and the working folder it runs in.
enum EditorJobs {
    static let templateNames = ["log-footage", "assemble", "turnover", "continue", "finish", "style", "technique", "editor-role"]

    static func templateName(_ job: EditorJob) -> String {
        switch job { case .logFootage: "log-footage"; case .assemble: "assemble"; case .turnover: "turnover"; case .finish: "finish"; case .style: "style"; case .technique: "technique" }
    }

    /// A template's text. SwiftPM flattens processed resources, so look both ways.
    static func template(_ name: String) -> String? {
        let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Editor/jobs") ?? Bundle.module.url(forResource: name, withExtension: "md")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// Replaces every {{key}}; the version comment line is dropped.
    static func fill(_ template: String, _ values: [String: String]) -> String {
        var out = template.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("<!-- direction-job") }.joined(separator: "\n")
        for (k, v) in values { out = out.replacingOccurrences(of: "{{\(k)}}", with: v) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static var role: String { fill(template("editor-role") ?? "", [:]) }
    static func skillPath(_ job: EditorJob) -> String { ".claude/skills/\(job.skill)/SKILL.md" }

    // MARK: Filling

    /// The first invocation's text for a run.
    static func text(for run: EditorRun, store: ProjectStore) throws -> String {
        let p = try store.read(), brief = try store.brief(), state = try store.directingState(), dailies = try store.dailies()
        let applied = try store.appliedStyle()
        var v = common(run.job, film: p.name, brief: brief, state: state, applied: applied, studied: { ReferenceVideo.study($0, film: store.url) })
        switch run.job {
        case .logFootage:
            let footage = p.footage(film: store.url)
            let logged = footage.filter { dailies.takes[$0.id] != nil }.count
            let batch = (run.assetIDs ?? footage.filter { dailies.takes[$0.id] == nil }.map(\.id)).compactMap { id in p.assets.first { $0.id == id } }
            let others = footage.count - logged - batch.count
            v["footage"] = "This run logs \(batch.count == 1 ? "1 take" : "\(batch.count) takes"), listed below. The film has \(footage.count); \(logged) \(logged == 1 ? "is" : "are") logged already\(others > 0 ? " and \(others) more come in later runs" : ""). Log only the takes listed here."
            v["takes"] = LoggingDigest.takes(batch, store: store, dailies: dailies)
            v["scenes"] = LoggingDigest.scenes(dailies)
        case .assemble, .turnover:
            guard let t = try run.turnoverID.map({ try store.turnover($0) }) else { throw DirectionError("turnover_not_found", "This run has no turnover.") }
            let cuts = try store.cuts(), notes = try store.notes()
            v["turnoverID"] = t.id; v["turnoverNumber"] = String(t.number)
            v["latitude"] = "\(t.latitude.label). \(t.latitude.detail)"
            v["cutName"] = t.kind == "assembly" || cuts.isEmpty ? "the assembly" : "Cut \(cuts.count + 1)"
            v["baseCut"] = t.baseCutID.flatMap { id in cuts.first { $0.id == id }?.name } ?? "the current cut"
            v["noteCount"] = t.noteIDs.count == 1 ? "1 note" : "\(t.noteIDs.count) notes"
            v["circles"] = "The director circled \(dailies.takes.values.filter(\.circled).count) takes."
            v["sync"] = syncRules(dailies, assets: p.assets, layout: try store.directingState().layout, styleLayouts: applied.layouts)
            let included = t.noteIDs.compactMap { id in notes.first { $0.id == id } }.sorted { ($0.number ?? 0) < ($1.number ?? 0) }
            let library = LibraryCatalog.entries(techniques: TechniqueLibrary.list(in: SharedSettings.techniquesFolder))
            v["notes"] = included.map { noteLine($0, library: library) }.joined(separator: "\n")
            v["waitForOK"] = t.waitForOK
                ? "The director wants to OK the read-back before you cut. Post it, then end your turn with finished: false; Direction continues this session when they approve."
                : "The director doesn\u{2019}t need to OK the read-back. Post it, then start cutting."
        case .finish:
            let items = state.finishing ?? FinishingItem.defaults
            v["items"] = items.map { "- \($0.title) (\($0.id)): \($0.detail) By \($0.by.joined(separator: " and ")). Now \($0.state)." }.joined(separator: "\n")
            v["lockedCut"] = state.pictureLockedCutID.flatMap { id in (try? store.cuts())?.first { $0.id == id }?.name } ?? "the latest cut"
            let lufs = UserDefaults.standard.object(forKey: "loudnessTarget") as? Double ?? -14
            v["loudness"] = "\(Int(lufs)) LUFS"
            v["ducking"] = ducking(UserDefaults.standard.object(forKey: "musicDucking") as? Double ?? 6)
            if let credits = state.credits, !credits.isEmpty {
                v["credits"] = "The director wrote the credits (a role, then its names, a line each; a blank line between credits):\n\n" + credits.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
                    + "\n\nRoll them at the end: copy the Credits roll example (`direction_graphic_examples` with name `credits-roll`) into `Graphics/credits/`, put these words in its credits field exactly as written, check it with `direction_graphic` (note `unasked`), then `placeGraphic` it at the cut\u{2019}s length, after the last shot, where it plays on black. Add where it plays to the titles item\u{2019}s detail."
            } else {
                v["credits"] = "The director hasn\u{2019}t written credits yet; titles and credits are theirs. Leave that item for them."
            }
            let licenses = state.licenses ?? []
            v["licenses"] = licenses.isEmpty ? "No licenses are on file yet." : "Licenses on file in the film: " + licenses.map { $0.path }.joined(separator: ", ") + "."
        case .style:
            v["request"] = run.request.map { $0.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n") } ?? "> Make a style from this film."
            let cuts = try store.cuts()
            v["source"] = run.fromFilm == true && !cuts.isEmpty
                ? "Learn it from this film as well: watch \(cuts.last!.name) (`direction_timeline`, `direction_watch`), measure how it's cut, and keep what makes it this director's."
                : "Make it from their words and whatever they point you to. Don't take it from this film's cut."
            if let studies = run.studies, !studies.isEmpty { v["source"] = videos(studies, editor: store.url.appendingPathComponent("Editor")) + (run.fromFilm == true ? "\n\n" + v["source"]! : "") }
            v["stylesFolder"] = SharedSettings.stylesFolder.path
        case .technique:
            v["request"] = run.request.map { $0.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n") } ?? "> Learn the technique this video teaches."
            let folder = URL(fileURLWithPath: run.learnFolder ?? store.url.appendingPathComponent("Editor/Learn").path)
            v["video"] = run.learnVideo ?? folder.appendingPathComponent("video.mp4").path
            v["packet"] = folder.path
            let info = (try? Data(contentsOf: folder.appendingPathComponent("video.info.json"))).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            v["videoSource"] = info.map { i in "It\u{2019}s \u{201C}\(i["title"].string ?? "untitled")\u{201D} by \(i["channel"].string ?? i["uploader"].string ?? "someone"), \(i["webpage_url"].string ?? ""). Its description is in `video.info.json`." } ?? "The director gave you the file."
            v["techniquesFolder"] = SharedSettings.techniquesFolder.path
        }
        return fill(template(templateName(run.job)) ?? "", v)
    }

    /// The videos a style is learned from (styles.md › From a video), each studied in its own folder.
    static func videos(_ studies: [String], editor: URL) -> String {
        let base = editor.standardizedFileURL.path + "/"
        let rows: [String] = studies.map { path in
            let folder = URL(fileURLWithPath: path), name = folder.standardizedFileURL.path.hasPrefix(base) ? String(folder.standardizedFileURL.path.dropFirst(base.count)) : path
            guard let s = VideoStudy.read(in: folder) else { return "- `\(name)/`" }
            let video = (try? FileManager.default.contentsOfDirectory(atPath: path))?.first { $0.hasPrefix("video.") }.map { "`\(name)/\($0)`" } ?? "not kept"
            return "- \u{201C}\(s.title)\u{201D}\(s.by.map { " by \($0)" } ?? "")\(s.link.map { " (\($0))" } ?? ""): `\(name)/`. \(s.summary). The video: \(video)."
        }
        let names = studies.map { path -> String in
            let p = URL(fileURLWithPath: path).standardizedFileURL.path
            return "\"" + (p.hasPrefix(base) ? String(p.dropFirst(base.count)) : path) + "\""
        }
        return """
        Learn it from \(studies.count == 1 ? "this video" : "these videos") the director likes. Direction has studied each in its own folder: `study.md` is what it measured (pace, words, sound, framing, captions, and every shot), `transcript.txt` the words with their times, and `sheet-N.jpg` a frame every two seconds. Look at any moment up close with `direction_study_frames`.
        \(rows.joined(separator: "\n"))

        Follow \u{201C}From a video\u{201D} in the skill. Save with `studies: [\(names.joined(separator: ", "))]` so the style keeps where it came from and Direction\u{2019}s numbers. The videos are removed once the style is saved, so take every still you want to keep first.
        """
    }

    /// The film's style and the house style's rules, for the brief (styles.md › In a film): the house rules
    /// in full, since they're few and every film follows them; the style by name, read with direction_style.
    static func styleLines(_ applied: AppliedStyle) -> [String] {
        var b: [String] = []
        if let style = applied.style {
            let n = style.rules.count, layouts = style.layouts.compactMap(\.name), transitions = style.transitions.map(\.name)
            b.append("- Style: \(style.name)\(style.summary.isEmpty ? "" : ". \(style.summary)") It has \(n) rule\(n == 1 ? "" : "s")\(layouts.isEmpty ? "" : ", layouts \(layouts.joined(separator: ", "))")\(transitions.isEmpty ? "" : ", transitions \(transitions.joined(separator: ", "))") and its moves. Read it with `direction_style` before you cut, and follow it wherever the brief and the notes leave a choice open. Use its layouts, transitions and moves by name; Direction does the rest.")
        }
        let house = applied.house.rules
        if !house.isEmpty {
            b.append("- House rules, for every film\(applied.style.map { " (\($0.name) wins where it says otherwise)" } ?? ""):")
            b.append(contentsOf: house.map { "  - \($0.text)" })
        }
        return b
    }

    /// How to cut takes in sync, with the film's groups, or nothing when it has none
    /// (footage-index.md › Sync).
    static func syncRules(_ dailies: Dailies, assets: [MediaAsset], layout: FrameLayout? = nil, styleLayouts: [FrameLayout] = []) -> String {
        let groups = dailies.syncGroups ?? []
        guard !groups.isEmpty else { return "" }
        func label(_ id: String) -> String {
            let t = dailies.take(id), code = [t.setupCode, t.code].compactMap { $0 }.joined(separator: " ")
            return code.isEmpty ? (assets.first { $0.id == id }?.name ?? id) : code
        }
        let list = groups.map { g in
            "- " + g.takes.map { t in label(t.assetID) + (t.assetID == g.soundAssetID ? " (its sound)" : "") + (dailies.take(t.assetID).circled ? ", circled" : "") }.joined(separator: " \u{00B7} ")
        }.joined(separator: "\n")
        return """
        ## Takes in sync
        These recorded the same moment, matched by their sound. Each group is one performance, seen from more than one angle.
        \(list)

        - A circle on any take in a group asks for that moment. Put one angle on V1, never two angles end to end.
        - Bring the other angles in over it with `cutaway` without `sourceRange` (give `at` and `seconds`): it plays the same moment, and Direction keeps it lined up as you edit.
        - The cut uses the group's sound take. If the angle on V1 isn't it, `syncSound` that clip so the sound take plays under it.
        - A camera and a screen recording in sync share the frame with `layout` (\(layoutChoice(layout, styleLayouts))). Direction frames the camera on the face and keeps both in sync. Never build a corner camera by hand with cutaways, transforms or shaders, even where a rule describes one: use the layout. Lay out the whole cut with it. Zoom, blur and freeze the screen inside a layout as the style asks; changing the layout keeps them. A layout the director set in the app is theirs.
        """
    }

    /// Which layout the editor starts from: the director's, else the style's by name, else the standard.
    static func layoutChoice(_ layout: FrameLayout?, _ styleLayouts: [FrameLayout]) -> String {
        if let layout { return "the director chose \(layout.label) for this film" }
        let named = styleLayouts.filter { $0.name != nil }
        if !named.isEmpty { return "use the style\u{2019}s by name: " + named.map { "\($0.name!) (\($0.plainLabel))" }.joined(separator: ", ") + "; its rules say when" }
        return "Screen and you, bottom right, unless the director chooses another; a scene that\u{2019}s only talk can be You"
    }

    /// A continuation of the same session: an answer, an approval, Resume or Try again.
    static func continuation(_ answer: String, job: EditorJob) -> String {
        let what: String = switch job { case .logFootage: "logging the footage"; case .assemble: "the assembly"; case .turnover: "the turnover"; case .finish: "finishing"; case .style: "the style"; case .technique: "the technique" }
        return fill(template("continue") ?? "{{answer}}", ["answer": answer, "skill": job.skill, "skillPath": skillPath(job), "job": what])
    }

    private static func common(_ job: EditorJob, film: String, brief: Brief, state: DirectingState, applied: AppliedStyle, studied: (BriefReference) -> VideoStudy? = { _ in nil }) -> [String: String] {
        var b: [String] = []
        if !brief.logline.isEmpty { b.append("- In one sentence: \(brief.logline)") }
        if !brief.feeling.isEmpty { b.append("- How it should feel: \(brief.feeling)") }
        if let lo = brief.lengthMin, let hi = brief.lengthMax { b.append("- Length: \(minutes(lo))\u{2013}\(minutes(hi))") }
        if let a = brief.audience, !a.isEmpty { b.append("- Audience: \(a)") }
        for k in brief.mustKeep { b.append("- Must keep: \(k)") }
        for r in brief.references {
            // A video the director gave as inspiration, studied by Direction (styles.md › In the brief).
            let study = studied(r).map { " Direction studied it: \($0.summary). What it measured, its words and contact sheets are in `References/\(r.id)/` (study.md first)." } ?? ""
            b.append("- Reference: \(r.title). \(r.why)\(study)")
        }
        if let a = brief.avoid, !a.isEmpty { b.append("- Avoid: \(a)") }
        // "@Name" in the brief names something in the library.
        let named = LibraryCatalog.mentions(in: [brief.logline, brief.feeling, brief.avoid ?? ""].joined(separator: "\n"), entries: LibraryCatalog.entries(techniques: TechniqueLibrary.list(in: SharedSettings.techniquesFolder)))
        if !named.isEmpty { b.append("- Named in the brief: \(LibraryCatalog.explain(named))") }
        b.append(contentsOf: styleLines(applied))
        let prefs = state.preferences ?? EditorPreferences()
        let order = prefs.conflictOrder.map(\.label).joined(separator: " \u{203A} ")
        return [
            "film": film, "skill": job.skill, "skillPath": skillPath(job),
            "brief": b.isEmpty ? "No brief yet. Read `direction_brief` in case it\u{2019}s been written since." : b.joined(separator: "\n"),
            "latitude": "\(state.latitude.label). \(state.latitude.detail)",
            "preferences": [
                "- Cut Feeling notes two ways: \(prefs.twoWaysForFeeling ? "yes" : "no")",
                "- Ask before guessing: \(prefs.askBeforeGuessing ? "yes" : "no")",
                "- When notes conflict: \(order)",
                "- Handles: \(Int(prefs.handleSeconds)) s",
                "- Music under dialogue: \(ducking(prefs.musicDuckDB ?? 6))",
            ].joined(separator: "\n"),
        ]
    }
    /// Settings › Cutting › Music under dialogue, the default a note can override.
    static func ducking(_ db: Double) -> String { db > 0 ? "duck it \(Int(db)) dB (`duck`) where a note doesn\u{2019}t say otherwise" : "don\u{2019}t duck it unless a note asks" }
    private static func minutes(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    /// "- Note 3 (Picture, at 01:12:08): Tighter on her. The sky is winning."
    private static func noteLine(_ c: ReviewComment, library: [LibraryEntry] = []) -> String {
        var anchor = "the whole cut"
        if let r = c.range { anchor = EditorActivityLog.timecode(r.start.seconds, 24) + "\u{2013}" + EditorActivityLog.timecode(r.end.seconds, 24) }
        else if let t = c.time { anchor = "at " + EditorActivityLog.timecode(t.seconds, 24) }
        else if let line = c.scriptAction?.lineLabel { anchor = line }
        let about = [c.kind?.label, anchor].compactMap { $0 }.joined(separator: ", ")
        let named = LibraryCatalog.mentions(in: c.text, entries: library)
        return "- Note \(c.number.map(String.init) ?? "\u{2013}") (\(about)): \(c.text)" + (named.isEmpty ? "" : "\n  (\(LibraryCatalog.explain(named)))")
    }

    // MARK: The working folder

    /// `<film>.direction/Editor/`: everything the editor writes, and the skill it follows.
    static func prepareFolder(film: URL, job: EditorJob) throws -> URL {
        let fm = FileManager.default, folder = film.appendingPathComponent("Editor")
        for sub in ["Graphics", "Looks", "Effects", "Transitions", "Techniques", ".direction"] { try fm.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true) }
        // Direction writes no settings here. Any it finds came with a film someone shared, or from an editor,
        // and a hook in one would run as you when the editor starts, so they go to the Trash first.
        for planted in [".claude/settings.json", ".claude/settings.local.json", ".codex"] {
            let url = folder.appendingPathComponent(planted)
            guard fm.fileExists(atPath: url.path) else { continue }
            DirectionLog.warning("Moved \(planted) out of the film\u{2019}s editor folder before starting the editor", "editor")
            if (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil { try fm.removeItem(at: url) }
        }
        let notes = folder.appendingPathComponent("NOTES.md")
        if !fm.fileExists(atPath: notes.path) { try Data("# Notes between runs\n\nWhat I\u{2019}d want to know next time I pick up this film.\n".utf8).write(to: notes) }
        // The job names its own skill; the others (make-shot, make-graphic, propose-look…) are there for it to follow too.
        if let skills = skillsFolder(), let names = try? fm.contentsOfDirectory(atPath: skills.path) {
            for name in names {
                guard let text = try? Data(contentsOf: skills.appendingPathComponent(name).appendingPathComponent("SKILL.md")) else { continue }
                let target = folder.appendingPathComponent(".claude/skills/\(name)/SKILL.md")
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: target, options: .atomic)
            }
        }
        return folder
    }

    /// The skills that ship with Direction: in the app bundle, or the checkout this build came from.
    static func skillsFolder() -> URL? {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Skills"), fm.fileExists(atPath: r.path) { return r }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let s = dir.appendingPathComponent("plugins/direction/skills")
            if fm.fileExists(atPath: s.path) { return s }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// The `direction` helper the program connects to: in the bundle, beside a development build, or installed.
    static var helperPath: String? {
        let fm = FileManager.default
        var candidates: [String] = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/direction").path]
        if let exe = Bundle.main.executableURL { candidates.append(exe.deletingLastPathComponent().appendingPathComponent("direction").path) }
        candidates.append(NSHomeDirectory() + "/.local/bin/direction")
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
}

/// What Direction found for a batch of takes, written into the logging job so the editor logs from
/// it rather than fetching each part with a tool call (footage-index.md › Logging in batches).
enum LoggingDigest {
    /// Words per take before the rest is left to `direction_transcript`.
    static let wordsPerTake = 1_200
    /// Words of text on screen per take: enough to say what a screen recording shows.
    static let screenWordsPerTake = 40

    static func takes(_ assets: [MediaAsset], store: ProjectStore, dailies: Dailies) -> String {
        let transcripts = (try? store.transcripts()) ?? []
        return assets.map { take($0, store: store, dailies: dailies, transcripts: transcripts) }.joined(separator: "\n\n")
    }

    static func take(_ a: MediaAsset, store: ProjectStore, dailies: Dailies, transcripts: [SourceTranscript]) -> String {
        var out: [String] = []
        let picture = a.video.first.map { "\($0.width)\u{00D7}\($0.height)" } ?? (a.isImage ? "still" : "sound only")
        out.append("### \(a.name) \u{00B7} \(a.id) \u{00B7} \(clock(a.duration.seconds)) \u{00B7} \(picture)\(a.audio.isEmpty ? " \u{00B7} no sound" : "")")
        if let folder = dailies.takes[a.id]?.folder, let t = dailies.takes[a.id], let scene = dailies.scene(for: a.id) {
            let setup = t.setupCode.map { code in " \u{00B7} setup \(code)" + (scene.setups.first { $0.code == code }.map { $0.description.isEmpty ? "" : " \($0.description)" } ?? "") } ?? ""
            out.append("Filed by the director in \u{201C}\(folder)\u{201D}: scene \(scene.number) \(scene.title)\(setup)\(t.code.map { " \u{00B7} take \($0)" } ?? "").")
        }
        if let g = dailies.syncGroup(for: a.id) {
            let others = g.takes.filter { $0.assetID != a.id }.map { t in (try? store.read().asset(t.assetID).name) ?? t.assetID }
            out.append("In sync with \(others.joined(separator: ", ")) (matched by sound)\(g.soundAssetID == a.id ? "; the cut uses this take\u{2019}s sound" : "").")
        }
        let shots = (try? store.shots(assetID: a.id)) ?? []
        if !shots.isEmpty {
            out.append("Shots:")
            for s in shots {
                guard let l = s.look else { out.append("\(s.number). \(clock(s.start))\u{2013}\(clock(s.end)) (not described)"); continue }
                let kind = [l.size, l.movement].compactMap { $0 }.joined(separator: ", ")
                let extra = [l.people.isEmpty ? nil : "people: " + l.people.joined(separator: "; "), l.setting.map { "setting: \($0)" }, l.flags.isEmpty ? nil : "flags: " + l.flags.joined(separator: ", ")].compactMap { $0 }
                out.append("\(s.number). \(clock(s.start))\u{2013}\(clock(s.end))\(kind.isEmpty ? "" : " \u{00B7} \(kind)") \u{00B7} \(l.description)\(extra.isEmpty ? "" : " (" + extra.joined(separator: "; ") + ")")")
            }
        }
        let screen = (try? store.screenText(assetID: a.id)) ?? []
        if !screen.isEmpty {
            out.append("On screen: \(ScreenText.gist(screen, words: screenWordsPerTake))\(screen.count > 1 ? " (\(screen.count) stretches over time: direction_screen_text with assetID)" : "")")
        }
        let sounds = ((try? store.sounds(assetID: a.id)) ?? []).filter { $0.kind != .silence && $0.end - $0.start >= 2 }
        if !sounds.isEmpty { out.append("Sounds: " + sounds.prefix(12).map { "\($0.kind.rawValue) \(clock($0.start))\u{2013}\(clock($0.end))" }.joined(separator: ", ")) }
        if let t = transcripts.filter({ $0.assetID == a.id }).max(by: { ($0.selectedAt ?? 0) < ($1.selectedAt ?? 0) }), !t.words.isEmpty {
            let text = t.words.prefix(wordsPerTake).map(\.text).joined(separator: " ")
            let more = t.words.count - wordsPerTake
            out.append("Words (\(t.words.count)): \(text)\(more > 0 ? " \u{2026} (\(more) more: direction_transcript with assetID and offset \(wordsPerTake))" : "")")
        } else if !a.audio.isEmpty {
            out.append("Words: none transcribed.")
        }
        return out.joined(separator: "\n")
    }

    /// The scenes logged so far, so a later batch adds to them.
    static func scenes(_ d: Dailies) -> String {
        guard !d.scenes.isEmpty else { return "None yet. You start them." }
        return d.scenes.sorted { $0.number < $1.number }.map { s in
            let setups = s.setups.map { "\($0.code) \($0.description)" }.joined(separator: "; ")
            return "- \(s.number) \(s.title) (\(s.id))\(s.folder.map { ", the director\u{2019}s folder \u{201C}\($0)\u{201D}" } ?? "")\(setups.isEmpty ? "" : ": " + setups)"
        }.joined(separator: "\n")
    }

    static func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}
