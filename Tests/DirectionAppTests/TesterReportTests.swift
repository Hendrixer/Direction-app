import Testing
import Foundation
@testable import DirectionApp
import DirectionCore
import DirectionMedia

/// From a tester's reports of 2026-11-14 (Sentry DIRECTION-4 to -8 and their notes): a lock that asked for a
/// scene that isn't there, a locked picture that said nothing, a style made from a video with no sign of it in
/// Settings, an info file read on the main thread, and a download macOS couldn't open.
@MainActor
struct TesterReportTests {
    /// A shot from a take in no scene has a place on the strip named for its clip; it never gets a lock tile, so
    /// Lock never asks for a scene that isn't there ("Scene not found", DIRECTION-8).
    @Test func onlyScenesGetLockTiles() {
        let strip = [
            StripScene(id: "scene-1", number: 1, title: "Circulatory", start: 0, end: 10, art: .room),
            StripScene(id: "clip-9", number: 2, title: "", start: 10, end: 14, art: .room),
            StripScene(id: "passage-14.0", number: 0, title: "", start: 14, end: 15, art: .room, passage: true),
            StripScene(id: "scene-1", number: 1, title: "Circulatory", start: 15, end: 18, art: .room),
        ]
        let (tiles, time) = LockBar.lockable(strip, scenes: ["scene-1"])
        #expect(tiles.map(\.id) == ["scene-1"])
        #expect(time["scene-1"] == 13 && time["clip-9"] == nil)
        #expect(LockBar.lockable(strip, scenes: []).scenes.isEmpty)
    }

    /// A film whose cut has no scene behind it offers no Lock scenes: only the picture locks.
    @Test func noLockScenesWithoutScenes() {
        let m = ChangesFixtures.cut4()
        #expect(m.hasLockableScenes)
        m.dailies.scenes = []
        #expect(!m.hasLockableScenes)
    }

    /// After picture lock the Cut room's one button goes on to Finish, and a note is refused with the way out
    /// instead of sitting on the sheet with nowhere to go.
    @Test func aLockedPictureSaysWhatToDo() {
        let m = FinishFixtures.finishing()
        m.room = .cut
        #expect(m.cutPrimary?.title == "Go to Finish")
        #expect(m.refusesNotesWhileLocked())
        #expect(m.toast?.title == "Picture is locked" && m.toast?.actionTitle == "Unlock Picture\u{2026}")
        m.toast = nil
        let notes = m.notes.count
        m.beginStretch(); m.beginRegion()
        #expect(!m.drawingStretch && !m.drawingRegion && m.notes.count == notes)
        // Nothing else slips a note in either: an outside note, or a take's sound (its note is how the cut changes).
        m.toast = nil; m.acceptOutside("outside-1"); #expect(m.toast?.title == "Picture is locked")
        m.toast = nil; m.useSyncSound("asset-1"); #expect(m.toast?.title == "Picture is locked" && m.notes.count == notes)
        m.directing.pictureLocked = false; m.toast = nil
        #expect(!m.refusesNotesWhileLocked() && m.toast == nil)
    }

    /// Settings › Styles follows a style from the video to the editor saving it, and says why when it stops.
    @Test func aStyleOnItsWayShowsHowItsGoing() {
        let m = ChangesFixtures.cut4()
        #expect(m.styleProgress == nil)
        m.styleMaking = StyleMaking(videos: [StyleVideo(link: "https://youtu.be/x")], ask: "", name: "Think Media")
        m.learning = "Downloading the video"
        #expect(m.styleProgress == .making(name: "\u{201C}Think Media\u{201D}", step: "Downloading the video"))
        var run = EditorSetup.newRun(.style, on: .claudeCode, quality: .balanced)
        run.state = .working
        m.runs.runs.append(run)
        m.styleMaking?.runID = run.id
        #expect(m.styleProgress == .making(name: "\u{201C}Think Media\u{201D}", step: "The editor is writing it"))
        m.runs.runs[m.runs.runs.count - 1].state = .waitingForYou
        #expect(m.styleProgress == .asks(name: "\u{201C}Think Media\u{201D}"))
        m.runs.runs[m.runs.runs.count - 1].state = .failed
        if case .failed(_, let reason)? = m.styleProgress { #expect(reason.hasPrefix("The editor stopped before saving it")) } else { Issue.record("A stopped run should read as failed") }
        m.runs.runs[m.runs.runs.count - 1].state = .done
        #expect(m.styleProgress == nil)
        m.styleMaking = StyleMaking(videos: [], ask: "", name: "", failed: "The video didn\u{2019}t download.")
        #expect(m.styleProgress == .failed(name: "the video", reason: "The video didn\u{2019}t download."))
    }

    /// Only the fields Direction reads come out of yt-dlp's info file, however many formats it lists.
    @Test func videoInfoReadsOnlyWhatsNeeded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-info-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let formats = (0..<4000).map { i in "{\"format_id\":\"\(i)\",\"fragments\":[{\"url\":\"https://example.com/\(i)\",\"duration\":5.0}],\"http_headers\":{\"Accept\":\"*/*\"}}" }.joined(separator: ",")
        let json = "{\"title\":\"How I edit\",\"channel\":\"Think Media\",\"artists\":[\"A\",\"B\"],\"description\":\"Music: Slow Rooms\",\"webpage_url\":\"https://youtu.be/x\",\"formats\":[\(formats)]}"
        try json.write(to: folder.appendingPathComponent("video.info.json"), atomically: true, encoding: .utf8)
        let info = try #require(VideoInfo.read(in: folder))
        #expect(info.title == "How I edit" && info.channel == "Think Media" && info.artists == ["A", "B"] && info.webpage_url == "https://youtu.be/x")
    }

    /// The download asks for H.264 picture and AAC sound first: AV1 or VP9 with Opus merged into an mp4 is what
    /// YouTube sends otherwise, and AVFoundation can refuse it ("Cannot Open", DIRECTION-5).
    @Test func downloadsPreferWhatEveryMacOpens() {
        let first = TutorialStudy.format.split(separator: "/").first.map(String.init) ?? ""
        #expect(first.contains("vcodec^=avc1") && first.contains("acodec^=mp4a"))
        #expect(TutorialStudy.format.hasSuffix("/b"))
    }

    /// Settings › Engines says an old mlx-vlm needs an update, never that it isn't installed.
    @Test func anOldMLXVLMReadsAsNeedingAnUpdate() {
        var f = MacFacts.preview
        f.downloaded = []; f.mlxVLMTooOld = ["best", "standard", "quick"]; f.mlxVLMUpdate = "uv tool upgrade mlx-vlm"
        let advice = EngineAdvice.advise(f, editor: .yourOwn, installed: [])
        let row = advice.missing.first { $0.name == "mlx-vlm" }
        #expect(row?.label == "mlx-vlm needs an update" && row?.command == "uv tool upgrade mlx-vlm")
    }

    /// Each version names the model type mlx-vlm needs for it, and mlx-vlm's refusal is told apart from other failures.
    @Test func anOldMLXVLMIsToldApart() {
        #expect(SharedSettings.lookDetails.map(\.modelType) == ["qwen2_5_vl", "qwen3_vl", "qwen3_vl_moe"])
        #expect(VisionHelper.outdatedMessage("Qwen3-VL 8B").contains("too old for Qwen3-VL 8B"))
    }
}
