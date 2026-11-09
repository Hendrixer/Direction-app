import Foundation

/// What the editor can make (product-model.md › Made).
public enum MadeKind: String, Codable, CaseIterable, Sendable {
    case music, soundEffect, voice, still, shot, `extension`, bridge, changedShot, slowMotion, upscale
    public var label: String {
        switch self {
        case .music: "Music"; case .soundEffect: "Sound effect"; case .voice: "Voice"; case .still: "Still"; case .shot: "New shot"
        case .extension: "Extended shot"; case .bridge: "Bridge"; case .changedShot: "Changed shot"; case .slowMotion: "Slow motion"; case .upscale: "Sharpened"
        }
    }
    /// The OpenRouter listing its versions come from.
    public var listing: MadeVersion.Listing {
        switch self { case .music, .soundEffect: .audio; case .voice: .speech; case .still: .image; case .shot, .extension, .bridge, .changedShot, .slowMotion, .upscale: .video }
    }
    public var isPicture: Bool { ![.music, .soundEffect, .voice].contains(self) }
    /// Music, effects and new shots are made to a length; voice runs as long as its words; stills have none;
    /// changed shots, slow motion and sharpening follow the range they're made from.
    public var needsSeconds: Bool { [.music, .soundEffect, .shot, .extension, .bridge].contains(self) }
    /// Made from a range of a take (`from: {assetID, start, end}`).
    public var worksOnRange: Bool { [.changedShot, .slowMotion, .upscale].contains(self) }
    /// Made shots that come back from a service and are finished on this Mac (made-media.md › Finishing a made shot).
    public var isMadeShot: Bool { [.shot, .extension, .bridge, .changedShot].contains(self) }
    public var spendKind: SpendKind { SpendKind(rawValue: rawValue)! }
}

/// One OpenRouter version and what its listing says about price and limits.
public struct MadeVersion: Codable, Hashable, Sendable, Identifiable {
    public enum Listing: String, Codable, Sendable { case audio, speech, video, image }
    public var id: String
    public var name: String
    public var listing: Listing
    /// `/models` pricing: dollars per token (prompt, completion, image_output…), per request, or per second.
    public var pricing: [String: String] = [:]
    /// `/videos/models` pricing SKUs: "duration_seconds_with_audio", "cents_per_second_output_1080p"…
    public var skus: [String: String] = [:]
    public var durations: [Int] = []
    public var resolutions: [String] = []
    public var aspectRatios: [String] = []
    public var voices: [String] = []
    /// `/videos/models` `supported_frame_images`: "first_frame", "last_frame".
    public var frames: [String] = []
    /// `/videos/models` lists an `upscale_factor` range.
    public var upscales: Bool = false
    /// `/videos/models` `generate_audio`: whether it can make sound; nil when the list doesn't say.
    public var makesSound: Bool?
    public init(id: String, name: String, listing: Listing, pricing: [String: String] = [:], skus: [String: String] = [:], durations: [Int] = [], resolutions: [String] = [], aspectRatios: [String] = [], voices: [String] = [], frames: [String] = [], upscales: Bool = false, makesSound: Bool? = nil) {
        self.id = id; self.name = name; self.listing = listing; self.pricing = pricing; self.skus = skus; self.durations = durations; self.resolutions = resolutions; self.aspectRatios = aspectRatios; self.voices = voices; self.frames = frames; self.upscales = upscales
        self.makesSound = makesSound
    }

    /// Returns the video it's given, changed (Aleph, FLUX Video Edit): no listed durations or frames, priced by the second out.
    public var changesVideo: Bool { listing == .video && !upscales && (id.contains("aleph") || id.contains("video-edit")) }
    /// Takes a video as a reference: the changing versions, and those with a "with video input" price (Seedance).
    public var takesVideo: Bool { changesVideo || upscales || skus.keys.contains { $0.contains("video_input") } }
    /// A last frame after a first one, as Direction sends it. Hailuo 3 Max lists both but takes one or the other.
    public var takesLastFrame: Bool { frames.contains("last_frame") && !Self.oneFrame.contains(id) }
    /// Takes reference stills (`input_references`) beside its frames.
    public var takesReferences: Bool { !Self.noReferences.contains(id) }
    /// Every price it lists is for a shot with sound (Gemini Omni): it always makes sound and turns down
    /// `generate_audio: false`, so it's never sent.
    public var alwaysMakesSound: Bool {
        let seconds = skus.keys.filter { $0.contains("second") }
        return !seconds.isEmpty && seconds.allSatisfy { $0.contains("with_audio") && !$0.contains("without_audio") }
    }
    /// Seed Audio makes sound effects from a description through the speech list (`POST /audio/speech`).
    public var makesEffects: Bool { id.hasPrefix("bytedance-seed/seed-audio") }

    /// What OpenRouter lists but the version turns down (the paid trials, 8 Nov 2026, docs/speed-and-quality.md):
    /// Hailuo 3 Max "supports a single keyframe image: send either a first_frame or a last_frame, not both",
    /// and its provider "does not support image input references".
    static let oneFrame: Set<String> = ["minimax/hailuo-3-max"]
    static let noReferences: Set<String> = ["minimax/hailuo-3-max"]
    /// Makes new shots: a video version that neither changes nor enlarges what it's given.
    public var makesShots: Bool { listing == .video && !changesVideo && !upscales && !id.hasPrefix("heygen/") }
    /// Runs on this Mac (slow motion, sharpening). Never billed.
    public var isLocal: Bool { id.hasPrefix("local/") }

    /// Apple's frame interpolation and super resolution, on this Mac.
    public static let frameInterpolation = MadeVersion(id: "local/frame-interpolation", name: "This Mac", listing: .video)
    public static let superResolution = MadeVersion(id: "local/super-resolution", name: "This Mac", listing: .video)

    /// "Google: Nano Banana 2 (Gemini 3.1 Flash Image)" → "Nano Banana 2"; "Lyria 3 Clip Preview" → "Lyria 3 Clip".
    /// A name that says nothing on its own keeps its maker: "AssemblyAI: TTS 1" → "AssemblyAI TTS 1".
    public static func displayName(_ listed: String, id: String) -> String {
        var name = listed.isEmpty ? id : listed
        if let colon = name.range(of: ": ") {
            let maker = name[..<colon.lowerBound], rest = String(name[colon.upperBound...])
            name = rest.hasPrefix("TTS") ? "\(maker) \(rest)" : rest
        }
        if let paren = name.range(of: " (") { name = String(name[..<paren.lowerBound]) }
        for suffix in [" Preview", " (free)"] where name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
        return name
    }

    func price(_ key: String) -> Double? { pricing[key].flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } }
}

/// Every version Direction can use, from OpenRouter's model lists, kept for a day.
public struct MadeCatalog: Codable, Sendable, Equatable {
    public var fetchedAt: Double
    public var versions: [MadeVersion]
    public init(fetchedAt: Double, versions: [MadeVersion]) { self.fetchedAt = fetchedAt; self.versions = versions }

    /// The spec's defaults (made-media.md › Services). Voice takes the first speech version listed.
    public static let defaults: [MadeKind: String] = [.music: "google/lyria-3-clip", .soundEffect: "bytedance-seed/seed-audio", .still: "google/gemini-3.1-flash-image",
                                                      .shot: "google/veo-3.1", .extension: "google/veo-3.1", .bridge: "google/veo-3.1", .changedShot: "runway/aleph-2",
                                                      .slowMotion: MadeVersion.frameInterpolation.id, .upscale: MadeVersion.superResolution.id]

    /// The versions that can make a kind: changed shots need a version that changes video, bridges one that takes a last frame.
    public func listed(_ kind: MadeKind) -> [MadeVersion] {
        switch kind {
        case .slowMotion: return [.frameInterpolation]
        case .upscale: return [.superResolution] + versions.filter { $0.listing == .video && $0.upscales }
        case .changedShot: return versions.filter(\.changesVideo)
        case .shot, .extension: return versions.filter(\.makesShots)
        case .bridge: return versions.filter { $0.makesShots && $0.takesLastFrame }
        // Seed Audio is listed with the voices but makes effects; the music versions make them too, as music.
        case .soundEffect: return versions.filter { $0.makesEffects } + versions.filter { $0.listing == .audio }
        case .voice: return versions.filter { $0.listing == .speech && !$0.makesEffects }
        default: return versions.filter { $0.listing == kind.listing }
        }
    }
    /// Versions for a kind, the default first.
    public func choices(_ kind: MadeKind) -> [MadeVersion] {
        let all = listed(kind)
        guard let d = defaultVersion(kind), let i = all.firstIndex(of: d) else { return all }
        var out = all; out.remove(at: i); out.insert(d, at: 0); return out
    }
    /// The listed version matching the default id, or a listed variant of it ("…-clip" → "…-clip-preview").
    public func defaultVersion(_ kind: MadeKind) -> MadeVersion? {
        let all = listed(kind)
        guard let id = Self.defaults[kind] else { return all.first }
        return all.first { $0.id == id } ?? all.first { $0.id.hasPrefix(id + "-") } ?? all.first
    }
    /// The chosen version (Settings › Engines, or the editor's `version`), else the default.
    public func version(_ kind: MadeKind, chosen: String? = nil) -> MadeVersion? {
        let all = listed(kind)
        if let chosen, let v = all.first(where: { $0.id == chosen }) ?? all.first(where: { $0.id.hasPrefix(chosen + "-") }) { return v }
        return defaultVersion(kind)
    }

    /// Enough to estimate and make with the defaults before the lists arrive (or when offline).
    public static let builtIn = MadeCatalog(fetchedAt: 0, versions: [
        MadeVersion(id: "google/lyria-3-clip-preview", name: "Lyria 3 Clip", listing: .audio),
        MadeVersion(id: "openai/gpt-4o-mini-tts-2025-12-15", name: "GPT-4o mini TTS", listing: .speech, pricing: ["prompt": "0.0000006", "completion": "0.000012"], voices: ["alloy"]),
        MadeVersion(id: "bytedance-seed/seed-audio-1-0", name: "Seed Audio 1.0", listing: .speech, pricing: ["prompt": "0", "completion": "0.0025"]),
        MadeVersion(id: "google/veo-3.1", name: "Veo 3.1", listing: .video, skus: ["duration_seconds_with_audio": "0.40", "duration_seconds_without_audio": "0.20", "duration_seconds_with_audio_4k": "0.60", "duration_seconds_without_audio_4k": "0.40"], durations: [4, 6, 8], resolutions: ["720p", "1080p", "4K"], aspectRatios: ["16:9", "9:16"], frames: ["first_frame", "last_frame"]),
        MadeVersion(id: "runway/aleph-2", name: "Aleph 2.0", listing: .video, skus: ["cents_per_second_output": "28", "minimum_cents_per_generation": "56"], aspectRatios: ["16:9", "4:3", "3:2", "1:1", "2:3", "3:4", "9:16", "21:9"]),
        MadeVersion(id: "google/gemini-3.1-flash-image", name: "Nano Banana 2", listing: .image, pricing: ["prompt": "0.0000005", "completion": "0.000003", "image_output": "0.00006"]),
    ])
}

/// The day-long cache in `~/Library/Application Support/Direction/openrouter-models.json`.
public enum MadeVersions {
    /// Tests use `OpenRouter.Overrides.catalog`.
    public static var cacheURL: URL { OpenRouter.overrides.catalog ?? SpendLedger.supportDirectory.appendingPathComponent("openrouter-models.json") }
    public static let maxAge: Double = 86_400

    public static func cached() -> MadeCatalog? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(MadeCatalog.self, from: data)
    }

    /// The cache when it's under a day old, else fresh lists; the stale cache or the built-in list if OpenRouter can't be reached.
    public static func load(refresh: Bool = false, now: Date = Date()) async -> MadeCatalog {
        let cache = cached()
        if !refresh, let cache, now.timeIntervalSince1970 - cache.fetchedAt < maxAge { return cache }
        if let fresh = try? await fetch(now: now) {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder.direction.encode(fresh).write(to: cacheURL, options: .atomic)
            return fresh
        }
        return cache ?? .builtIn
    }

    /// `GET /models?output_modalities=audio|speech|image` and `GET /videos/models`.
    public static func fetch(now: Date = Date()) async throws -> MadeCatalog {
        async let audio = OpenRouter.models(output: "audio")
        async let speech = OpenRouter.models(output: "speech")
        async let image = OpenRouter.models(output: "image")
        async let video = OpenRouter.videoModels()
        var versions: [MadeVersion] = []
        for (listing, models) in [(MadeVersion.Listing.audio, try await audio), (.speech, try await speech), (.image, try await image)] {
            for m in models {
                guard let id = m["id"].string else { continue }
                // The audio listing also holds speech-in-speech-out chat versions; keep the ones that output audio.
                if listing == .audio, !(m["architecture"]["output_modalities"].array?.contains(.string("audio")) ?? true) { continue }
                versions.append(MadeVersion(id: id, name: MadeVersion.displayName(m["name"].string ?? "", id: id), listing: listing, pricing: strings(m["pricing"]), voices: m["supported_voices"].array?.compactMap(\.string) ?? []))
            }
        }
        for m in try await video {
            guard let id = m["id"].string else { continue }
            versions.append(MadeVersion(id: id, name: MadeVersion.displayName(m["name"].string ?? "", id: id), listing: .video, skus: strings(m["pricing_skus"]),
                                        durations: m["supported_durations"].array?.compactMap(\.int) ?? [], resolutions: m["supported_resolutions"].array?.compactMap(\.string) ?? [],
                                        aspectRatios: m["supported_aspect_ratios"].array?.compactMap(\.string) ?? [],
                                        frames: m["supported_frame_images"].array?.compactMap(\.string) ?? [], upscales: m["upscale_factor"] != .null, makesSound: m["generate_audio"].bool))
        }
        guard !versions.isEmpty else { throw DirectionError("no_versions", "OpenRouter listed no versions.") }
        return MadeCatalog(fetchedAt: now.timeIntervalSince1970, versions: versions)
    }

    private static func strings(_ value: JSONValue) -> [String: String] {
        guard case .object(let fields) = value else { return [:] }
        return fields.compactMapValues { $0.string ?? $0.double.map { String($0) } }
    }
}

// MARK: Estimates

/// What a request will cost before it's made, from the version's listed price.
public struct MadeEstimate: Codable, Hashable, Sendable {
    public var spend: Double
    public var seconds: Double?
    /// Requests sent: music longer than a clip is several clips; two ways is twice.
    public var requests: Int
    /// The length each video request asks for (one of the version's durations), and its resolution.
    public var duration: Int?
    public var resolution: String?
    /// False when the listing gave no price and Direction had none of its own.
    public var priced: Bool
}

public enum MadeEstimator {
    /// Lyria 3 Clip makes 30 s clips.
    public static let clipSeconds: Double = 30
    /// Joins between clips of a longer bed.
    public static let crossfade: Double = 0.5
    /// OpenRouter lists Lyria at zero per token; it bills per clip. Prices Direction knows when the listing doesn't say.
    static let perRequest: [String: Double] = ["google/lyria-3-clip": 0.04]
    /// A 1K Nano Banana image is about 1,290 output tokens.
    static let imageTokens: Double = 1_290
    /// Speech-to-speech chat versions bill audio tokens at about ten a second.
    static let audioTokensPerSecond: Double = 10

    public static func clips(for seconds: Double) -> Int {
        seconds <= clipSeconds ? 1 : Int(((seconds - crossfade) / (clipSeconds - crossfade)).rounded(.up))
    }
    static func isClipVersion(_ v: MadeVersion) -> Bool { v.id.contains("lyria") }

    /// - sound: a shot made with its own sound (`generate_audio`). Shots are silent unless asked.
    /// - fromImage: a shot that starts from a frame, priced at the version's image-to-video rate where it has one.
    /// - outputPixels: what sharpening through a service makes, per frame (the cut's size).
    public static func estimate(_ kind: MadeKind, version v: MadeVersion, seconds: Double?, words: String = "", ways: Int = 1, resolution: String? = nil, sound: Bool = false, fromImage: Bool = false, outputPixels: Double? = nil) -> MadeEstimate {
        let ways = max(1, min(kind == .still ? 4 : 2, ways))
        if v.isLocal { return MadeEstimate(spend: 0, seconds: seconds, requests: 0, priced: true) }
        if v.upscales {
            let s = max(1, seconds ?? 5), megapixels = (outputPixels ?? 3840 * 2160) / 1_000_000
            let cents = v.skus["cents_per_megapixel_second_precise"].flatMap(Double.init)
            return MadeEstimate(spend: (cents ?? 0) / 100 * megapixels * s, seconds: s, requests: 1, priced: cents != nil)
        }
        if v.changesVideo {
            // The range goes in and comes back changed, so it's priced by the range's length.
            let s = max(1, seconds ?? 5), per = perSecond(v, resolution: nil, audio: false, fromImage: false)
            var spend = (per ?? 0) * s
            if let minimum = v.skus["minimum_cents_per_generation"].flatMap(Double.init) { spend = max(spend, minimum / 100) }
            return MadeEstimate(spend: spend * Double(ways), seconds: s, requests: ways, priced: per != nil)
        }
        switch kind.listing {
        case .audio:
            let s = max(1, seconds ?? clipSeconds)
            if v.listing == .speech {
                // Seed Audio's effects: billed per second of sound made (under completion).
                let per = (v.price("completion") ?? 0) * s + (v.price("request") ?? 0)
                return MadeEstimate(spend: per * Double(ways), seconds: s, requests: ways, priced: per > 0)
            }
            if isClipVersion(v) {
                let n = clips(for: s)
                let per = v.price("request") ?? perRequest.first { v.id.hasPrefix($0.key) }?.value
                return MadeEstimate(spend: Double(n * ways) * (per ?? 0), seconds: s, requests: n * ways, priced: per != nil)
            }
            let per = (v.price("audio_output") ?? v.price("completion") ?? 0) * audioTokensPerSecond * s + (v.price("request") ?? 0)
            return MadeEstimate(spend: per * Double(ways), seconds: s, requests: ways, priced: per > 0)
        case .speech:
            // Per character of input, or per second of audio (reported under completion) for a few versions.
            let chars = Double(max(1, words.count)), s = seconds ?? chars / 15
            let per = (v.price("prompt") ?? 0) * chars + (v.price("completion") ?? 0) * (v.price("prompt") == nil ? s : 0) + (v.price("request") ?? 0)
            return MadeEstimate(spend: per * Double(ways), seconds: s, requests: ways, priced: per > 0 || v.pricing.values.allSatisfy { Double($0) == 0 })
        case .image:
            let per = v.price("image") ?? v.price("image_output").map { $0 * imageTokens } ?? v.price("completion").map { $0 * imageTokens } ?? 0
            return MadeEstimate(spend: (per + (v.price("request") ?? 0)) * Double(ways), seconds: nil, requests: ways, priced: per > 0)
        case .video:
            let duration = videoDuration(v, seconds: seconds ?? 8), res = resolution ?? videoResolution(v)
            let per = perSecond(v, resolution: res, audio: sound, fromImage: fromImage)
            var spend = (per ?? 0) * Double(duration)
            if let minimum = v.skus["minimum_cents_per_generation"].flatMap(Double.init) { spend = max(spend, minimum / 100) }
            return MadeEstimate(spend: spend * Double(ways), seconds: Double(duration), requests: ways, duration: duration, resolution: res, priced: per != nil)
        }
    }

    /// The shortest listed duration that covers the ask, else the longest.
    public static func videoDuration(_ v: MadeVersion, seconds: Double) -> Int {
        let listed = v.durations.sorted()
        guard !listed.isEmpty else { return max(1, Int(seconds.rounded(.up))) }
        return listed.first { Double($0) >= seconds - 0.001 } ?? listed.last!
    }
    /// 1080p when listed, else the largest listed under it, else the first.
    /// For the film's speed and quality: Best makes 1080p where it can; Faster and Balanced make 720p where it's
    /// listed (else 768p, else the version's default), quicker and for about half, which this Mac sharpens to a
    /// cut half again as tall or more. When this Mac can't sharpen (`sharpensHere` false), the version's default.
    public static func videoResolution(_ v: MadeVersion, quality: FilmQuality, sharpensHere: Bool = true) -> String? {
        guard quality != .best, sharpensHere, v.listing == .video, !v.changesVideo, !v.upscales else { return videoResolution(v) }
        for r in ["720p", "768p"] where v.resolutions.contains(r) { return r }
        return videoResolution(v)
    }
    public static func videoResolution(_ v: MadeVersion) -> String? {
        if v.resolutions.isEmpty || v.resolutions.contains("1080p") { return v.resolutions.isEmpty ? nil : "1080p" }
        let order = ["480p", "720p", "768p", "1080p", "1K", "2K", "4K"]
        return v.resolutions.filter { (order.firstIndex(of: $0) ?? 0) <= 3 }.max { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) } ?? v.resolutions.first
    }

    /// Dollars per second of video from the SKUs, which every version names its own way:
    /// "duration_seconds_with_audio_4k" (dollars), "cents_per_second_output_1080p", "cents_per_video_output_second_720p" (cents),
    /// "per-video-second-1080p". A SKU without a resolution is the default one; the closest match wins.
    public static func perSecond(_ v: MadeVersion, resolution: String?, audio: Bool, fromImage: Bool) -> Double? {
        let res = resolution?.lowercased()
        let resolutions = ["480p", "720p", "768p", "1080p", "1k", "2k", "4k"]
        var best: (score: Int, dollars: Double)?
        for (raw, value) in v.skus {
            guard let amount = Double(value) else { continue }
            let key = raw.lowercased().replacingOccurrences(of: "-", with: "_")
            let cents = key.hasPrefix("cents_")
            guard key.contains("second"), !key.contains("reference"), !key.contains("continuation"), !key.contains("megapixel"), !key.contains("minimum") else { continue }
            let skuRes = resolutions.first { key.hasSuffix("_" + $0) || key.contains("_" + $0 + "_") }
            var score = 0
            if let skuRes { guard skuRes == res else { continue }; score += 4 }
            if key.contains("without_audio") { if audio { score -= 2 } else { score += 2 } }
            else if key.contains("with_audio") { if audio { score += 2 } else { score -= 2 } }
            if key.hasPrefix("image_to_video") { if fromImage { score += 1 } else { continue } }
            if key.hasPrefix("text_to_video") { if fromImage { score -= 1 } else { score += 1 } }
            let dollars = cents ? amount / 100 : amount
            if best == nil || score > best!.score { best = (score, dollars) }
        }
        if let best { return best.dollars }
        // Token-priced versions (Seedance): about width × height × 24 fps / 1024 tokens a second.
        if let perToken = v.skus["video_tokens"].flatMap(Double.init) {
            let pixels: Double = res == "1080p" ? 1920 * 1080 : res == "480p" ? 854 * 480 : 1280 * 720
            return perToken * pixels * 24 / 1024
        }
        return nil
    }
}

public enum MadeFormat {
    /// "$0.40": two decimals, always.
    public static func money(_ dollars: Double) -> String { String(format: "$%.2f", (dollars * 100).rounded() / 100) }
    /// "0:24".
    public static func length(_ seconds: Double) -> String { let s = Int(seconds.rounded()); return "\(s / 60):" + String(format: "%02d", s % 60) }

    /// The Services sub-label for a kind's version: "About $0.04 a 30 s clip", "About $0.40 a second at 1080p".
    /// `resolution`: the one the film's speed and quality makes it at; the version's default otherwise.
    public static func priceLine(_ kind: MadeKind, _ v: MadeVersion, resolution: String? = nil) -> String? {
        switch kind.listing {
        case .audio:
            let e = MadeEstimator.estimate(kind, version: v, seconds: MadeEstimator.clipSeconds)
            guard e.priced, e.spend > 0 else { return nil }
            return MadeEstimator.isClipVersion(v) ? "About \(money(e.spend)) a 30 s clip" : "About \(money(e.spend)) for 30 s"
        case .video:
            if v.isLocal { return "Nothing, on this Mac" }
            let res = v.changesVideo ? nil : resolution ?? MadeEstimator.videoResolution(v)
            guard let per = MadeEstimator.perSecond(v, resolution: res, audio: false, fromImage: false), per > 0 else { return nil }
            return "About \(money(per)) a second" + (res.map { " at \($0)" } ?? "")
        case .speech, .image: return nil
        }
    }
}
