import Foundation
import DirectionCore

/// Turns each of the editor's tool calls into an Activity row (specs/editor.md › Tool call → Activity).
/// Tools other phase-2 areas add are handled by name, so their calls read as verbs too.
public enum EditorActivityLog {
    /// Off in the app process: its own tool calls (bringing footage in) are the director's, not the editor's.
    nonisolated(unsafe) public static var isEnabled = true
    /// The run Direction started this MCP server for; nil for a session you run yourself.
    public static var runID: String? { ProcessInfo.processInfo.environment["DIRECTION_RUN_ID"].flatMap { $0.isEmpty ? nil : $0 } }

    /// What the mapping needs to know about the film. Loaded once per call.
    public struct Context {
        public var project: Project?
        public var dailies = Dailies()
        public var cuts: [ReviewCut] = []
        public var turnovers: [Turnover] = []
        /// Note numbers by id; loaded only for calls that name notes.
        public var noteNumbers: () -> [String: Int] = { [:] }
        public init(project: Project? = nil, dailies: Dailies = Dailies(), cuts: [ReviewCut] = [], turnovers: [Turnover] = [], noteNumbers: @escaping () -> [String: Int] = { [:] }) {
            self.project = project; self.dailies = dailies; self.cuts = cuts; self.turnovers = turnovers; self.noteNumbers = noteNumbers
        }
        public static func load(_ store: ProjectStore) -> Context {
            Context(project: try? store.read(), dailies: (try? store.dailies()) ?? Dailies(), cuts: (try? store.cuts()) ?? [], turnovers: (try? store.turnovers()) ?? [],
                    noteNumbers: { Dictionary(((try? store.notes()) ?? []).compactMap { c in c.number.map { (c.id, $0) } }, uniquingKeysWith: { a, _ in a }) })
        }
        var fps: Double { project?.sequences.first?.frameRate.value ?? 24 }
        var sequence: DirectionCore.Sequence? {
            let id = turnovers.last(where: { $0.state.isOpen })?.sequenceID
            return project.flatMap { p in id.flatMap { id in p.sequences.first { $0.id == id } } ?? p.sequences.first }
        }
    }

    /// Records the call in the film's store. Never throws: activity must not get in the way of the work.
    public static func record(_ name: String, _ a: JSONValue, store: ProjectStore, runID: String?) {
        guard let input = activity(for: name, a, context: .load(store)) else { return }
        _ = try? store.recordActivity(input, runID: runID)
    }

    // MARK: The table

    /// nil for housekeeping calls (status, jobs, events) that aren't anything the director needs to see.
    public static func activity(for name: String, _ a: JSONValue, context c: Context) -> ActivityInput? {
        func reading(_ object: String) -> ActivityInput { ActivityInput(verb: "Reading", object: object, tool: name) }
        switch name {
        case "direction_frame":
            if let asset = a["assetID"].string { return ActivityInput(verb: "Looking at", object: take(asset, c), tool: name) }
            let t = seconds(a["time"]) ?? 0
            return ActivityInput(verb: "Watching", object: clock(t), mono: true, time: t, tool: name)
        case "direction_watch", "direction_preview":
            guard let (s, e) = range(a) else { return ActivityInput(verb: "Watching", object: "the cut", tool: name) }
            return ActivityInput(verb: "Watching", object: clock(s) + "\u{2013}" + clock(e), mono: true, time: s, tool: name)
        case "direction_contact_sheet":
            return ActivityInput(verb: "Looking at", object: a["assetID"].string.map { take($0, c) } ?? "the footage", tool: name)
        case "direction_measure_audio" where a["assetID"] == .null:
            return ActivityInput(verb: "Measuring", object: "the mix", tool: name)
        case "direction_transcribe", "direction_measure_audio", "direction_listen", "direction_sounds":
            return ActivityInput(verb: "Listening to", object: a["assetID"].string.map { take($0, c) } ?? "the footage", tool: name)
        case "direction_sync_takes":
            return ActivityInput(verb: "Matching", object: "the takes\u{2019} sound", tool: name)
        case "direction_audio":
            let asset = a["assetID"].string.map { take($0, c) } ?? "the sound"
            let changes = ["muted", "gainDB", "fadeIn", "fadeOut", "highPassHz", "bassDB", "trebleDB", "compressor", "thresholdDB", "limiter"].contains { a[$0] != .null }
            return changes ? ActivityInput(verb: "Mixing", object: asset, tool: name) : ActivityInput(verb: "Listening to", object: asset, tool: name)
        case "direction_screen_text":
            return ActivityInput(verb: "Reading the screen in", object: a["assetID"].string.map { take($0, c) } ?? "the footage", tool: name)
        case "direction_search_footage":
            let q = a["query"].string ?? a["text"].string ?? ""
            return ActivityInput(verb: "Searching footage for", object: "\u{201C}\(q)\u{201D}", tool: name)
        case "direction_edit", "direction_remove_range", "direction_edit_transcript":
            return edit(name, a, c)
        case "direction_make":
            if a["estimateOnly"].bool == true { return ActivityInput(verb: "Pricing", object: madeKind(a["kind"].string), tool: name) }
            let kind = madeKind(a["kind"].string ?? a["type"].string)
            let note = noteLabel(a, c)
            return ActivityInput(verb: a["kind"].string == "changedShot" ? "Changing" : "Making", object: note.map { "\(kind) for \($0)" } ?? kind, tool: name)
        case "direction_estimate":
            let n = a["steps"].array?.count ?? 0
            return ActivityInput(verb: "Pricing", object: n == 1 ? "one step" : "a plan of \(n) steps", tool: name)
        case "direction_graphic":
            let what = a["name"].string ?? a["title"].string ?? "a graphic"
            let note = noteLabel(a, c)
            return ActivityInput(verb: "Drawing", object: note.map { "\(what) for \($0)" } ?? what, time: seconds(a["at"]) ?? seconds(a["start"]), tool: name)
        case "direction_make_look":
            return ActivityInput(verb: "Making a look", object: noteLabel(a, c).map { "for \($0)" } ?? (a["name"].string ?? "for the film"), tool: name)
        case "direction_turnover_update":
            guard let lines = a["readBack"].array else { return nil }
            return ActivityInput(verb: "Reading back", object: count(lines.count, "note"), tool: name, turnoverID: a["turnoverID"].string)
        case "direction_ask":
            let ids = a["noteIDs"].array?.compactMap(\.string) ?? []
            let numbers = ids.compactMap { c.noteNumbers()[$0] }
            return ActivityInput(verb: "Asking you", object: numbers.isEmpty ? "a question" : "about " + notes(numbers), tool: name, turnoverID: a["turnoverID"].string)
        case "direction_turnover_complete":
            let t = a["turnoverID"].string.flatMap { id in c.turnovers.first { $0.id == id } }
            let cut = t?.kind == "assembly" || c.cuts.isEmpty ? "Assembly" : "Cut \(c.cuts.count + 1)"
            return ActivityInput(verb: "Delivering", object: cut, tool: name, turnoverID: t?.id)
        case "direction_log_dailies":
            let n = a["takes"].array?.count ?? 0
            return ActivityInput(verb: "Logging", object: n == 0 ? "the footage" : count(n, "take"), tool: name)
        case "direction_finishing":
            guard let items = a["items"].array, let first = items.first else { return reading("the finishing list") }
            return ActivityInput(verb: "Finishing", object: (first["title"].string ?? first["id"].string ?? "the film").lowercased(), tool: name)
        case "direction_import":
            return ActivityInput(verb: "Bringing in", object: a["path"].string.map { ($0 as NSString).lastPathComponent } ?? "footage", tool: name)
        case "direction_export":
            return ActivityInput(verb: "Exporting", object: "the cut", tool: name)
        case "direction_create_cut":
            return ActivityInput(verb: "Saving", object: a["name"].string ?? "a cut", tool: name)
        case "direction_restore":
            return ActivityInput(verb: "Restoring", object: a["revision"].int.map { "revision \($0)" } ?? "an earlier cut", tool: name)
        case "direction_feedback_reply":
            return ActivityInput(verb: "Answering", object: a["commentID"].string.flatMap { c.noteNumbers()[$0] }.map { "note \($0)" } ?? "a note", tool: name)
        case "direction_add_outside_note":
            return ActivityInput(verb: "Bringing in", object: "a note from \(a["name"].string ?? "someone")", tool: name)
        // Housekeeping: status lines and job polling aren't work the director needs to follow.
        case "direction_editor_status", "direction_job", "direction_jobs", "direction_cancel_job", "direction_events", "direction_capabilities", "direction_projects", "direction_open_project", "direction_create_project":
            return nil
        case "direction_brief": return reading("the brief")
        case "direction_turnovers", "direction_feedback": return reading("the notes")
        case "direction_feedback_context": return reading(a["commentID"].string.flatMap { c.noteNumbers()[$0] }.map { "note \($0)" } ?? "a note")
        case "direction_dailies": return reading("the dailies")
        case "direction_inspect", "direction_timeline": return reading("the cut")
        case "direction_transcript": return reading("the words")
        case "direction_questions": return reading("your answers")
        case "direction_cuts": return reading("the cuts")
        case "direction_edit_catalog": return reading("the edit functions")
        default:
            let words = name.hasPrefix("direction_") ? String(name.dropFirst("direction_".count)) : name
            return reading("the " + words.replacingOccurrences(of: "_", with: " "))
        }
    }

    /// Files and scripts the program touches in its own folder (Claude's Read/Write, Codex's file changes and commands).
    /// The program's own steps in plain words, never its file names: "Reading how to reframe", "Looking at a
    /// frame", "Writing a new effect".
    public static func programActivity(tool: String, path: String?) -> ActivityInput? {
        switch tool {
        case "Read", "NotebookRead": return ActivityInput(verb: reads(path).verb, object: reads(path).object, tool: tool)
        case "Write", "Edit", "MultiEdit", "NotebookEdit", "file_change": return ActivityInput(verb: "Writing", object: writes(path), tool: tool)
        case "Glob", "Grep", "LS": return ActivityInput(verb: "Looking through", object: "its folder", tool: tool)
        case "Bash", "command_execution": return ActivityInput(verb: "Running", object: "a script", tool: tool)
        default: return nil
        }
    }

    /// What reading a file is, by what it is.
    static func reads(_ path: String?) -> (verb: String, object: String) {
        guard let path else { return ("Reading", "its notes") }
        let url = URL(fileURLWithPath: path), name = url.lastPathComponent, ext = url.pathExtension.lowercased()
        if name == "SKILL.md" { return ("Reading", "how to " + skillWords(url.deletingLastPathComponent().lastPathComponent)) }
        if ["CLAUDE.md", "AGENTS.md"].contains(name) { return ("Reading", "what it\u{2019}s here to do") }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp"].contains(ext) { return ("Looking at", "a frame") }
        if ["mov", "mp4", "m4v"].contains(ext) { return ("Looking at", "footage") }
        if ["wav", "m4a", "mp3", "aif", "aiff"].contains(ext) { return ("Listening to", "sound") }
        return ("Reading", "its notes")
    }
    /// What writing a file is, by what it is.
    static func writes(_ path: String?) -> String {
        switch path.map({ URL(fileURLWithPath: $0).pathExtension.lowercased() }) {
        case "metal": "a new effect"
        case "js", "html", "svg": "a graphic"
        case "py", "sh", "swift", "rb", "mjs": "a script"
        case "md", "txt": "its notes"
        default: "a file"
        }
    }
    /// "reframe" → "reframe for the shape": a skill by what it teaches.
    static func skillWords(_ name: String) -> String {
        let known = ["assemble": "assemble a cut", "break-down": "break down the script", "edit-video": "edit", "finish": "finish the film",
                     "learn-technique": "learn a technique", "make-graphic": "make a graphic", "make-shot": "make a shot", "make-style": "make a style",
                     "propose-look": "propose a look", "reframe": "reframe for the shape", "review-feedback": "read your notes", "start-project": "start a film",
                     "take-turnover": "take your notes", "transitions": "use transitions", "write-av-script": "write the script"]
        return known[name] ?? name.replacingOccurrences(of: "-", with: " ")
    }

    /// "0:12", "1:02:03": a time in the cut the way the director reads it.
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds < 360_000 else { return "\u{2013}:\u{2013}\u{2013}" }
        let total = Int(max(0, seconds)), h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: Edits

    /// The verb for each edit function (agent-timeline.md › Operations). Multi-word verbs end with the
    /// preposition so "Swapping takes in scene 2" reads as a sentence.
    public static let editVerbs: [String: String] = [
        "insert": "Adding to", "overwrite": "Placing over", "removeRange": "Trimming", "remove": "Removing a shot from", "move": "Moving",
        "split": "Splitting", "trim": "Trimming", "roll": "Rolling", "slip": "Slipping", "slide": "Sliding", "splitEdit": "Overlapping sound in",
        "replaceTake": "Swapping takes in", "removeWords": "Cutting words in", "tightenPauses": "Tightening", "speed": "Retiming", "freeze": "Holding a frame in",
        "reframe": "Reframing", "balance": "Balancing", "matchBalance": "Matching", "cameraLUT": "Balancing", "color": "Balancing", "frame": "Reframing",
        "addEffect": "Adding an effect to", "setEffect": "Adjusting an effect in", "removeEffect": "Removing an effect from",
        "transition": "Adding a transition to", "removeTransition": "Removing a transition from", "cutaway": "Cutting away in",
        "placeGraphic": "Placing a graphic in", "placeMade": "Placing a made clip in", "gain": "Mixing", "fade": "Fading", "duck": "Ducking",
        "placeMusic": "Placing music in", "audio": "Mixing", "syncSound": "Syncing sound in", "title": "Titling", "format": "Changing the format of", "rename": "Renaming", "duplicateSequence": "Copying",
    ]

    private static func edit(_ name: String, _ a: JSONValue, _ c: Context) -> ActivityInput {
        let batch = a["batch"] == .null ? a : a["batch"]
        var ops = batch["operations"].array ?? []
        if name == "direction_remove_range" { ops = [.object(["op": .string("removeRange"), "range": .object(["start": a["start"], "end": a["end"]])])] }
        if name == "direction_edit_transcript" { ops = [.object(["op": .string("removeWords")])] }
        let first = ops.first ?? .null
        let op = first["op"].string ?? first["type"].string ?? ""
        let verb = editVerbs[op] ?? "Editing"
        // The scenes touched, in order.
        var scenes: [Int] = []
        for o in ops { for n in sceneNumbers(o, c) where !scenes.contains(n) { scenes.append(n) } }
        var object = scenes.isEmpty ? "the cut" : (scenes.count == 1 ? "scene " : "scenes ") + list(scenes.sorted().map(String.init))
        if ["format", "duplicateSequence", "rename"].contains(op) { object = "the cut" }
        if op == "reframe", let clip = clip(first["clipID"].string, c) {
            let scale = first["scale"].double.map { " to " + number($0) + "\u{00D7}" } ?? ""
            object = (clip.assetID.map { take($0, c) } ?? "the shot") + scale
        }
        var detail: [String] = []
        if op == "removeRange", let (s, e) = range(first) { detail.append(delta(-(e - s))) }
        if op == "trim", let f = first["frames"].double { detail.append(delta(f / c.fps)) }
        let noteValue = first["note"] != .null ? first["note"] : batch["notes"]
        if let n = noteNumbers(noteValue, c), !n.isEmpty { detail.append(notes(n)) }
        return ActivityInput(verb: verb, object: object, detail: detail.isEmpty ? nil : detail.joined(separator: " \u{00B7} "), time: firstTime(first, c), tool: name)
    }

    private static func clip(_ id: String?, _ c: Context) -> Clip? { id.flatMap { id in c.sequence?.clips.first { $0.id == id } } }
    private static func storyClip(at t: Double, _ c: Context) -> Clip? {
        c.sequence?.clips.first { $0.kind == .video && $0.layer == 0 && t >= $0.start.seconds && t < $0.start.seconds + $0.sourceRange.duration.seconds / max($0.speed, 0.0001) }
    }
    private static func sceneNumbers(_ op: JSONValue, _ c: Context) -> [Int] {
        var clips: [Clip] = []
        for key in ["clipID", "toClipID"] { if let x = clip(op[key].string, c) { clips.append(x) } }
        if let point = op["editPoint"].string, let left = point.split(separator: "|").first, let x = clip(String(left), c) { clips.append(x) }
        if let target = op["target"].string, let x = clip(target, c) { clips.append(x) }
        if let (s, e) = range(op) {
            clips += c.sequence?.clips.filter { $0.layer == 0 && $0.start.seconds < e && $0.start.seconds + $0.sourceRange.duration.seconds / max($0.speed, 0.0001) > s } ?? []
        }
        if let t = seconds(op["at"]), let x = storyClip(at: t, c) { clips.append(x) }
        var out = clips.compactMap { c.dailies.scene(for: $0.assetID)?.number }
        if out.isEmpty, let asset = op["assetID"].string ?? op["withAssetID"].string, let s = c.dailies.scene(for: asset) { out.append(s.number) }
        return out
    }
    private static func firstTime(_ op: JSONValue, _ c: Context) -> Double? {
        if let (s, _) = range(op) { return s }
        if let t = seconds(op["at"]) { return t }
        for key in ["clipID", "target"] { if let x = clip(op[key].string, c) { return x.start.seconds } }
        if let point = op["editPoint"].string, let right = point.split(separator: "|").last, let x = clip(String(right), c) { return x.start.seconds }
        return nil
    }

    // MARK: Words

    /// "3B T2" from the dailies log, else the file's name.
    static func take(_ assetID: String, _ c: Context) -> String {
        let t = c.dailies.take(assetID)
        if let code = t.code, let setup = t.setupCode { return "\(setup) \(code)" }
        return c.project?.assets.first { $0.id == assetID }?.name ?? "a take"
    }
    private static func madeKind(_ kind: String?) -> String {
        switch kind {
        case "music": "music"
        case "soundEffect", "sound": "a sound effect"
        case "voice": "a voice"
        case "shot": "a shot"
        case "extension": "a longer shot"
        case "bridge": "a bridge"
        case "changedShot": "a take"
        case "slowMotion": "slow motion"
        case "upscale": "a sharper take"
        case "still": "a still"
        default: kind ?? "something"
        }
    }
    private static func noteLabel(_ a: JSONValue, _ c: Context) -> String? {
        for key in ["note", "noteID", "notes", "noteIDs"] { if let n = noteNumbers(a[key], c), !n.isEmpty { return notes(n) } }
        return nil
    }
    /// Note numbers from numbers, ids, or a list of either.
    private static func noteNumbers(_ v: JSONValue, _ c: Context) -> [Int]? {
        switch v {
        case .number(let n): return [Int(n)]
        case .string(let id): return c.noteNumbers()[id].map { [$0] } ?? Int(id).map { [$0] }
        case .array(let items): let out = items.flatMap { noteNumbers($0, c) ?? [] }; return out.isEmpty ? nil : out
        default: return nil
        }
    }
    static func notes(_ numbers: [Int]) -> String { (numbers.count == 1 ? "note " : "notes ") + list(numbers.map(String.init)) }
    static func list(_ items: [String]) -> String { items.count <= 1 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last! }
    private static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    private static func number(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    /// −4.2 s, with a true minus sign.
    static func delta(_ s: Double) -> String { let v = (s * 10).rounded() / 10; return (v < 0 ? "\u{2212}" : "+") + String(format: "%.1f s", abs(v)) }

    /// MM:SS:FF under an hour, H:MM:SS:FF over (product-model.md › Formats).
    public static func timecode(_ seconds: Double, _ fps: Double) -> String {
        guard seconds.isFinite, seconds < 360_000 else { return "--:--:--" }
        let s = max(0, seconds), rate = fps.isFinite ? max(1, fps.rounded()) : 24
        let total = Int(s), frames = min(Int(rate) - 1, Int(((s - Double(total)) * rate + 1e-6).rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d:%02d", h, m, sec, frames) : String(format: "%02d:%02d:%02d", m, sec, frames)
    }

    /// Seconds from a number, or from a `{value, timescale}` media time.
    static func seconds(_ v: JSONValue) -> Double? {
        if let d = v.double, d.isFinite { return d }
        if let value = v["value"].double, let scale = v["timescale"].double, scale > 0 { return value / scale }
        return nil
    }
    /// A range from `start`/`end` seconds, `range: {start, end}`, or `range: {start, duration}` media times.
    static func range(_ v: JSONValue) -> (Double, Double)? {
        if let s = seconds(v["start"]), let e = seconds(v["end"]), e > s { return (s, e) }
        let r = v["range"]
        if r != .null {
            if let s = seconds(r["start"]), let e = seconds(r["end"]), e > s { return (s, e) }
            if let s = seconds(r["start"]), let d = seconds(r["duration"]), d > 0 { return (s, s + d) }
        }
        return nil
    }
}
