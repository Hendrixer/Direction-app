import Foundation

// The fixed vocabulary of the editor's timeline (agent-timeline.md): every operation with its arguments,
// every effect with its parameters' ranges and defaults, the transitions and the error codes.
public enum EditCatalog {
    public struct Param: Codable, Hashable, Sendable {
        public var name: String
        /// number, bool, choice, crop, color or text.
        public var kind: String
        public var min: Double?
        public var max: Double?
        public var defaultValue: JSONValue?
        public var choices: [String]?
        public var keyable: Bool
        public init(name: String, kind: String, min: Double? = nil, max: Double? = nil, defaultValue: JSONValue? = nil, choices: [String]? = nil, keyable: Bool = false) { self.name = name; self.kind = kind; self.min = min; self.max = max; self.defaultValue = defaultValue; self.choices = choices; self.keyable = keyable }
        var rangeText: String { "\(String(format: "%g", min ?? 0))–\(String(format: "%g", max ?? 0))" }
    }
    public struct Effect: Codable, Hashable, Sendable {
        public var name: String
        public var params: [Param]
        public var keys: Bool
        public var note: String
    }
    public struct Argument: Codable, Hashable, Sendable { public var name: String; public var type: String; public var required: Bool }
    public struct Operation: Codable, Hashable, Sendable { public var op: String; public var group: String; public var arguments: [Argument]; public var does: String }

    public static let blendModes = ["normal", "screen", "multiply", "overlay", "add"]
    public static let transitions = ["dissolve", "dipToBlack", "dipToWhite"] + builtInTransitions.map(\.name) + ["shader"]
    /// Direction's own transitions (agent-timeline.md › Transitions): Metal functions that ship with it,
    /// drawn from both shots at once, so like a dissolve they need handle on both sides.
    public static let builtInTransitions: [(name: String, params: [Param], note: String)] = {
        let way = [number("x", -1, 1, -1, keyable: false), number("y", -1, 1, 0, keyable: false)]
        return [
            ("push", way, "The new shot pushes the old one out of frame. x and y are the way they travel: x −1 to the left, y 1 down."),
            ("slide", way, "The new shot slides in over the old one, which stays where it is."),
            ("whip", way + [number("blur", 0, 1, 0.7, keyable: false)], "A whip pan: a fast push smeared along the way it travels. Put a whoosh under it."),
            ("zoom", [number("amount", 1.2, 6, 2.5, keyable: false)], "The old shot rushes toward the middle and the new one settles out of the rush, blurred along it."),
            ("wipe", [number("angle", -180, 180, 0, keyable: false), number("softness", 0, 0.5, 0.08, keyable: false)], "An edge crosses the frame onto the new shot; angle 0 travels left to right, 90 top to bottom."),
            ("iris", [number("x", 0, 1, 0.5, keyable: false), number("y", 0, 1, 0.5, keyable: false), number("softness", 0, 0.5, 0.04, keyable: false)], "A circle opens from x, y (fractions of the frame from its top left) onto the new shot."),
        ]
    }()
    public static func builtInTransition(_ name: String) -> (name: String, params: [Param], note: String)? { builtInTransitions.first { $0.name == name } }
    /// looks.md › Filters, in their fixed order, with each one's option.
    public static let filters: [(kind: String, options: [String]?)] = [("blackAndWhite", nil), ("splitTone", ["warmTeal", "coolAmber"]), ("fade", nil), ("halation", nil), ("bloom", nil), ("soften", nil), ("chromaticAberration", nil), ("vignette", nil), ("grain", ["fine", "medium", "coarse"]), ("gateWeave", nil), ("letterbox", ["2.39", "2.00", "1.85"])]

    static func number(_ name: String, _ min: Double, _ max: Double, _ value: Double, keyable: Bool) -> Param { .init(name: name, kind: "number", min: min, max: max, defaultValue: .number(value), keyable: keyable) }
    public static let effects: [Effect] = [
        .init(name: "transform", params: [number("scale", 0.1, 8, 1, keyable: true), number("x", -8, 8, 0, keyable: true), number("y", -8, 8, 0, keyable: true), number("rotation", -180, 180, 0, keyable: true), number("opacity", 0, 1, 1, keyable: true), .init(name: "crop", kind: "crop", min: 0, max: 0.5, defaultValue: .object(["l": .number(0), "r": .number(0), "t": .number(0), "b": .number(0)]), keyable: true)], keys: true, note: "Scale over the fitted frame; x and y are fractions of the frame (y down); rotation in degrees, clockwise; crop {l, r, t, b} keys as crop.l…. reframe writes this."),
        .init(name: "blend", params: [.init(name: "mode", kind: "choice", defaultValue: .string("normal"), choices: blendModes)], keys: false, note: "On V2+ clips."),
        .init(name: "mask", params: [.init(name: "shape", kind: "choice", defaultValue: .string("rect"), choices: ["rect", "ellipse"]), number("x", 0, 1, 0.25, keyable: true), number("y", 0, 1, 0.25, keyable: true), number("w", 0, 1, 0.5, keyable: true), number("h", 0, 1, 0.5, keyable: true), number("feather", 0, 0.5, 0.05, keyable: true), .init(name: "invert", kind: "bool", defaultValue: .bool(false))], keys: true, note: "Limits the clip's other effects to the shape. x y w h are fractions of the frame, from its top left."),
        .init(name: "card", params: [number("radius", 0, 0.5, 0.2, keyable: false), number("edge", 0, 1, 0.3, keyable: false), number("shadow", 0, 1, 0.5, keyable: false), .init(name: "background", kind: "text")], keys: false, note: "Gives the clip's placed picture rounded corners (radius, a fraction of its shorter side; 0.5 on a square is a circle), a thin light edge and a soft shadow, over an optional background color (#RRGGBB) that fills the frame. Layouts write it."),
        .init(name: "blur", params: [number("radius", 0, 100, 0, keyable: true)], keys: true, note: "Pixels at the cut's size."),
        .init(name: "sharpen", params: [number("amount", 0, 1, 0, keyable: false)], keys: false, note: ""),
        .init(name: "stabilize", params: [number("amount", 0, 1, 0.5, keyable: false)], keys: false, note: "Vision homographic registration, measured and cached per clip."),
        pin,
    ] + filters.map { f in
        .init(name: "filter." + f.kind, params: (f.kind == "letterbox" ? [] : [number("amount", 0, 1, 0.5, keyable: true)]) + (f.options.map { [.init(name: "option", kind: "choice", defaultValue: .string($0[0]), choices: $0)] } ?? []), keys: f.kind != "letterbox", note: "The look's \(f.kind) filter on this clip alone, apart from the director's look.")
    } + [
        .init(name: "shader", params: [.init(name: "file", kind: "text")], keys: true, note: "Your Metal function in Effects/<name>.metal; its header declares the rest of its parameters."),
    ]
    public static func effect(_ name: String) -> Effect? { effects.first { $0.name == name } }
    /// The pin effect's corners, in the order its parameters and the corners argument take them.
    public static let pinCorners = ["tl", "tr", "br", "bl"]
    static let pin: Effect = {
        var params: [Param] = []
        for (c, x, y) in [("tl", 0.0, 0.0), ("tr", 1.0, 0.0), ("br", 1.0, 1.0), ("bl", 0.0, 1.0)] { params += [number(c + ".x", -1, 2, x, keyable: true), number(c + ".y", -1, 2, y, keyable: true)] }
        return Effect(name: "pin", params: params, keys: true, note: "Puts the clip's whole picture into four corners of the frame (fractions from its top left, y down), in perspective: onto a screen, a window, a sign. It takes the place of the clip's framing and transform; crop and opacity still apply. The pin operation finds the corners and follows them for you.")
    }()

    static func op(_ name: String, _ group: String, _ args: String, _ does: String) -> Operation {
        .init(op: name, group: group, arguments: args.split(separator: " ").map { a in
            let parts = a.split(separator: ":", maxSplits: 1).map(String.init)
            let n = parts[0].hasSuffix("?") ? String(parts[0].dropLast()) : parts[0]
            return Argument(name: n, type: parts.count > 1 ? parts[1] : "string", required: !parts[0].hasSuffix("?"))
        }, does: does)
    }
    public static let operations: [Operation] = [
        op("insert", "Story", "assetID sourceRange:range at:seconds track?:track", "Inserts and ripples everything after it."),
        op("overwrite", "Story", "assetID sourceRange:range at:seconds track?:track", "Places over what's there, without moving anything."),
        op("removeRange", "Story", "range:range ripple?:bool", "Removes the range on every track; ripple (default true) closes the gap."),
        op("remove", "Story", "clipID ripple?:bool", "Removes a clip; ripple closes the gap (every track for V1)."),
        op("move", "Story", "clipID to:{at|before|after,track?}", "Moves a clip and its linked sound. A V1 clip takes everything over it and the story closes up behind it."),
        op("split", "Story", "clipID at:seconds", "Splits a clip at a cut time."),
        op("trim", "Story", "clipID edge:head|tail frames:int ripple?:bool", "Extends (+frames) or shortens (−frames) one end. ripple defaults to true."),
        op("roll", "Story", "editPoint frames:int", "Moves a cut point; the total length doesn't change."),
        op("slip", "Story", "clipID frames:int", "Changes which part of the take plays, without moving the clip."),
        op("slide", "Story", "clipID frames:int", "Moves a clip between its neighbors, trimming them to fit."),
        op("splitEdit", "Story", "editPoint lead:sound|picture frames:int", "J-cut (sound leads) or L-cut (picture leads, sound carries). 0 frames is a straight cut."),
        op("replaceTake", "Story", "clipID withAssetID alignOn:words|head|tail ripple?:bool", "Swaps in another take. With words, the same line lines up word for word."),
        op("removeWords", "Story", "wordIDs:[string]", "Cuts the words and their picture on every layer."),
        op("tightenPauses", "Story", "range:range longerThan:seconds to:seconds", "Shortens each pause longer than longerThan to `to`, in the quiet between words."),
        op("speed", "Story", "clipID rate:number ripple?:bool", "0.1–8; 2 plays twice as fast."),
        op("freeze", "Story", "clipID at:seconds seconds:number", "Holds a frame, rippling everything after it."),
        op("reframe", "Picture", "clipID scale:number x?:number y?:number follow?:face|subject keepIn?:thirds|center", "Writes the clip's transform. With follow, Direction tracks the face or subject with Vision and writes the keys."),
        op("balance", "Picture", "clipID exposure?:number contrast?:number saturation?:number temperature?:number tint?:number", "Shot matching. Ranges: exposure −5–5, contrast 0–4, saturation 0–3, temperature −3000–3000, tint −100–100."),
        op("matchBalance", "Picture", "clipID toClipID", "Measures both shots and sets the balance that matches the reference."),
        op("cameraLUT", "Picture", "assetID lut:auto|none|file", "Per take, not per clip."),
        op("addEffect", "Picture", "target:clip|track effect params:object keys?:object", "Returns the effect's id."),
        op("setEffect", "Picture", "effectID params?:object keys?:object", "Changes an effect's parameters or keys."),
        op("removeEffect", "Picture", "effectID", "Takes an effect off."),
        op("transition", "Picture", "editPoint type:dissolve|dipToBlack|dipToWhite|push|slide|whip|zoom|wipe|iris|shader frames:int params?:object", "Centered on the cut. Everything but the dips draws both shots, so it needs handles on both sides. push, slide, whip, zoom, wipe and iris take params (see transitions); shader is your own, params.file \"Transitions/<name>.metal\" and the parameters its header declares. \"|<clip>\" dips in at a clip's head."),
        op("removeTransition", "Picture", "editPoint", "Makes it a straight cut."),
        op("cutaway", "Layers", "assetID sourceRange?:range seconds?:number at?:seconds cover?:clip|editPoint", "Puts picture on V2 or above; the sound underneath keeps playing. With cover, it's centered over the cut. Without sourceRange, give seconds: a take in sync with V1 there (direction_dailies › syncGroups) plays the same moment, which is how you switch angles or put a screen recording under the words that describe it. It stays in sync as the cut changes: Direction lines it up again after every edit and splits it where V1 jumps; slipping it, or a V1 it can't follow, makes it a plain cutaway, with a warning."),
        op("layout", "Layers", "range:range layout:{kind,corner?,size?,shape?,screen?}", "How the screen recording and the camera in sync share the frame over range: screenAndYou (you in a bubble: corner topLeft|topRight|bottomLeft|bottomRight, size small|medium|large, shape circle|rounded|wide), you, screen, or sideBySide; screen full|framed (smaller on a background). Direction finds which take is which and keeps the bubble on the face. It replaces earlier layouts and cutaways in sync over range. Layouts the director set are theirs (layout_is_yours) unless a note asks."),
        op("pin", "Layers", "clipID corners?:[[x,y]×4] follow?:screen", "Puts a clip on V2 or above into a screen, window or sign in the shot under it, in perspective. Without corners Direction finds the biggest one in that shot and follows it as the camera moves; with corners it stays there, unless follow: screen follows it from them. Writes the clip's pin effect."),
        op("zoomThrough", "Layers", "editPoint seconds?:number corners?:[[x,y]×4]", "Pushes into a screen (or window, frame, doorway) in the left shot over its last seconds (default 1) until it fills the frame at the cut, with the right shot's first frame pinned in it, so the cut lands inside the screen. Without corners Direction finds the biggest one near the cut and follows it. Adds a transform to the left clip and the right shot's first frame on V2 or above."),
        op("placeGraphic", "Layers", "graphic at:seconds seconds?:number aboveLook?:bool", "Places a checked graphic on the first free layer at V2 or above, above the look by default."),
        op("placeMade", "Layers", "madeID at:seconds track:track sourceRange?:range", "Places a made clip like footage."),
        op("gain", "Sound", "target:clip|track dB:number keys?:{dB:[{t,v}]}", "Clip or track gain, with keys in dB."),
        op("fade", "Sound", "clipID in?:frames out?:frames", "Fades a clip's sound."),
        op("duck", "Sound", "track under?:track dB:number attack?:seconds release?:seconds", "Finds every line of dialogue on `under` (A1) from the words and writes the gain keys on `track` (A2)."),
        op("syncSound", "Sound", "clipID assetID?", "A take in sync with a V1 clip plays its sound under it, lined up, in place of the clip's own: the group's sound take (soundAssetID) by default, or assetID. Use it when the angle on V1 isn't the sound take (the screen on V1 with the camera's mic, a camera with a separate recorder). Naming the clip's own take puts its own sound back. It stays in sync like a cutaway."),
        op("placeMusic", "Sound", "madeID|assetID at:seconds endOn:{cut}|{word}|seconds track?:track", "Lines the music's end up with a cut or a word, trimming from the head."),
        op("audio", "Sound", "assetID|clipID audioTrackID:int audio:object", "EQ, compression and per-stream settings, as before."),
        op("format", "Film", "width?:int height?:int frameRate?:{numerator,denominator}", "The cut's size and rate."),
        op("duplicateSequence", "Film", "text width?:int height?:int", "A copy of the cut, for another format."),
    ]

    public static let errors: [(code: String, when: String)] = [
        ("scene_locked", "It would recut a locked scene: its takes, timing, framing, joins, or any picture over it. Its color and sound stay open."),
        ("picture_locked", "Any picture change after picture lock. Color and sound still change."),
        ("stale_revision", "baseEditRevision isn't current."),
        ("overlap", "It would make two clips overlap on one track."),
        ("unknown_op", "Not in the catalog."),
        ("bad_argument", "A value out of range, a missing argument or an id that isn't in the cut."),
        ("missing_media", "An asset, graphic or made clip that doesn't exist."),
        ("no_words", "replaceTake with words, tightenPauses, removeWords or duck on a take with no transcript."),
        ("not_in_sync", "A cutaway without sourceRange from a take that isn't in sync with the story clip under it."),
        ("look_is_yours", "Anything that would change the director's look."),
        ("words_are_yours", "Changing a graphic's words the director set, without a note that names it (direction_graphic)."),
        ("layout_is_yours", "Changing a layout the director set (or its clips), without a note that asks for it."),
        ("shader_invalid", "A shader that doesn't compile, or makes NaN."),
        ("shader_too_slow", "A shader slower than 40 ms a frame at 1080p."),
        ("no_screen", "pin or zoomThrough without corners, in a shot where Direction can't find a screen, window or sign."),
    ]

    public static func json(custom: [JSONValue] = [], problems: [JSONValue] = []) -> JSONValue {
        let ops = (try? JSONValue.wrapping(operations)) ?? .array([])
        let fx = (try? JSONValue.wrapping(effects)) ?? .array([])
        return .object([
            "operations": ops, "effects": fx, "customEffects": .array(custom), "customEffectProblems": .array(problems),
            "transitions": .array(transitions.map { t in
                var v: [String: JSONValue] = ["type": .string(t), "otio": .string(t == "dissolve" ? "SMPTE_Dissolve" : "Direction_" + t)]
                if let b = builtInTransition(t) { v["params"] = (try? .wrapping(b.params)) ?? .array([]); v["does"] = .string(b.note) }
                if t == "shader" { v["does"] = .string("Your own, from Transitions/<name>.metal: params.file and the parameters its header declares (customTransitions lists the ones that compile).") }
                return .object(v)
            }),
            "blendModes": .array(blendModes.map(JSONValue.string)),
            "errors": .array(errors.map { .object(["code": .string($0.code), "when": .string($0.when)]) }),
            "conventions": .object([
                "times": .string("Cut seconds unless an argument says source. frames count frames at the cut's rate. Every result snaps to whole frames."),
                "editPoint": .string("\"<left clip>|<right clip>\", ids from direction_timeline."),
                "tracks": .string("V1 is the story; V2+ overlays (graphics, cutaways, made shots). A1 dialogue (V1's own sound), A2 music, A3 sound effects."),
                "keys": .string("{param: [{t, v, ease?}]}, t in cut seconds; ease is linear, hold or smooth."),
                "notes": .string("Each batch names the notes it answers (notes, or an operation's note). With no open turnover, or latitude Take a pass, a change may name none and is labeled Unasked."),
            ]),
        ])
    }
}

/// A shader's own parameters, from its header comments:
/// `// direction: param amount 0 1 0.5` and `// direction: param tint color #F2A33A`.
public struct ShaderParam: Codable, Hashable, Sendable {
    public var name: String
    /// number or color.
    public var kind: String
    public var min: Double?
    public var max: Double?
    public var defaultValue: JSONValue
    var catalogParam: EditCatalog.Param { .init(name: name, kind: kind, min: min, max: max, defaultValue: defaultValue, keyable: kind == "number") }
}

public enum ShaderHeader {
    public static func params(_ source: String) throws -> [ShaderParam] {
        var out: [ShaderParam] = []
        for (n, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("//"), let r = t.range(of: "direction:") else { continue }
            let words = t[r.upperBound...].split(separator: " ").map(String.init)
            guard words.first == "param" else { continue }
            func invalid(_ m: String) -> DirectionError { .init("shader_invalid", "Line \(n + 1): \(m)") }
            guard words.count >= 3, let name = words.dropFirst().first, name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil, name != "file" else { throw invalid("a parameter is `// direction: param <name> <min> <max> <default>` or `… <name> color #RRGGBB`.") }
            guard !out.contains(where: { $0.name == name }) else { throw invalid("\(name) is declared twice.") }
            if words[2] == "color" {
                guard words.count == 4, rgb(words[3]) != nil else { throw invalid("a color parameter's default is #RRGGBB.") }
                out.append(.init(name: name, kind: "color", defaultValue: .string(words[3])))
            } else {
                guard words.count == 5, let lo = Double(words[2]), let hi = Double(words[3]), let v = Double(words[4]), lo < hi, (lo...hi).contains(v) else { throw invalid("\(name) needs a min, a max and a default between them.") }
                out.append(.init(name: name, kind: "number", min: lo, max: hi, defaultValue: .number(v)))
            }
        }
        guard out.count <= 16 else { throw DirectionError("shader_invalid", "A shader takes up to 16 parameters.") }
        return out
    }
    public static func rgb(_ hex: String) -> (Double, Double, Double)? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

/// Timecode at a cut's rate (product-model › Formats): MM:SS:FF under an hour, H:MM:SS:FF over.
public enum CutTimecode {
    public static func string(_ seconds: Double, rate: Double) -> String {
        let fps = max(1, Int(rate.rounded())), total = max(0, Int((seconds * rate).rounded()))
        let ff = total % fps, s = (total / fps) % 60, m = (total / fps / 60) % 60, h = total / fps / 3600
        return h > 0 ? String(format: "%d:%02d:%02d:%02d", h, m, s, ff) : String(format: "%02d:%02d:%02d", m, s, ff)
    }
    /// A length without the leading zero: "3:40:00".
    public static func length(_ seconds: Double, rate: Double) -> String {
        let t = string(seconds, rate: rate)
        return t.hasPrefix("0") && t.count == 8 ? String(t.dropFirst()) : t
    }
    /// 23.976, 24, 29.97.
    public static func rate(_ rate: Double) -> String {
        var s = String(format: "%.3f", rate)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
