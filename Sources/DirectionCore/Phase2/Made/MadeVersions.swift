import Foundation

/// What the editor can make (product-model.md › Made).
public enum MadeKind: String, Codable, CaseIterable, Sendable {
    case music, soundEffect, voice, shot, changedShot, still
    public var label: String {
        switch self { case .music: "Music"; case .soundEffect: "Sound effect"; case .voice: "Voice"; case .shot: "New shot"; case .changedShot: "Changed shot"; case .still: "Still" }
    }
    /// The OpenRouter listing its versions come from.
    public var listing: MadeVersion.Listing {
        switch self { case .music, .soundEffect: .audio; case .voice: .speech; case .shot, .changedShot: .video; case .still: .image }
    }
    public var isPicture: Bool { [.shot, .changedShot, .still].contains(self) }
    /// Music, effects and shots are made to a length; voice runs as long as its words; stills have none.
    public var needsSeconds: Bool { [.music, .soundEffect, .shot, .changedShot].contains(self) }
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
    public init(id: String, name: String, listing: Listing, pricing: [String: String] = [:], skus: [String: String] = [:], durations: [Int] = [], resolutions: [String] = [], aspectRatios: [String] = [], voices: [String] = []) {
        self.id = id; self.name = name; self.listing = listing; self.pricing = pricing; self.skus = skus; self.durations = durations; self.resolutions = resolutions; self.aspectRatios = aspectRatios; self.voices = voices
    }

    /// "Google: Nano Banana 2 (Gemini 3.1 Flash Image)" → "Nano Banana 2"; "Lyria 3 Clip Preview" → "Lyria 3 Clip".
    public static func displayName(_ listed: String, id: String) -> String {
        var name = listed.isEmpty ? id : listed
        if let colon = name.range(of: ": ") { name = String(name[colon.upperBound...]) }
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
    public static let defaults: [MadeKind: String] = [.music: "google/lyria-3-clip", .soundEffect: "google/lyria-3-clip", .shot: "google/veo-3.1", .changedShot: "google/veo-3.1", .still: "google/gemini-3.1-flash-image"]

    /// Versions for a kind, the default first.
    public func choices(_ kind: MadeKind) -> [MadeVersion] {
        let all = versions.filter { $0.listing == kind.listing }
        guard let d = defaultVersion(kind), let i = all.firstIndex(of: d) else { return all }
        var out = all; out.remove(at: i); out.insert(d, at: 0); return out
    }
    /// The listed version matching the default id, or a listed variant of it ("…-clip" → "…-clip-preview").
    public func defaultVersion(_ kind: MadeKind) -> MadeVersion? {
        let all = versions.filter { $0.listing == kind.listing }
        guard let id = Self.defaults[kind] else { return all.first }
        return all.first { $0.id == id } ?? all.first { $0.id.hasPrefix(id + "-") } ?? all.first
    }
    /// The chosen version (Settings › Services, or the editor's `version`), else the default.
    public func version(_ kind: MadeKind, chosen: String? = nil) -> MadeVersion? {
        let all = versions.filter { $0.listing == kind.listing }
        if let chosen, let v = all.first(where: { $0.id == chosen }) ?? all.first(where: { $0.id.hasPrefix(chosen + "-") }) { return v }
        return defaultVersion(kind)
    }

    /// Enough to estimate and make with the defaults before the lists arrive (or when offline).
    public static let builtIn = MadeCatalog(fetchedAt: 0, versions: [
        MadeVersion(id: "google/lyria-3-clip-preview", name: "Lyria 3 Clip", listing: .audio),
        MadeVersion(id: "openai/gpt-4o-mini-tts-2025-12-15", name: "GPT-4o mini TTS", listing: .speech, pricing: ["prompt": "0.0000006", "completion": "0.000012"], voices: ["alloy"]),
        MadeVersion(id: "google/veo-3.1", name: "Veo 3.1", listing: .video, skus: ["duration_seconds_with_audio": "0.40", "duration_seconds_without_audio": "0.20", "duration_seconds_with_audio_4k": "0.60", "duration_seconds_without_audio_4k": "0.40"], durations: [4, 6, 8], resolutions: ["720p", "1080p", "4K"], aspectRatios: ["16:9", "9:16"]),
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
                                        aspectRatios: m["supported_aspect_ratios"].array?.compactMap(\.string) ?? []))
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

    public static func estimate(_ kind: MadeKind, version v: MadeVersion, seconds: Double?, words: String = "", ways: Int = 1, resolution: String? = nil) -> MadeEstimate {
        let ways = max(1, min(2, ways))
        switch kind.listing {
        case .audio:
            let s = max(1, seconds ?? clipSeconds)
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
            let per = perSecond(v, resolution: res, audio: true, fromImage: kind == .changedShot)
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
    public static func priceLine(_ kind: MadeKind, _ v: MadeVersion) -> String? {
        switch kind.listing {
        case .audio:
            let e = MadeEstimator.estimate(kind, version: v, seconds: MadeEstimator.clipSeconds)
            guard e.priced, e.spend > 0 else { return nil }
            return MadeEstimator.isClipVersion(v) ? "About \(money(e.spend)) a 30 s clip" : "About \(money(e.spend)) for 30 s"
        case .video:
            let res = MadeEstimator.videoResolution(v)
            guard let per = MadeEstimator.perSecond(v, resolution: res, audio: true, fromImage: false), per > 0 else { return nil }
            return "About \(money(per)) a second" + (res.map { " at \($0)" } ?? "")
        case .speech, .image: return nil
        }
    }
}
