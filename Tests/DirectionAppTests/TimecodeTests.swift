import Testing
@testable import DirectionApp

@Suite("Gate timecode")
struct TimecodeTests {
    @Test func pausedFrameCountsUseSequenceRate() {
        #expect(timecode(1.5, frameRate: 24) == "00:01:12")
        #expect(timecode(1.5, frameRate: 30) == "00:01:15")
        #expect(timecode(60, frameRate: 25) == "01:00:00")
        #expect(timecode(60, frameRate: 30_000.0 / 1001) == "00:59:28")
    }
    @Test func playbackDropsFramesAndHoursAppearWhenNeeded() {
        #expect(timecode(72.9, frames: false) == "01:12")
        #expect(timecode(3601.5, frameRate: 24) == "01:00:01:12")
        #expect(timecode(3601.5, frames: false) == "01:00:01")
    }
    @Test func frameBoundaryDoesNotRoundIntoNextFrame() {
        #expect(timecode(29.0 / 30) == "00:00:29")
        #expect(timecode(0.999) == "00:00:29")
        #expect(timecode(1) == "00:01:00")
    }
    @Test func malformedInputDoesNotCrash() {
        #expect(timecode(-1) == "00:00:00")
        #expect(timecode(.nan) == "00:00:00")
        #expect(timecode(.infinity, frames: false) == "00:00")
        #expect(timecode(1.5, frameRate: .nan) == "00:01:15")
        #expect(timecode(.greatestFiniteMagnitude) == "--:--:--")
    }
}
