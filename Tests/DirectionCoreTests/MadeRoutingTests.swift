import Testing
import Foundation
@testable import DirectionCore

/// Direction picks each request's version (made-media.md › Choosing a version).
struct MadeRoutingTests {
    /// Shot versions as OpenRouter listed them on 30 Oct 2026, prices simplified to dollars a second.
    static let catalog = MadeCatalog(fetchedAt: 0, versions: [
        MadeVersion(id: "bytedance/seedance-2.5", name: "Seedance 2.5", listing: .video, skus: ["duration_seconds": "0.23"], durations: Array(4...30), resolutions: ["720p"], frames: ["first_frame", "last_frame"]),
        MadeVersion(id: "minimax/hailuo-3", name: "H3", listing: .video, skus: ["duration_seconds": "0.13"], durations: Array(5...15), resolutions: ["2K"], frames: ["first_frame", "last_frame"]),
        MadeVersion(id: "minimax/hailuo-3-max", name: "H3 Max", listing: .video, skus: ["duration_seconds_768p": "0.08"], durations: Array(5...15), resolutions: ["768p"], frames: ["first_frame", "last_frame"]),
        MadeVersion(id: "alibaba/wan-3.0", name: "Wan 3.0", listing: .video, skus: ["duration_seconds_1080p": "0.2"], durations: Array(2...30), resolutions: ["1080p"], frames: ["first_frame", "last_frame"]),
        MadeVersion(id: "kwaivgi/kling-v3.0-pro", name: "Kling 3.0 Pro", listing: .video, skus: ["duration_seconds": "0.11"], durations: Array(3...15), resolutions: ["720p"], frames: ["first_frame", "last_frame"]),
        MadeVersion(id: "runway/gen-4.5", name: "Gen-4.5", listing: .video, skus: ["cents_per_second_output": "12"], durations: Array(2...10), resolutions: ["720p"], frames: ["first_frame"]),
        MadeVersion(id: "someone/unrated", name: "Unrated", listing: .video, skus: ["duration_seconds": "0.01"], durations: Array(2...10), resolutions: ["720p"], frames: ["first_frame", "last_frame"]),
    ])
    private func ids(_ needs: MadeNeeds, _ q: FilmQuality, refused: Set<String> = [], in catalog: MadeCatalog = Self.catalog) -> [String] { catalog.route(needs, quality: q, refusedPeople: refused).map(\.id) }
    private let fromFrame = MadeNeeds(kind: .shot, firstFrame: true, seconds: 5)

    /// Best: the research's picks first (Seedance 2.5, then Wan 3.0 for people), then the best rated.
    @Test func bestStartsWithThePicksThenTheBestRated() {
        #expect(ids(fromFrame, .best).prefix(4) == ["bytedance/seedance-2.5", "alibaba/wan-3.0", "minimax/hailuo-3-max", "minimax/hailuo-3"])
        // Unrated versions only after every rated one.
        let order = ids(fromFrame, .best)
        #expect(order.firstIndex(of: "someone/unrated")! > order.firstIndex(of: "kwaivgi/kling-v3.0-pro")!)
    }

    @Test func aPersonInAFrameSkipsByteDanceAndVersionsThatRefusedOne() {
        var withPerson = fromFrame; withPerson.person = true
        // Wan 3.0 draws people best of the versions that take them.
        #expect(ids(withPerson, .best).first == "alibaba/wan-3.0" && ids(withPerson, .balanced).first == "alibaba/wan-3.0")
        #expect(!ids(withPerson, .best).contains("bytedance/seedance-2.5"))
        #expect(ids(withPerson, .best, refused: ["alibaba/wan-3.0"]).first == "minimax/hailuo-3-max")
        // A refusal for a person doesn't stop a version making shots without one.
        #expect(ids(fromFrame, .best, refused: ["alibaba/wan-3.0"]).contains("alibaba/wan-3.0"))
    }

    /// Faster and Balanced start with Hailuo 3 Max: rated close to the best, quickest by far, and cheap.
    @Test func fasterAndBalancedStartWithTheQuickOne() {
        #expect(ids(fromFrame, .faster).first == "minimax/hailuo-3-max" && ids(fromFrame, .balanced).first == "minimax/hailuo-3-max")
        // Past the picks, Balanced is the cheapest of the best few and Faster the cheapest rated good.
        #expect(ids(fromFrame, .balanced)[1] == "minimax/hailuo-3")
        let faster = ids(fromFrame, .faster)
        #expect(faster[1] == "kwaivgi/kling-v3.0-pro" && faster.firstIndex(of: "someone/unrated")! > faster.firstIndex(of: "bytedance/seedance-2.5")!)
    }

    /// A camera move never goes to Hailuo 3, whose orbits failed; Best takes Seedance's camera control.
    @Test func aCameraMoveSkipsHailuo3() {
        var orbit = fromFrame; orbit.camera = true
        for q in FilmQuality.allCases { #expect(!ids(orbit, q).contains("minimax/hailuo-3"), "\(q)") }
        #expect(ids(orbit, .best).first == "bytedance/seedance-2.5")
        orbit.person = true
        #expect(ids(orbit, .best).first == "minimax/hailuo-3-max")
        #expect(MadeNeeds.isCameraMove("Slow orbit around the desk at dusk") && MadeNeeds.isCameraMove("The camera pushes in on the screen") && MadeNeeds.isCameraMove("A crane shot rising over the roof"))
        #expect(!MadeNeeds.isCameraMove("Hands typing on a keyboard") && !MadeNeeds.isCameraMove("A crane wading in the shallows") && !MadeNeeds.isCameraMove("Dolly Parton on the radio") && !MadeNeeds.isCameraMove("A satellite in orbit"))
    }

    /// Sound asked for: a version the list says makes none is left out.
    @Test func soundSkipsVersionsThatMakeNone() {
        var catalog = Self.catalog
        let i = catalog.versions.firstIndex { $0.id == "minimax/hailuo-3-max" }!
        catalog.versions[i].makesSound = false
        var withSound = fromFrame; withSound.sound = true
        #expect(!ids(withSound, .faster, in: catalog).contains("minimax/hailuo-3-max"))
        #expect(ids(fromFrame, .faster, in: catalog).first == "minimax/hailuo-3-max")
    }

    /// Stills: words go to GPT Image, which spells best; otherwise the stop's pick for keeping a frame.
    @Test func stillsFollowWhatTheyNeed() {
        let stills = MadeCatalog(fetchedAt: 0, versions: [
            MadeVersion(id: "openai/gpt-image-2.6-flare", name: "GPT Image 2.6 Flare", listing: .image, pricing: ["image": "0.21"]),
            MadeVersion(id: "openai/gpt-image-2.6-sunburst", name: "GPT Image 2.6 Sunburst", listing: .image, pricing: ["image": "0.21"]),
            MadeVersion(id: "openai/gpt-image-2.5-sunburst", name: "GPT Image 2.5 Sunburst", listing: .image, pricing: ["image": "0.21"]),
            MadeVersion(id: "google/gemini-nano-banana-2.1", name: "Nano Banana 2.1", listing: .image, pricing: ["image": "0.034"]),
        ])
        let sign = MadeNeeds(kind: .still, lettering: true), plain = MadeNeeds(kind: .still)
        #expect(ids(sign, .balanced, in: stills).first == "openai/gpt-image-2.6-flare" && ids(sign, .best, in: stills).first == "openai/gpt-image-2.6-sunburst")
        #expect(ids(plain, .faster, in: stills).first == "openai/gpt-image-2.6-flare")
        #expect(ids(plain, .balanced, in: stills).first == "google/gemini-nano-banana-2.1")
        #expect(ids(plain, .best, in: stills).first == "openai/gpt-image-2.5-sunburst")
        #expect(MadeNeeds.hasLettering(#"A shop sign that says "OPEN" in red neon"#) && MadeNeeds.hasLettering("A poster reading \u{201C}Grand Opening\u{201D}"))
        #expect(MadeNeeds.hasLettering(#""OPEN" glowing on the door"#) && MadeNeeds.hasLettering(#"A banner reading: "Day 1""#))
        #expect(!MadeNeeds.hasLettering("A quiet street at dusk") && !MadeNeeds.hasLettering(#"A "   " blank"#) && !MadeNeeds.hasLettering(#"A 12" vinyl and a 7" single on the shelf"#))
    }

    /// A voice is the stop's pick, never whichever OpenRouter happens to list first.
    @Test func aVoiceIsTheStopsPick() {
        let voices = MadeCatalog(fetchedAt: 0, versions: [
            MadeVersion(id: "assemblyai/assemblyai-tts-1", name: "AssemblyAI TTS 1", listing: .speech, voices: ["aai-jane"]),
            MadeVersion(id: "fish-audio/drama-3", name: "Drama 3", listing: .speech, voices: ["narrator"]),
            MadeVersion(id: "elevenlabs/eleven-v4-turbo", name: "Eleven v4 Turbo", listing: .speech, voices: ["rachel"]),
            MadeVersion(id: "elevenlabs/eleven-v4", name: "Eleven v4", listing: .speech, voices: ["rachel"]),
        ])
        let voice = MadeNeeds(kind: .voice)
        #expect(FilmQuality.allCases.map { ids(voice, $0, in: voices).first } == ["elevenlabs/eleven-v4-turbo", "elevenlabs/eleven-v4-turbo", "elevenlabs/eleven-v4"])
        // Gone from the list: the first one listed, as before.
        #expect(ids(voice, .best, in: MadeCatalog(fetchedAt: 0, versions: [voices.versions[0]])) == ["assemblyai/assemblyai-tts-1"])
    }

    /// Best makes 1080p where a version can; Faster and Balanced make 720p, which this Mac sharpens.
    @Test func theResolutionFollowsTheStop() {
        let wan = MadeVersion(id: "alibaba/wan-3.0", name: "Wan 3.0", listing: .video, skus: ["duration_seconds_720p": "0.1", "duration_seconds_1080p": "0.2"], durations: Array(2...30), resolutions: ["480p", "720p", "1080p"])
        #expect(MadeEstimator.videoResolution(wan, quality: .best) == "1080p" && MadeEstimator.videoResolution(wan, quality: .balanced) == "720p")
        let fiveSeconds = { (q: FilmQuality) in MadeEstimator.estimate(.shot, version: wan, seconds: 5, resolution: MadeEstimator.videoResolution(wan, quality: q)).spend }
        #expect(abs(fiveSeconds(.faster) - 0.5) < 0.001 && abs(fiveSeconds(.best) - 1.0) < 0.001)
        let maxV = MadeVersion(id: "minimax/hailuo-3-max", name: "H3 Max", listing: .video, resolutions: ["768p", "480p"])
        #expect(MadeEstimator.videoResolution(maxV, quality: .faster) == "768p" && MadeEstimator.videoResolution(maxV, quality: .best) == "768p")
    }

    /// A version with no listed price would look free, so it comes after every priced one, even a pick.
    @Test func versionsWithNoListedPriceComeAfterEveryPricedOne() {
        var catalog = Self.catalog
        let i = catalog.versions.firstIndex { $0.id == "minimax/hailuo-3-max" }!
        catalog.versions[i].skus = [:]
        for q in FilmQuality.allCases {
            let order = catalog.route(fromFrame, quality: q).map(\.id)
            #expect(order.last == "minimax/hailuo-3-max", "\(q): \(order)")
            #expect(order.count == Self.catalog.route(fromFrame, quality: q).count)
        }
        #expect(catalog.route(fromFrame, quality: .balanced).first?.id == "minimax/hailuo-3")
        #expect(catalog.route(fromFrame, quality: .faster).first?.id == "kwaivgi/kling-v3.0-pro")
    }

    @Test func versionsThatCantMakeItAreLeftOut() {
        let bridge = MadeNeeds(kind: .bridge, firstFrame: true, lastFrame: true, seconds: 5)
        #expect(!ids(bridge, .best).contains("runway/gen-4.5"))
        let long = MadeNeeds(kind: .shot, firstFrame: true, seconds: 20)
        #expect(ids(long, .best) == ["bytedance/seedance-2.5", "alibaba/wan-3.0"])
        // Music keeps Direction's default; slow motion is this Mac.
        #expect(MadeCatalog.builtIn.route(MadeNeeds(kind: .music, seconds: 30), quality: .best).map(\.name) == ["Lyria 3 Clip"])
        #expect(MadeCatalog.builtIn.route(MadeNeeds(kind: .slowMotion), quality: .faster).first?.isLocal == true)
        // Sharpening goes to a service only when this Mac can't take the size.
        var big = MadeNeeds(kind: .upscale); big.sharpenHere = false
        #expect(MadeCatalog.builtIn.route(big, quality: .best).allSatisfy { !$0.isLocal })
    }

    @Test func refusalsAreToldFromFailures() {
        let bytedance = DirectionError("openrouter_error", #"OpenRouter said: HTTP 400: {"error":{"code":"InputImageSensitiveContentDetected.PrivacyInformation","message":"The request failed because the input image 'content[1]' may contain real person."}} (400)"#)
        #expect(MadeRefusals.isRefusal(bytedance))
        #expect(!MadeRefusals.isRefusal(DirectionError("openrouter_error", "OpenRouter said: A last_frame image must be paired with a first_frame image (400)")))
        #expect(!MadeRefusals.isRefusal(DirectionError("openrouter_credits", "OpenRouter said: Insufficient credits (402)")))
    }

    @Test func refusalsAreKeptForAWeek() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("refusals-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try OpenRouter.$overrides.withValue(OpenRouter.Overrides(refusals: file)) {
            let then = Date(timeIntervalSince1970: 1_793_000_000)
            MadeRefusals.record("minimax/hailuo-3", now: then)
            #expect(MadeRefusals.refusedPeople(now: then.addingTimeInterval(86_400)) == ["minimax/hailuo-3"])
            #expect(MadeRefusals.refusedPeople(now: then.addingTimeInterval(8 * 86_400)).isEmpty)
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }
}
