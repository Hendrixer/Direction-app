import SwiftUI
import DirectionCore

// Watch through, the Cut room's full-screen mode (13–15). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum ScreeningFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "13-screening": { .film(screening(marks: 2, at: SampleFilm.tc(1, 12, 8))) },
            "14-screening-quiet": {
                SnapshotScene(FilmWindow(app: nil, model: screening(marks: 2, at: SampleFilm.tc(1, 10, 21))).environment(\.screeningStartsQuiet, true))
            },
            "15-screening-mark": {
                let m = screening(marks: 3, at: SampleFilm.tc(1, 12, 8))
                m.freshMarkID = "note-3"
                return .film(m)
            },
            // Back from watching through: the marks wait on the sheet as notes to write, the first one open.
            "16-watch-back": {
                let m = screening(marks: 4, at: SampleFilm.tc(2, 40))
                m.endScreening()
                return .film(m)
            },
        ]
    }

    /// Cut 3 playing, watched through. This watch's marks are the drafts at 00:18:04,
    /// 00:46:00, 01:12:08 and 01:43:20 (notes 1–4 before they're written).
    static func screening(marks: Int, at time: Double) -> FilmModel {
        let m = SampleFilm.make(room: .cut)
        m.watchingCut = true
        let times = [SampleFilm.tc(0, 18, 4), SampleFilm.tc(0, 46), SampleFilm.tc(1, 12, 8), SampleFilm.tc(1, 43, 20)]
        m.notes = (1...marks).map { SampleFilm.note($0, "", time: times[$0 - 1], state: .draft) }
        m.screeningMarkIDs = (1...marks).map { "note-\($0)" }
        m.screeningStartedAt = Date()
        m.position = time
        m.playing = true
        return m
    }
}
