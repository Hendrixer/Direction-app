import Testing
@testable import DirectionApp

@Suite("Gate timecode")
struct TimecodeTests {
    /// Times read the way a video player says them: minutes and seconds, no frames.
    @Test func timesAreMinutesAndSeconds() {
        #expect(Timecode.format(1.5, fps: 24) == "0:01")
        #expect(Timecode.format(72 + 8.0 / 24, fps: 24) == "1:12")
        #expect(Timecode.format(23.0 / 24, fps: 24) == "0:00")
        #expect(Timecode.range(46, 58.5, fps: 24) == "0:46\u{2013}0:58")
    }
    @Test func hoursAppearOnlyWhenNeeded() {
        #expect(Timecode.format(3601.5, fps: 24) == "1:00:01")
        #expect(Timecode.duration(220) == "3:40")
        #expect(Timecode.duration(46) == "0:46")
    }
    /// Go to a time lands where a time reads: past an hour, three parts are hours, minutes and seconds.
    @MainActor @Test func aTimeTypedBackLandsWhereItReads() {
        #expect(FilmActions.parseTimecode(Timecode.format(3723, fps: 24), fps: 24, hours: true) == 3723)
        #expect(FilmActions.parseTimecode("1:12", fps: 24) == 72 && FilmActions.parseTimecode("72", fps: 24) == 72)
        #expect(FilmActions.parseTimecode("00:01:12", fps: 24) == 1.5)
    }
    /// Frames, where they show, say what they are and use the sequence rate.
    @Test func framesSayWhatTheyAre() {
        #expect(Timecode.frame(1.5, fps: 24) == 12 && Timecode.frame(1.5, fps: 30) == 15)
        #expect(Timecode.withFrames(12 + 23.0 / 24, fps: 24) == "0:12 and 23 frames")
        #expect(Timecode.withFrames(12, fps: 24) == "0:12 exactly")
        #expect(Timecode.withFrames(12 + 1.0 / 24, fps: 24) == "0:12 and 1 frame")
        #expect(Timecode.rate(29.97) == 30)
    }
    @Test func frameBoundaryDoesNotRoundIntoNextFrame() {
        #expect(Timecode.frame(29.0 / 30, fps: 30) == 29)
        #expect(Timecode.frame(0.999, fps: 30) == 29)
        #expect(Timecode.format(0.999, fps: 30) == "0:00" && Timecode.format(1, fps: 30) == "0:01")
    }
    @Test func deltasUseATrueMinusSign() {
        #expect(Timecode.delta(-4.2) == "\u{2212}4.2 s")
        #expect(Timecode.delta(1.6) == "+1.6 s")
    }
    @Test func malformedInputDoesNotCrash() {
        #expect(Timecode.format(-1) == "0:00")
        #expect(Timecode.format(.nan) == "\u{2013}:\u{2013}\u{2013}")
        #expect(Timecode.format(1.5, fps: .nan) == "0:01" && Timecode.frame(1.5, fps: .nan) == 12)
        #expect(Timecode.format(.greatestFiniteMagnitude) == "\u{2013}:\u{2013}\u{2013}")
    }
    /// The shape reads as a word, never as a number beside a time.
    @Test func theShapeIsAWord() {
        #expect(ShapeTag.name(9.0 / 16) == "Vertical" && ShapeTag.name(16.0 / 9) == "Wide" && ShapeTag.name(1) == "Square" && ShapeTag.name(0.8) == "Portrait" && ShapeTag.name(2.39) == "Widescreen")
    }
}
