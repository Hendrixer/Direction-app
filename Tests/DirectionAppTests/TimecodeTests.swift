import Testing
@testable import DirectionApp

@Suite("Gate timecode")
struct TimecodeTests {
    @Test func framesUseTheSequenceRate() {
        #expect(Timecode.format(1.5, fps: 24) == "00:01:12")
        #expect(Timecode.format(1.5, fps: 30) == "00:01:15")
        #expect(Timecode.format(72 + 8.0 / 24, fps: 24) == "01:12:08")
    }
    @Test func hoursAppearOnlyWhenNeeded() {
        #expect(Timecode.format(3601.5, fps: 24) == "1:00:01:12")
        #expect(Timecode.duration(220) == "3:40")
        #expect(Timecode.duration(46) == "0:46")
    }
    @Test func frameBoundaryDoesNotRoundIntoNextFrame() {
        #expect(Timecode.format(29.0 / 30, fps: 30) == "00:00:29")
        #expect(Timecode.format(0.999, fps: 30) == "00:00:29")
        #expect(Timecode.format(1, fps: 30) == "00:01:00")
    }
    @Test func deltasUseATrueMinusSign() {
        #expect(Timecode.delta(-4.2) == "\u{2212}4.2 s")
        #expect(Timecode.delta(1.6) == "+1.6 s")
        #expect(Timecode.range(46, 58.5, fps: 24) == "00:46:00–00:58:12")
    }
    @Test func malformedInputDoesNotCrash() {
        #expect(Timecode.format(-1) == "00:00:00")
        #expect(Timecode.format(.nan) == "--:--:--")
        #expect(Timecode.format(1.5, fps: .nan) == "00:01:12")
        #expect(Timecode.format(.greatestFiniteMagnitude) == "--:--:--")
    }
}
