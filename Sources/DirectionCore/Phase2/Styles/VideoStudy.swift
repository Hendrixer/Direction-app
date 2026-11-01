import Foundation

/// What Direction measured in a video someone else made, to learn a style from it (styles.md › From a
/// video): what it can count, so the editor judges only what it can't. Kept as study.json beside the
/// video's contact sheets and words; a style keeps the numbers once it's made, and the video goes.
public struct VideoStudy: Codable, Hashable, Sendable {
    public var title: String
    /// The channel or person who made it, when the page says.
    public var by: String?
    /// Where it came from: a web page, or a file's name.
    public var link: String?
    public var seconds: Double
    public var width: Int?
    public var height: Int?
    public var studiedAt: Double
    public var pace: Pace
    public var words: Words?
    public var sound: Sound?
    public var picture: Picture
    public var onScreen: OnScreenText?
    /// What the video's page says about its music, line by line as written there ("Music: Epidemic Sound").
    public var musicCredits: [String]?
    /// Every shot, in order.
    public var shots: [Shot]

    public init(title: String, by: String? = nil, link: String? = nil, seconds: Double, width: Int? = nil, height: Int? = nil, studiedAt: Double = Date().timeIntervalSince1970,
                pace: Pace, words: Words? = nil, sound: Sound? = nil, picture: Picture, onScreen: OnScreenText? = nil, musicCredits: [String]? = nil, shots: [Shot]) {
        self.title = title; self.by = by; self.link = link; self.seconds = seconds; self.width = width; self.height = height; self.studiedAt = studiedAt
        self.pace = pace; self.words = words; self.sound = sound; self.picture = picture; self.onScreen = onScreen; self.musicCredits = musicCredits; self.shots = shots
    }

    /// How fast it cuts.
    public struct Pace: Codable, Hashable, Sendable {
        public var shots: Int
        public var cutsPerMinute: Double
        public var averageShot: Double
        public var medianShot: Double
        public var longestShot: Double
        /// When the first cut comes, in seconds; nil for one shot.
        public var firstCut: Double?
        /// Cuts in each minute, so a faster opening shows.
        public var cutsByMinute: [Int]
        public init(shots: Int, cutsPerMinute: Double, averageShot: Double, medianShot: Double, longestShot: Double, firstCut: Double?, cutsByMinute: [Int]) {
            self.shots = shots; self.cutsPerMinute = cutsPerMinute; self.averageShot = averageShot; self.medianShot = medianShot; self.longestShot = longestShot; self.firstCut = firstCut; self.cutsByMinute = cutsByMinute
        }
    }

    /// How it talks: how many words and how tight the pauses are left.
    public struct Words: Codable, Hashable, Sendable {
        public var count: Int
        public var perMinute: Double
        /// The gap between words, in seconds, at the median and the longest.
        public var medianPause: Double
        public var longestPause: Double
        /// Of the gaps between sentences or thoughts (over 0.25 s), the share longer than half a second.
        public var pausesOverHalfSecond: Double
        public init(count: Int, perMinute: Double, medianPause: Double, longestPause: Double, pausesOverHalfSecond: Double) {
            self.count = count; self.perMinute = perMinute; self.medianPause = medianPause; self.longestPause = longestPause; self.pausesOverHalfSecond = pausesOverHalfSecond
        }
    }

    public struct Sound: Codable, Hashable, Sendable {
        /// Integrated loudness (BS.1770) and true peak of the whole video.
        public var loudness: Double?
        public var truePeak: Double?
        /// Share of the running time with music, and with music under speech.
        public var music: Double?
        public var musicUnderSpeech: Double?
        /// Each stretch of music six seconds or longer, in order. A stretch that changes key or chords partway
        /// is two cues.
        public var cues: [Cue]?
        /// Music shorter than that, where each starts: risers, transitions, hits.
        public var stings: [Double]?
        /// Stretches of talk of four seconds or more between cues with no music under them.
        public var breaks: [Stretch]?
        /// The music in the pauses between words against the voice, and the music with nobody talking against
        /// the voice, in dB (−18: eighteen under it).
        public var musicUnderVoiceDB: Double?
        public var musicAloneDB: Double?
        /// Other sounds the classifier heard, each where it starts: added effects, or the footage's own.
        public var effects: [Effect]?
        /// The key most of the music fits, across every cue: one key held through a film is a choice.
        public var key: String?
        /// Of the cuts with music playing and no word starting on them, how many land on a hit; of the cuts with
        /// no talk in the two seconds before, how many the level rises into. Under the voice a riser can't be told.
        public var cutsHeard: Int?
        public var hitsOnCuts: Int?
        public var cutsClearOfTalk: Int?
        public var risersIntoCuts: Int?
        public init(loudness: Double? = nil, truePeak: Double? = nil, music: Double? = nil, musicUnderSpeech: Double? = nil, cues: [Cue]? = nil, stings: [Double]? = nil, breaks: [Stretch]? = nil,
                    musicUnderVoiceDB: Double? = nil, musicAloneDB: Double? = nil, effects: [Effect]? = nil, key: String? = nil, cutsHeard: Int? = nil, hitsOnCuts: Int? = nil, cutsClearOfTalk: Int? = nil, risersIntoCuts: Int? = nil) {
            self.loudness = loudness; self.truePeak = truePeak; self.music = music; self.musicUnderSpeech = musicUnderSpeech; self.cues = cues; self.stings = stings; self.breaks = breaks
            self.musicUnderVoiceDB = musicUnderVoiceDB; self.musicAloneDB = musicAloneDB; self.effects = effects; self.key = key; self.cutsHeard = cutsHeard; self.hitsOnCuts = hitsOnCuts; self.cutsClearOfTalk = cutsClearOfTalk; self.risersIntoCuts = risersIntoCuts
        }
    }

    /// One stretch of music: what plays in it, its beat and key when they can be told, how much of it is under
    /// the voice, and whether it starts and ends on a cut (within the second the classifier hears in).
    public struct Cue: Codable, Hashable, Sendable {
        public var start: Double
        public var end: Double
        /// "piano", "bowed strings", "synth", "vocals": what the classifier heard in a quarter of it or more.
        public var instruments: [String]
        /// Beats a minute; nil when there's no steady beat (a drone, a pad) or the voice covers it.
        public var tempo: Double?
        /// "A minor"; nil when no key stands out.
        public var key: String?
        /// Share of its seconds with someone talking over it.
        public var underSpeech: Double
        public var startsOnCut: Bool?
        public var endsOnCut: Bool?
        public init(start: Double, end: Double, instruments: [String] = [], tempo: Double? = nil, key: String? = nil, underSpeech: Double = 0, startsOnCut: Bool? = nil, endsOnCut: Bool? = nil) {
            self.start = start; self.end = end; self.instruments = instruments; self.tempo = tempo; self.key = key; self.underSpeech = underSpeech; self.startsOnCut = startsOnCut; self.endsOnCut = endsOnCut
        }
    }

    public struct Stretch: Codable, Hashable, Sendable {
        public var start: Double
        public var end: Double
        public init(start: Double, end: Double) { self.start = start; self.end = end }
    }

    public struct Effect: Codable, Hashable, Sendable {
        public var at: Double
        /// "whoosh", "ticking clock", "click".
        public var sound: String
        public var onCut: Bool?
        public init(at: Double, sound: String, onCut: Bool? = nil) { self.at = at; self.sound = sound; self.onCut = onCut }
    }

    /// How it's framed and how it looks, as shares of its shots and averages of its frames (0–1).
    public struct Picture: Codable, Hashable, Sendable {
        public var close: Double
        public var medium: Double
        public var wide: Double
        /// Shots with no face in them (screens, b-roll, graphics).
        public var noFace: Double
        /// Of the cuts between two shots of the same face, the share that changes its size (a punch-in or out).
        public var punchIns: Double
        public var brightness: Double
        public var contrast: Double
        public var saturation: Double
        /// Above 0 warmer, below 0 cooler (red minus blue, −1–1).
        public var warmth: Double
        public init(close: Double, medium: Double, wide: Double, noFace: Double, punchIns: Double, brightness: Double, contrast: Double, saturation: Double, warmth: Double) {
            self.close = close; self.medium = medium; self.wide = wide; self.noFace = noFace; self.punchIns = punchIns
            self.brightness = brightness; self.contrast = contrast; self.saturation = saturation; self.warmth = warmth
        }
    }

    /// Words on screen: captions are text that matches what's being said at that moment.
    public struct OnScreenText: Codable, Hashable, Sendable {
        /// Share of the looks (one a second) with captions, and with other text.
        public var captions: Double
        public var otherText: Double
        public var wordsPerCaption: Double?
        /// Where captions sit, top 0 to bottom 1.
        public var captionHeight: Double?
        /// Share of caption words in capitals.
        public var upperCase: Double?
        public init(captions: Double, otherText: Double, wordsPerCaption: Double? = nil, captionHeight: Double? = nil, upperCase: Double? = nil) {
            self.captions = captions; self.otherText = otherText; self.wordsPerCaption = wordsPerCaption; self.captionHeight = captionHeight; self.upperCase = upperCase
        }
    }

    public struct Shot: Codable, Hashable, Sendable {
        public var start: Double
        public var end: Double
        /// close, medium or wide by the face's size; nil when there's no face.
        public var framing: String?
        /// Words on screen in the middle of the shot, if any.
        public var text: String?
        public init(start: Double, end: Double, framing: String? = nil, text: String? = nil) { self.start = start; self.end = end; self.framing = framing; self.text = text }
    }

    public static let fileName = "study.json"

    /// The lines on a video's page about its music: the track the page names, then the description's lines that
    /// mention music, a song or a music library, as written, eight at most.
    public static func musicCredits(description: String?, track: String?, artist: String?) -> [String] {
        var out: [String] = []
        if let track = track?.trimmingCharacters(in: .whitespaces), !track.isEmpty { out.append("\u{201C}\(track)\u{201D}" + (artist.map { " by \($0)" } ?? "")) }
        for line in (description ?? "").components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty, out.count < 8, l.contains(/(?i)\bmusic\b|\bsongs?\b|soundtrack|\btrack\s*:|\blicensed\b|\bcompos(?:er|ed)\b|artlist|epidemic sound|musicbed|soundstripe|\u{266A}|\u{266B}|\u{1F3B5}|\u{1F3B6}/) else { continue }
            out.append(l.count > 160 ? String(l.prefix(159)) + "\u{2026}" : l)
        }
        return out
    }

    /// One line for the brief's reference card and the editor's job: "142 shots, 3.1 s each (9 a minute) · 168 words a minute · captions most of the time · −14 LUFS".
    public var summary: String {
        func n(_ v: Double) -> String { String(format: v < 10 ? "%.1f" : "%.0f", v) }
        var parts = ["\(pace.shots) shot\(pace.shots == 1 ? "" : "s"), \(n(pace.averageShot)) s each (\(n(pace.cutsPerMinute)) cuts a minute)"]
        if let w = words, w.count > 0 { parts.append("\(Int(w.perMinute.rounded())) words a minute") }
        if let t = onScreen, t.captions >= 0.2 { parts.append(t.captions >= 0.6 ? "captions most of the time" : "captions some of the time") }
        if let c = sound?.cues?.count, c > 0 { parts.append("\(c) music cue\(c == 1 ? "" : "s")") }
        if let l = sound?.loudness { parts.append("\(l < -0.5 ? "\u{2212}" : "")\(Int(abs(l).rounded())) LUFS") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// What the editor reads beside the contact sheets: the numbers in words, then every shot.
    public var markdown: String {
        func n(_ v: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", v) }
        func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
        func clock(_ t: Double) -> String { String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }
        var out = ["# \(title)", ""]
        out.append([by.map { "By \($0)." }, link.map { "From \($0)." }, "\(clock(seconds)) long\(width.flatMap { w in height.map { ", \(w)\u{00D7}\($0)" } } ?? "")."].compactMap { $0 }.joined(separator: " "))
        out += ["", "Measured by Direction. Use these numbers as they are; judge the rest from the contact sheets and the words.", "", "## Pace"]
        out.append("- \(pace.shots) shots: \(n(pace.averageShot)) s on average, \(n(pace.medianShot)) s at the median, the longest \(n(pace.longestShot)) s; \(n(pace.cutsPerMinute)) cuts a minute.")
        if let f = pace.firstCut { out.append("- The first cut comes at \(n(f)) s.") }
        if !pace.cutsByMinute.isEmpty { out.append("- Cuts in each minute: \(pace.cutsByMinute.map(String.init).joined(separator: ", ")).") }
        if let w = words {
            out += ["", "## Words"]
            out.append("- \(w.count) words, \(Int(w.perMinute.rounded())) a minute.")
            out.append("- Gaps between words: \(n(w.medianPause, 2)) s at the median, the longest \(n(w.longestPause)) s; of the pauses, \(pct(w.pausesOverHalfSecond)) run over half a second.")
        }
        if let s = sound {
            func mmss(_ t: Double) -> String { String(format: "%d:%02d", Int(t.rounded()) / 60, Int(t.rounded()) % 60) }
            func times(_ ts: [Double], _ most: Int = 12) -> String { ts.prefix(most).map(mmss).joined(separator: ", ") + (ts.count > most ? " and \(ts.count - most) more" : "") }
            func db(_ v: Double) -> String { "\(Int(abs(v).rounded())) dB \(v <= 0 ? "under" : "over")" }
            func plural(_ k: Int, _ one: String, _ many: String) -> String { "\(k) \(k == 1 ? one : many)" }
            out += ["", "## Sound"]
            if let l = s.loudness { out.append("- \(n(l)) LUFS integrated\(s.truePeak.map { ", true peak \(n($0)) dBTP" } ?? "").") }
            if let m = s.music { out.append("- Music \(pct(m)) of the time\(s.musicUnderSpeech.map { ", under the speech \(pct($0)) of the time" } ?? "").") }
            if let v = s.musicUnderVoiceDB { out.append("- In the pauses between words the music sits \(db(v)) the voice\(s.musicAloneDB.map { "; with nobody talking it plays \(db($0)) it" } ?? "").") }
            else if let a = s.musicAloneDB { out.append("- With nobody talking the music plays \(db(a)) the voice.") }
            if let k = s.key {
                let outside = (s.cues ?? []).compactMap(\.key).filter { $0 != k }
                out.append("- Across the cues, the notes fit \(k) best\(outside.isEmpty ? "" : "; cues read in another key: \(Array(Set(outside)).sorted().joined(separator: ", "))").")
            }
            if let cues = s.cues, !cues.isEmpty {
                let lengths = cues.map { $0.end - $0.start }
                out.append("- \(plural(cues.count, "music cue", "music cues")), \(mmss(lengths.reduce(0, +) / Double(lengths.count))) on average, the longest \(mmss(lengths.max()!)); \(n(Double(cues.count) / max(1, seconds / 60))) a minute.")
            }
            if let b = s.breaks, !b.isEmpty { out.append("- The music stops for \(plural(b.count, "stretch", "stretches")) of talk, the longest \(mmss(b.map { $0.end - $0.start }.max()!)): at \(times(b.map(\.start), 8)).") }
            if let st = s.stings, !st.isEmpty { out.append("- \(plural(st.count, "short burst", "short bursts")) of music (risers, transitions, hits) at \(times(st)).") }
            if let c = s.cutsHeard, c > 0 { out.append("- Of the \(plural(c, "cut", "cuts")) with music playing and no word starting on them, \(s.hitsOnCuts ?? 0) have a sound starting right on the cut: a hit, or the next shot\u{2019}s own sound.") }
            if let c = s.cutsClearOfTalk, c >= 5 { out.append("- Of the \(plural(c, "cut", "cuts")) with no talk in the two seconds before, the level rises into \(s.risersIntoCuts ?? 0) (a riser). Under the voice a riser can\u{2019}t be told.") }
            if let e = s.effects, !e.isEmpty {
                let kinds = Dictionary(grouping: e, by: \.sound).sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
                out.append("- Other sounds heard (added effects, or the footage\u{2019}s own): " + kinds.map { k, v in "\(k) \(v.count)\(v.contains { $0.onCut == true } ? " (\(v.filter { $0.onCut == true }.count) on a cut)" : "") at \(times(v.map(\.at), 6))" }.joined(separator: "; ") + ".")
            }
            if let cues = s.cues, !cues.isEmpty {
                out += ["", "## Music cues", ""]
                out += cues.enumerated().map { i, c in
                    let parts = [c.instruments.isEmpty ? nil : c.instruments.joined(separator: ", "), c.tempo.map { "about \(Int($0.rounded())) beats a minute" } ?? "no steady beat", c.key,
                                 c.underSpeech >= 0.05 ? "under the voice \(pct(c.underSpeech)) of it" : "no one talking over it", c.startsOnCut == true ? "starts on a cut" : nil, c.endsOnCut == true ? "ends on a cut" : nil].compactMap { $0 }
                    return "\(i + 1). \(mmss(c.start))\u{2013}\(mmss(c.end)) (\(mmss(c.end - c.start))): " + parts.joined(separator: " \u{00B7} ")
                }
                out += ["", "Beats and keys are estimated from the whole mix, voice and all: a beat can read double or half, and a minor key and its relative major (A minor, C major) are easy to confuse. A cue boundary inside continuous music is where its chords changed. Genre isn\u{2019}t measured; name it from these."]
            }
        }
        if let credits = musicCredits, !credits.isEmpty { out += ["", "## Music on the page", "", "As the video\u{2019}s page lists it:"] + credits.map { "- \($0)" } }
        let p = picture
        out += ["", "## Picture"]
        out.append("- Shots by the face: \(pct(p.close)) close, \(pct(p.medium)) medium, \(pct(p.wide)) wide, \(pct(p.noFace)) with no face.")
        out.append("- Cuts between two shots of the same face that change its size: \(pct(p.punchIns)).")
        out.append("- Brightness \(n(p.brightness, 2)), contrast \(n(p.contrast, 2)), saturation \(n(p.saturation, 2)), warmth \(n(p.warmth, 2)) (0 is neutral).")
        if let t = onScreen {
            out += ["", "## Words on screen"]
            out.append("- Captions on \(pct(t.captions)) of the looks (one a second)\(t.wordsPerCaption.map { ", \(n($0)) words at a time" } ?? "")\(t.captionHeight.map { ", centered \(pct($0)) of the way down" } ?? "")\(t.upperCase.map { ", \(pct($0)) of their words in capitals" } ?? "").")
            out.append("- Other text on \(pct(t.otherText)) of the looks.")
        }
        out += ["", "## Shots", ""]
        out += shots.enumerated().map { i, s in "\(i + 1). \(clock(s.start))\u{2013}\(clock(s.end)) (\(n(s.end - s.start)) s)\(s.framing.map { ", \($0)" } ?? "")\(s.text.map { ": \u{201C}\($0)\u{201D}" } ?? "")" }
        return out.joined(separator: "\n") + "\n"
    }

    /// Where a brief reference's study is kept in its film, beside what the editor writes (styles.md › In the brief).
    public static func referenceFolder(_ referenceID: String, film: URL) -> URL { film.appendingPathComponent("Editor/References/\(referenceID)", isDirectory: true) }

    public static func read(in folder: URL) -> VideoStudy? {
        (try? Data(contentsOf: folder.appendingPathComponent(fileName))).flatMap { try? JSONDecoder().decode(VideoStudy.self, from: $0) }
    }
}
