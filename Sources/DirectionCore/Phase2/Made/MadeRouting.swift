import Foundation

// Choosing a version (made-media.md › Choosing a version). The director sets the film's speed and quality;
// Direction picks the version for each request from that and what the request needs. Nobody keeps up with the list.

extension FilmQuality {
    /// The film's setting as the made tools read it; tests set `OpenRouter.Overrides.quality`.
    public static func forMade(_ state: DirectingState?) -> FilmQuality {
        OpenRouter.overrides.quality ?? state?.speedAndQuality ?? .balanced
    }
}

/// What one request needs from a version.
public struct MadeNeeds: Sendable, Equatable {
    public var kind: MadeKind
    public var firstFrame = false
    public var lastFrame = false
    /// A frame or reference shows a person (`PeopleCheck`). ByteDance's service refuses those.
    public var person = false
    /// The length asked for; a version must offer at least this much.
    public var seconds: Double?
    public var sound = false
    /// What the picture is sharpened from: this Mac takes up to 1920 × 1080.
    public var sharpenHere = true
    /// A still that must show written words: the ask quotes them (`hasLettering`).
    public var lettering = false
    /// A shot whose ask is mainly a camera move: an orbit, a push in, a crane (`isCameraMove`).
    public var camera = false
    /// Reference stills go with it (`input_references`).
    public var references = false
    public init(kind: MadeKind, firstFrame: Bool = false, lastFrame: Bool = false, person: Bool = false, seconds: Double? = nil, sound: Bool = false, sharpenHere: Bool = true, lettering: Bool = false, camera: Bool = false, references: Bool = false) {
        self.kind = kind; self.firstFrame = firstFrame; self.lastFrame = lastFrame; self.person = person; self.seconds = seconds; self.sound = sound; self.sharpenHere = sharpenHere
        self.lettering = lettering; self.camera = camera; self.references = references
    }

    /// Words in quotes, "OPEN" or “Grand Opening”: the picture has to spell them. An opening quote follows a
    /// space or the start, and the words start right after it, so inch marks (12" and 7") aren't words.
    public static func hasLettering(_ ask: String) -> Bool {
        ask.range(of: #"(^|[\s(:\x{2014}\x{2013}-])["\x{201C}](?=\S)[^"\x{201C}\x{201D}\n]*\p{L}[^"\x{201C}\x{201D}\n]*["\x{201D}]"#, options: .regularExpression) != nil
    }
    /// The move is the shot: versions differ most at camera control.
    public static func isCameraMove(_ ask: String) -> Bool {
        let a = ask.lowercased()
        return ["orbits", "orbiting", "orbit around", "orbit shot", "slow orbit", "circles around", "circling around", "arc around", "arcs around",
                "dolly in", "dolly out", "dolly shot", "dollies", "push in", "push-in", "pushes in", "pull out", "pull-out", "pulls out", "pull back", "pulls back",
                "crane shot", "crane up", "crane down", "cranes up", "cranes down", "tracking shot", "tracks with", "pan across", "pans across", "whip pan",
                "tilt up", "tilts up", "tilt down", "tilts down", "fly-through", "flies through", "fpv", "zoom out from", "zooms out"].contains { a.contains($0) }
    }
}

/// What the research picked for each kind of request at each stop (docs/speed-and-quality.md › Made
/// picture and sound), from the Artificial Analysis and LMArena arenas and OpenRouter's prices and times,
/// read 8 Nov 2026. These are tried first, in order; one that can't make the request (a person ByteDance
/// won't take, no last frame, too short, gone from the list) is skipped, and the ratings order the rest.
public enum MadePicks {
    public static let readOn = "2026-11-08"

    static let h3Max = "minimax/hailuo-3-max", h3 = "minimax/hailuo-3", wan = "alibaba/wan-3.0", omni = "google/gemini-omni-1.2-flash", seedance = "bytedance/seedance-2.5"
    static let kling = "kwaivgi/kling-v3.0-pro"
    static let flare = "openai/gpt-image-2.6-flare", sunburst = "openai/gpt-image-2.6-sunburst", sunburst25 = "openai/gpt-image-2.5-sunburst", nanoBanana = "google/gemini-nano-banana-2.1"
    static let aleph = "runway/aleph-2", fluxEdit = "black-forest-labs/flux-video-edit"

    public static func preferred(_ n: MadeNeeds, _ q: FilmQuality) -> [String] {
        switch n.kind {
        case .still:
            // Words: GPT Image leads every text-rendering board. Otherwise reference fidelity and multi-image edits.
            if n.lettering { return q == .best ? [sunburst, flare] : [flare, sunburst] }
            switch q {
            case .fastest, .faster: return [flare, nanoBanana]
            case .balanced: return [nanoBanana, flare]
            case .best: return [sunburst25, sunburst, flare]
            }
        case .shot, .extension:
            if n.sound {
                // Hailuo 3 Max makes no sound. Seedance's dialogue rates best; H3's sound sync is next.
                switch q {
                case .fastest, .faster: return [omni, wan]
                case .balanced: return [wan, omni]
                case .best: return [seedance, h3, wan]
                }
            }
            if n.kind == .shot && !n.firstFrame && !n.lastFrame {
                switch q {
                case .fastest, .faster: return [h3Max]
                case .balanced: return [omni, h3Max]
                case .best: return [wan, omni]
                }
            }
            if n.camera { return q == .best ? [seedance, h3Max] : [h3Max] }
            switch q {
            case .fastest, .faster: return [h3Max]
            // With a person, Wan 3.0 draws people best of the versions that take them.
            case .balanced: return n.person ? [wan, h3Max] : [h3Max]
            case .best: return [seedance, wan, h3Max]
            }
        case .bridge:
            // No board measures first-to-last frames, so the paid trials did (8 Nov 2026): Hailuo 3 Max takes only one
            // of the two frames; Kling 3.0 Pro showed what made the change (the headphones put on by hand) where Wan 3.0
            // let them appear, but took four minutes to Wan's two and cost a third more.
            switch q {
            case .fastest, .faster: return [wan, kling]
            case .balanced: return [kling, wan]
            case .best: return [seedance, kling, wan]
            }
        case .changedShot:
            // Gemini Omni and Hailuo 3 rate above Aleph at changing video, but neither is proven with a real
            // take of a person through OpenRouter yet (docs/speed-and-quality.md › Still to test).
            return q == .best ? [aleph] : [fluxEdit, aleph]
        case .voice:
            // Eleven v4 rates best for speech; Turbo is its quick one. (Fish Audio's Drama 3 lists no voices to pick.)
            return q == .best ? ["elevenlabs/eleven-v4", "elevenlabs/eleven-v4-turbo"] : ["elevenlabs/eleven-v4-turbo", "elevenlabs/eleven-v4"]
        default:
            return []
        }
    }

    /// Never used for the need: Hailuo 3's camera control rates far below the rest (its orbits failed).
    public static func avoided(_ n: MadeNeeds) -> Set<String> { n.camera ? [h3] : [] }
}

/// How good each version is, from blind comparisons people voted on.
public enum MadeRanking {
    /// Artificial Analysis arenas, read 31 Oct 2026. Shots: image to video (AA-Video-I2V v2.1, Kling 3.0
    /// 1080p Pro is the 1000 anchor). Stills: image editing. Changed shots have no arena: Aleph 2.0 is the
    /// one the spec was built on, FLUX Video Edit the cheaper one. Versions not here count as `unrated`,
    /// so they're used only when nothing rated can make the request.
    public static let ratings: [String: Double] = [
        // Shots
        "bytedance/seedance-2.5": 1153, "bytedance/seedance-2.0": 1136, "minimax/hailuo-3": 1128, "minimax/hailuo-3-max": 1117,
        "alibaba/wan-3.0-prime": 1111, "alibaba/wan-3.0": 1111, "black-forest-labs/flux-3-video": 1071, "x-ai/grok-imagine-video-1.5": 1052,
        "alibaba/happyhorse-1.1": 1037, "alibaba/happyhorse-1.0": 1027, "kwaivgi/kling-v3.0-pro": 1000, "x-ai/grok-imagine-video-1.5-lite": 999,
        // Stills
        "openai/gpt-image-2.5-sunburst": 1199, "openai/gpt-image-2.5-flare": 1181, "google/gemini-nano-banana-2.1": 1152, "microsoft/mai-image-2.6": 1151,
        "x-ai/grok-imagine-image-2.0": 1110,
        // Changed shots
        "runway/aleph-2": 1050, "black-forest-labs/flux-video-edit": 1000,
    ]
    public static let unrated: Double = 900
    /// Past its picks, Faster takes the cheapest version rated this well.
    public static let goodEnough: Double = 1000
    /// Balanced takes the cheapest version within this of the best one that can make the request.
    public static let closeToBest: Double = 50

    public static func rating(_ v: MadeVersion) -> Double { ratings[v.id] ?? (v.isLocal ? 1000 : unrated) }

    /// ByteDance's service checks every input image and refuses any that may show a real person
    /// ("InputImageSensitiveContentDetected.PrivacyInformation") unless that person was registered with them.
    public static func refusesPeople(_ v: MadeVersion) -> Bool { v.id.hasPrefix("bytedance/") || v.id.hasPrefix("bytedance-seed/") }
}

extension MadeCatalog {
    /// The versions to try for a request, in order. Those that can't make it are left out: frames they
    /// don't take, a length they don't offer, a person ByteDance won't take, or a version that refused a
    /// frame with a person lately (`refusedPeople`). Music keeps Direction's default, sound effects go to Seed Audio, and a voice is the stop's pick.
    public func route(_ needs: MadeNeeds, quality: FilmQuality, refusedPeople: Set<String> = []) -> [MadeVersion] {
        let picks = MadePicks.preferred(needs, quality)
        switch needs.kind {
        case .music:
            return defaultVersion(.music).map { [$0] } ?? []
        case .soundEffect:
            // Seed Audio makes the effect itself; Lyria makes music about it, so it's only there for an ask
            // Seed Audio turns down (the paid trials, 8 Nov 2026).
            let seed = versions.first(where: \.makesEffects), lyria = defaultVersion(.music)
            return [seed, lyria].compactMap { $0 }
        case .voice:
            // The pick for the stop, then Direction's default: never whichever voice OpenRouter happens to list first.
            let listed = listed(.voice)
            let picked = picks.compactMap { id in listed.first { $0.id == id } }
            return picked + (defaultVersion(.voice).map { d in picked.contains(d) ? [] : [d] } ?? [])
        case .slowMotion:
            return [.frameInterpolation]
        case .upscale:
            let services = versions.filter { $0.listing == .video && $0.upscales }
            return (needs.sharpenHere ? [.superResolution] : []) + services
        default: break
        }
        let avoided = MadePicks.avoided(needs)
        let fits = listed(needs.kind).filter { v in
            if needs.firstFrame && v.listing == .video && !v.frames.contains("first_frame") { return false }
            if needs.lastFrame && !v.takesLastFrame { return false }
            if needs.references && !v.takesReferences { return false }
            if needs.references && (needs.firstFrame || needs.lastFrame) && !v.takesReferencesWithFrames { return false }
            if needs.person && (MadeRanking.refusesPeople(v) || refusedPeople.contains(v.id)) { return false }
            if needs.kind.listing == .video, !v.changesVideo, let s = needs.seconds, let longest = v.durations.max(), Double(longest) < s - 0.5 { return false }
            // Sound asked for: a version the list says makes none would come back silent.
            if needs.sound && v.makesSound == false { return false }
            return !avoided.contains(v.id)
        }
        func estimate(_ v: MadeVersion) -> MadeEstimate {
            MadeEstimator.estimate(needs.kind, version: v, seconds: needs.seconds ?? 5, resolution: MadeEstimator.videoResolution(v, quality: quality), sound: needs.sound, fromImage: needs.firstFrame || needs.lastFrame)
        }
        func price(_ v: MadeVersion) -> Double { estimate(v).spend }
        let rated = fits.sorted { (MadeRanking.rating($0), -price($0)) > (MadeRanking.rating($1), -price($1)) }
        guard let top = rated.first else { return [] }
        let ordered: [MadeVersion]
        switch quality {
        case .best:
            ordered = rated
        case .balanced:
            let close = rated.filter { MadeRanking.rating($0) >= MadeRanking.rating(top) - MadeRanking.closeToBest }.sorted { price($0) < price($1) }
            ordered = close + rated.filter { !close.contains($0) }
        case .fastest, .faster:
            // Past the picks, the cheaper versions rated good enough: they're the quick ones too.
            let good = rated.filter { MadeRanking.rating($0) >= MadeRanking.goodEnough }.sorted { price($0) < price($1) }
            ordered = good + rated.filter { !good.contains($0) }
        }
        // A version with no listed price would look free; it comes after every priced one, picked or not.
        let priced = ordered.filter { estimate($0).priced }
        // The research's picks for the stop come first, in their order.
        let picked = picks.compactMap { id in priced.first { $0.id == id } }
        return picked + priced.filter { !picked.contains($0) } + ordered.filter { !priced.contains($0) }
    }
}

/// Versions that refused a frame because it showed a person, so later requests with a person skip them.
/// Kept on this Mac for a week, beside the spend ledger.
public enum MadeRefusals {
    static let keep: TimeInterval = 7 * 86_400
    static var url: URL { OpenRouter.overrides.refusals ?? SpendLedger.supportDirectory.appendingPathComponent("made-refusals.json") }
    private static let lock = NSLock()

    public static func refusedPeople(now: Date = Date()) -> Set<String> {
        lock.withLock { Set(read().filter { now.timeIntervalSince1970 - $0.value < keep }.keys) }
    }
    public static func record(_ versionID: String, now: Date = Date()) {
        lock.withLock {
            var all = read().filter { now.timeIntervalSince1970 - $0.value < keep }
            all[versionID] = now.timeIntervalSince1970
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(all).write(to: url, options: .atomic)
        }
    }
    private static func read() -> [String: Double] { (try? JSONDecoder().decode([String: Double].self, from: Data(contentsOf: url))) ?? [:] }

    /// A service turning a request down for what's in it (a person, a policy), rather than failing.
    /// Another version may take it.
    public static func isRefusal(_ error: Error) -> Bool {
        guard let e = error as? DirectionError, e.code == "openrouter_error" else { return false }
        let m = e.message.lowercased()
        return ["sensitive", "real person", "privacy", "moderation", "moderated", "safety", "policy", "prohibited", "not permitted", "inappropriate", "flagged"].contains { m.contains($0) }
    }
}
