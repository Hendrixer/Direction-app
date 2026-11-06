import Testing
import Foundation
@testable import DirectionCore

struct CaptionsTests {
    func word(_ text: String, _ start: Double, _ end: Double) -> TimelineWord {
        TimelineWord(id: "c:" + text, sourceWordID: text, clipID: "c", assetID: "a", text: text, range: .init(start: start, end: end))
    }

    @Test func aCaptionEndsAtASentenceAPauseOrWhenFull() {
        let words = [word("One", 0, 0.2), word("two.", 0.25, 0.5), word("Three", 0.55, 0.7), word("four", 1.4, 1.6), word("five", 1.65, 1.8), word("six", 1.85, 2), word("seven", 2.05, 2.2)]
        let lines = Captions.lines(words, wordsAtATime: 3, maxCharacters: 42)
        #expect(lines.map(\.text) == ["One two.", "Three", "four five six", "seven"])
        // Each stays up until the next starts, and never flashes.
        #expect(lines[0].end == 0.55 && lines[1].end == 1.35 && lines[3].end - lines[3].start >= 0.8)
        #expect(Captions.lines(words, wordsAtATime: 9, maxCharacters: 12).allSatisfy { $0.text.count <= 12 })
    }

    @Test func stretchesFitAGraphicAndBreakAtAPause() {
        let lines = (0..<60).map { i in Captions.Line(text: "line \(i)", start: Double(i) * 4 + (i >= 20 ? 3 : 0), end: Double(i) * 4 + 3 + (i >= 20 ? 3 : 0)) }
        let stretches = Captions.stretches(lines, limit: 110)
        #expect(stretches.allSatisfy { ($0.last!.end - $0.first!.start) <= 110 } && stretches.flatMap { $0 }.count == 60)
        #expect(stretches[0].last?.text == "line 19")
    }

    @Test func srtIsNumberedAndTimedToTheMillisecond() {
        let srt = Captions.srt([.init(text: "Hello.", start: 1.5, end: 3.25), .init(text: "Bye.", start: 3661, end: 3662)])
        #expect(srt == "1\n00:00:01,500 --> 00:00:03,250\nHello.\n\n2\n01:01:01,000 --> 01:01:02,000\nBye.\n")
    }

    @Test func theLoudnessVerdictSaysWhatsWrong() {
        #expect(LoudnessCheck.verdict(integrated: -14.4, truePeak: -2, target: -14, ceiling: -1) == .onTarget)
        #expect(LoudnessCheck.verdict(integrated: nil, truePeak: -60, target: -14, ceiling: -1) == .silent)
        #expect(LoudnessCheck.verdict(integrated: -19, truePeak: -6, target: -14, ceiling: -1).words == "The mix is \u{2212}19 LUFS, 5 LU under the \u{2212}14 LUFS target.")
        #expect(LoudnessCheck.verdict(integrated: -14, truePeak: 0.4, target: -14, ceiling: -1).isReady == false)
        if case .heldByPeaks = LoudnessCheck.verdict(integrated: -18, truePeak: -1.1, target: -14, ceiling: -1) {} else { Issue.record("peaks at the ceiling hold it") }
        #expect(LoudnessCheck.dBText(3.17) == "+3.2 dB" && LoudnessCheck.lufsText(-14) == "\u{2212}14 LUFS")
    }
}
