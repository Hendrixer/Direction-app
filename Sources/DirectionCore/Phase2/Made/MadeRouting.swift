import Foundation

// Choosing a version (made-media.md › Choosing a version). The director picks how good against how
// cheap; Direction picks the version for each request from what it needs. Nobody keeps up with the list.

/// Settings › Engines › Made with.
public enum MadeQuality: String, CaseIterable, Codable, Sendable {
    /// The best-rated version that can make it, whatever it costs.
    case best
    /// The cheapest of the versions rated close to the best.
    case balanced
    /// The cheapest version rated good enough.
    case cheapest

    public var label: String { switch self { case .best: "Best"; case .balanced: "Balanced"; case .cheapest: "Cheapest" } }
}

extension SharedSettings {
    public static let madeQualityKey = "madeQuality"
    public static var madeQuality: MadeQuality {
        OpenRouter.overrides.quality ?? defaults.string(forKey: madeQualityKey).flatMap(MadeQuality.init) ?? .balanced
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
    public init(kind: MadeKind, firstFrame: Bool = false, lastFrame: Bool = false, person: Bool = false, seconds: Double? = nil, sound: Bool = false, sharpenHere: Bool = true) {
        self.kind = kind; self.firstFrame = firstFrame; self.lastFrame = lastFrame; self.person = person; self.seconds = seconds; self.sound = sound; self.sharpenHere = sharpenHere
    }
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
    /// Cheapest stops at versions rated this well.
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
    /// frame with a person lately (`refusedPeople`). Music and voice keep Direction's defaults.
    public func route(_ needs: MadeNeeds, quality: MadeQuality, refusedPeople: Set<String> = []) -> [MadeVersion] {
        switch needs.kind {
        case .music, .soundEffect, .voice:
            return defaultVersion(needs.kind).map { [$0] } ?? []
        case .slowMotion:
            return [.frameInterpolation]
        case .upscale:
            let services = versions.filter { $0.listing == .video && $0.upscales }
            return (needs.sharpenHere ? [.superResolution] : []) + services
        default: break
        }
        let fits = listed(needs.kind).filter { v in
            if needs.firstFrame && v.listing == .video && !v.frames.contains("first_frame") { return false }
            if needs.lastFrame && !v.takesLastFrame { return false }
            if needs.person && (MadeRanking.refusesPeople(v) || refusedPeople.contains(v.id)) { return false }
            if needs.kind.listing == .video, !v.changesVideo, let s = needs.seconds, let longest = v.durations.max(), Double(longest) < s - 0.5 { return false }
            return true
        }
        func price(_ v: MadeVersion) -> Double {
            MadeEstimator.estimate(needs.kind, version: v, seconds: needs.seconds ?? 5, sound: needs.sound, fromImage: needs.firstFrame || needs.lastFrame).spend
        }
        let rated = fits.sorted { (MadeRanking.rating($0), -price($0)) > (MadeRanking.rating($1), -price($1)) }
        guard let top = rated.first else { return [] }
        switch quality {
        case .best:
            return rated
        case .balanced:
            let close = rated.filter { MadeRanking.rating($0) >= MadeRanking.rating(top) - MadeRanking.closeToBest }.sorted { price($0) < price($1) }
            return close + rated.filter { !close.contains($0) }
        case .cheapest:
            let good = rated.filter { MadeRanking.rating($0) >= MadeRanking.goodEnough }.sorted { price($0) < price($1) }
            return good + rated.filter { !good.contains($0) }
        }
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
