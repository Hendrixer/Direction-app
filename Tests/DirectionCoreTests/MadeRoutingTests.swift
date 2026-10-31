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
    private func ids(_ needs: MadeNeeds, _ q: MadeQuality, refused: Set<String> = []) -> [String] { Self.catalog.route(needs, quality: q, refusedPeople: refused).map(\.id) }
    private let fromFrame = MadeNeeds(kind: .shot, firstFrame: true, seconds: 5)

    @Test func bestIsTheBestRatedThatCanMakeIt() {
        #expect(ids(fromFrame, .best).prefix(3) == ["bytedance/seedance-2.5", "minimax/hailuo-3", "minimax/hailuo-3-max"])
        // Unrated versions only after every rated one.
        let order = ids(fromFrame, .best)
        #expect(order.firstIndex(of: "someone/unrated")! > order.firstIndex(of: "kwaivgi/kling-v3.0-pro")!)
    }

    @Test func aPersonInAFrameSkipsByteDanceAndVersionsThatRefusedOne() {
        var withPerson = fromFrame; withPerson.person = true
        #expect(ids(withPerson, .best).first == "minimax/hailuo-3")
        #expect(!ids(withPerson, .best).contains("bytedance/seedance-2.5"))
        #expect(ids(withPerson, .best, refused: ["minimax/hailuo-3"]).first == "minimax/hailuo-3-max")
        // A refusal for a person doesn't stop a version making shots without one.
        #expect(ids(fromFrame, .best, refused: ["minimax/hailuo-3"]).contains("minimax/hailuo-3"))
    }

    @Test func balancedIsTheCheapestOfTheBestFew() {
        // Within 50 of Seedance 2.5's 1153: Seedance 2.5, H3, H3 Max, Wan 3.0. H3 Max costs least.
        #expect(ids(fromFrame, .balanced).first == "minimax/hailuo-3-max")
        #expect(ids(fromFrame, .balanced).prefix(4).sorted() == ["alibaba/wan-3.0", "bytedance/seedance-2.5", "minimax/hailuo-3", "minimax/hailuo-3-max"])
    }

    @Test func cheapestIsTheCheapestRatedGood() {
        // The unrated one is cheaper still, but not rated good.
        let order = ids(fromFrame, .cheapest)
        #expect(order.first == "minimax/hailuo-3-max" && order[1] == "kwaivgi/kling-v3.0-pro")
        #expect(order.firstIndex(of: "someone/unrated")! > order.firstIndex(of: "bytedance/seedance-2.5")!)
    }

    @Test func versionsThatCantMakeItAreLeftOut() {
        let bridge = MadeNeeds(kind: .bridge, firstFrame: true, lastFrame: true, seconds: 5)
        #expect(!ids(bridge, .best).contains("runway/gen-4.5"))
        let long = MadeNeeds(kind: .shot, firstFrame: true, seconds: 20)
        #expect(ids(long, .best) == ["bytedance/seedance-2.5", "alibaba/wan-3.0"])
        // Music and voice keep Direction's defaults; slow motion is this Mac.
        #expect(MadeCatalog.builtIn.route(MadeNeeds(kind: .music, seconds: 30), quality: .best).map(\.name) == ["Lyria 3 Clip"])
        #expect(MadeCatalog.builtIn.route(MadeNeeds(kind: .slowMotion), quality: .cheapest).first?.isLocal == true)
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
