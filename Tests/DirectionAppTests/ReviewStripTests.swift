import CoreGraphics
import Testing
@testable import DirectionApp
@testable import DirectionCore

private func stripClip(_ id: String, start: Double, end: Double, layer: Int = 0, kind: ClipKind = .video, speed: Double = 1) -> Clip {
    Clip(id: id, assetID: "asset-" + id, name: id, kind: kind, layer: layer,
         start: .init(seconds: start), sourceRange: .init(start: 0, end: (end - start) * speed), speed: speed)
}

@Suite("Review scene strip")
struct ReviewStripTests {
    @Test func sequentialShotsKeepTheirActualDurationsAndOrder() {
        let short = stripClip("short", start: 0, end: 2)
        let long = stripClip("long", start: 2, end: 8)
        let segments = ReviewStripLayout.segments(clips: [long, short], duration: 8)

        #expect(segments.map(\.clip?.id) == ["short", "long"])
        #expect(segments.map(\.start) == [0, 2])
        #expect(segments.map(\.end) == [2, 8])
        #expect(segments.map(\.number) == [1, 2])
        #expect((segments[0].end - segments[0].start) / 8 == 0.25)
        #expect((segments[1].end - segments[1].start) / 8 == 0.75)
    }

    @Test func aHigherLayerReplacesOnlyItsActualVisibleInterval() {
        let base = stripClip("interview", start: 0, end: 12)
        let overlay = stripClip("cutaway", start: 3, end: 7, layer: 1)
        let segments = ReviewStripLayout.segments(clips: [overlay, base], duration: 12)

        #expect(segments.map(\.clip?.id) == ["interview", "cutaway", "interview"])
        #expect(segments.map(\.start) == [0, 3, 7])
        #expect(segments.map(\.end) == [3, 7, 12])
        #expect(segments.reduce(0) { $0 + $1.end - $1.start } == 12)
    }

    @Test func hiddenLowerLayerBoundariesDoNotInventAdditionalScenes() {
        let first = stripClip("under-a", start: 0, end: 4)
        let second = stripClip("under-b", start: 4, end: 8)
        let covering = stripClip("visible", start: 0, end: 8, layer: 2)
        let segments = ReviewStripLayout.segments(clips: [first, second, covering], duration: 8)

        #expect(segments.count == 1)
        #expect(segments[0].clip?.id == "visible")
        #expect(segments[0].start == 0 && segments[0].end == 8)
    }

    @Test func blackGapsRemainUnnumberedAndAudioAndTitlesDoNotBecomeShots() {
        let video = stripClip("picture", start: 2, end: 4)
        let audio = stripClip("sound", start: 0, end: 8, kind: .audio)
        let title = stripClip("type", start: 0, end: 8, kind: .title)
        let segments = ReviewStripLayout.segments(clips: [title, audio, video], duration: 8)

        #expect(segments.map(\.clip?.id) == [nil, "picture", nil])
        #expect(segments.map(\.number) == [nil, 1, nil])
        #expect(segments.map(\.start) == [0, 2, 4])
        #expect(segments.map(\.end) == [2, 4, 8])
        #expect(ReviewStripLayout.segments(clips: [audio, title], duration: 8).isEmpty)
    }

    @Test func retimedFootageUsesSequenceDurationInsteadOfSourceDuration() {
        let doubleSpeed = stripClip("fast", start: 0, end: 4, speed: 2)
        let ordinary = stripClip("normal", start: 4, end: 8)
        let segments = ReviewStripLayout.segments(clips: [doubleSpeed, ordinary], duration: 8)

        #expect(doubleSpeed.sourceRange.duration.seconds == 8)
        #expect(segments.map(\.start) == [0, 4])
        #expect(segments.map(\.end) == [4, 8])
    }

    @Test func equalLayerTiesFollowTheRendererOrdering() {
        let first = stripClip("a", start: 0, end: 8)
        let last = stripClip("z", start: 0, end: 8)
        let segments = ReviewStripLayout.segments(clips: [last, first], duration: 8)

        #expect(segments.count == 1)
        #expect(segments[0].clip?.id == "z")
    }

    @Test func sourceIntervalsAreClippedToTheDisplayedCut() {
        let overhanging = stripClip("overhang", start: -2, end: 12)
        let segments = ReviewStripLayout.segments(clips: [overhanging], duration: 8)

        #expect(segments.count == 1)
        #expect(segments[0].start == 0 && segments[0].end == 8)
    }

    @Test(arguments: [0.0, -1, Double.nan, Double.infinity])
    func anInvalidOrEmptyDurationHasNoInventedScene(_ duration: Double) {
        let clip = stripClip("picture", start: 0, end: 8)
        #expect(ReviewStripLayout.segments(clips: [clip], duration: duration).isEmpty)
    }

    @Test func pointerMappingUsesTheSameTrueProportionsAndClampsToTheCut() {
        #expect(ReviewStripLayout.time(at: 0, width: 640, duration: 8.72) == 0)
        #expect(abs(ReviewStripLayout.time(at: 160, width: 640, duration: 8.72) - 2.18) < 0.000_001)
        #expect(ReviewStripLayout.time(at: 640, width: 640, duration: 8.72) == 8.72)
        #expect(ReviewStripLayout.time(at: -200, width: 640, duration: 8.72) == 0)
        #expect(ReviewStripLayout.time(at: 900, width: 640, duration: 8.72) == 8.72)
        #expect(ReviewStripLayout.time(at: 50, width: 0, duration: 8.72) == 0)
        #expect(ReviewStripLayout.time(at: .nan, width: 640, duration: 8.72) == 0)
    }
}
