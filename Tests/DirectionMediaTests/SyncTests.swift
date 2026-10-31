import Testing
import Foundation
import DirectionCore
import DirectionMedia
import DirectionTools

/// Sync by sound (footage-index.md › Sync).
struct SyncTests {
    /// Speech-like loudness: bursts of a few hundred milliseconds with quiet between.
    static func speech(seconds: Double, seed: UInt64) -> [Float] {
        var rng = SplitMix(seed: seed), out: [Float] = []
        while Double(out.count) < seconds * SoundSync.rate {
            let loud = rng.next() % 3 != 0, n = 8 + Int(rng.next() % 30)
            out += (0..<n).map { _ in loud ? 0.3 + Float(rng.next() % 1000) / 1500 : Float(rng.next() % 1000) / 20_000 }
        }
        return Array(out.prefix(Int(seconds * SoundSync.rate)))
    }

    @Test func aRecordingStartedLaterIsFoundOnTheOthersClock() throws {
        let a = Self.speech(seconds: 60, seed: 1)
        // b started 3.27 s into a and ran 40 s, with its own hiss.
        var rng = SplitMix(seed: 9)
        let b = a[327..<4327].map { $0 * 0.6 + Float(rng.next() % 1000) / 40_000 }
        let m = try #require(SoundSync.match(Self.standardized(a), Self.standardized(Array(b))))
        #expect(abs(m.offset - 3.27) < 0.011, "offset \(m.offset)")
        #expect(m.match > 0.9 && m.isSameMoment && abs(m.overlap - 40) < 0.1)
        // Different sound isn't the same moment, however it's shifted.
        let other = try #require(SoundSync.match(Self.standardized(a), Self.standardized(Self.speech(seconds: 40, seed: 2))))
        #expect(!other.isSameMoment, "match \(other.match)")
        // Too short to say.
        #expect(SoundSync.match(Self.standardized(a), Self.standardized(Array(a[0..<500]))) == nil)
    }

    @Test func groupsChainMatchesAndPreferASoundRecorder() {
        let curves = ["cam": SoundSync.Curve(values: [], level: 0.5, trackID: 1), "screen": .init(values: [], level: 0.7, trackID: 1), "recorder": .init(values: [], level: 0.2, trackID: 1), "broll": .init(values: [], level: 0.9, trackID: 1)]
        // cam = screen + 0.089; recorder = cam + 1.5; b-roll matched nothing well.
        let matches: [(a: String, b: String, match: SoundSync.Match)] = [
            ("cam", "screen", .init(offset: 0.089, match: 0.99, overlap: 190)),
            ("recorder", "cam", .init(offset: 1.5, match: 0.9, overlap: 120)),
            ("broll", "cam", .init(offset: 4, match: 0.3, overlap: 30)),
        ]
        let groups = SoundSync.groups(matches, curves: curves, audioOnly: ["recorder"])
        #expect(groups.count == 1)
        let g = groups[0]
        #expect(g.soundAssetID == "recorder" && g.takes.first?.assetID == "recorder" && g.take("broll") == nil)
        // On the recorder's clock: recorder time = take time + offset.
        #expect(g.take("cam")?.offset == 1.5 && g.take("screen")?.offset == 1.589)
        var d = Dailies(); d.syncGroups = groups
        #expect(d.syncedTime(10, from: "screen", to: "cam") == 10.089)
    }

    @Test func takesThatRecordedTheSameMomentAreLinkedByTheirSound() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // One room, two recorders: the second started 4.25 s later and stopped early. A third is elsewhere.
        let room = Self.signal(seconds: 30, seed: 3)
        try Self.wav(room, to: dir.appendingPathComponent("room.wav"))
        try Self.wav(Array(room[Int(4.25 * 8_000)..<Int(24.25 * 8_000)]).map { $0 * 0.5 }, to: dir.appendingPathComponent("late.wav"))
        try Self.wav(Self.signal(seconds: 20, seed: 4), to: dir.appendingPathComponent("elsewhere.wav"))
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Sync.direction"), name: "Sync")
        let runtime = try ToolRuntime(store: store)
        var ids: [String: String] = [:]
        for name in ["room", "late", "elsewhere"] {
            let r = try await runtime.invoke("direction_import", arguments: .object(["path": .string(dir.appendingPathComponent(name + ".wav").path)]))
            ids[name] = r.value["asset"]["id"].string
        }
        let job = try await runtime.invoke("direction_sync_takes").value
        _ = try await runtime.waitForJob(try #require(job["id"].string))
        let d = try store.dailies()
        let g = try #require(d.syncGroups?.first)
        #expect(d.syncGroups?.count == 1 && g.takes.count == 2 && g.take(ids["elsewhere"]!) == nil)
        // The louder recorder carries the sound; the late one sits 4.25 s into it.
        #expect(g.soundAssetID == ids["room"])
        #expect(abs((g.take(ids["late"]!)?.offset ?? 0) - 4.25) < 0.012, "offset \(String(describing: g.take(ids["late"]!)?.offset))")
        #expect(Set(d.syncChecked ?? []) == Set(ids.values))
        // Nothing new: nothing to do.
        #expect(try await runtime.invoke("direction_sync_takes").value["note"].string != nil)
        // Compared again from scratch, every pair's answer is already known: nothing is matched again.
        let again = try await runtime.invoke("direction_sync_takes", arguments: .object(["force": .bool(true)])).value
        let done = try await runtime.waitForJob(try #require(again["id"].string))
        #expect(done.result?["compared"].int == 0)
        #expect(try store.dailies().syncGroups?.first?.take(ids["late"]!) != nil)
    }

    /// Finishing muted every track of one take (the cut's sound came from a mix) and brought its mix
    /// into the film. Neither may undo the link: the mix isn't footage, and a muted take still
    /// recorded the moment.
    @Test func theEditorsMixAndAMutedTakeLeaveTheLinkAlone() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let room = Self.signal(seconds: 30, seed: 3)
        try Self.wav(room, to: dir.appendingPathComponent("room.wav"))
        try Self.wav(Array(room[Int(4.25 * 8_000)..<Int(24.25 * 8_000)]).map { $0 * 0.5 }, to: dir.appendingPathComponent("late.wav"))
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Sync.direction"), name: "Sync")
        let runtime = try ToolRuntime(store: store)
        func importing(_ url: URL) async throws -> String { try #require(try await runtime.invoke("direction_import", arguments: .object(["path": .string(url.path)])).value["asset"]["id"].string) }
        let roomID = try await importing(dir.appendingPathComponent("room.wav")), lateID = try await importing(dir.appendingPathComponent("late.wav"))
        _ = try await runtime.waitForJob(try #require(try await runtime.invoke("direction_sync_takes").value["id"].string))
        #expect(try store.dailies().syncGroups?.first?.take(lateID) != nil)

        let mixURL = store.url.appendingPathComponent("Editor/Deliveries/mix.wav")
        try FileManager.default.createDirectory(at: mixURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.wav(Array(room[0..<Int(20 * 8_000)]), to: mixURL)
        let mixID = try await importing(mixURL)
        let p = try store.read()
        _ = try store.update(expectedRevision: p.editRevision, key: UUID().uuidString, request: Data(), summary: "Muted the late recorder") { p in
            let i = p.assets.firstIndex { $0.id == lateID }!
            for t in p.assets[i].audio.indices { p.assets[i].audio[t].settings.muted = true }
        }
        #expect(try store.read().footage(film: store.url).map(\.id) == [roomID, lateID])
        #expect(try await runtime.invoke("direction_sync_takes").value["note"].string != nil)

        // Before Direction told them apart, the mix was compared and the link was lost. The next pass
        // compares the footage again without it, the muted take heard on its muted tracks.
        try store.saveSync([], checked: [roomID, lateID, mixID])
        _ = try await runtime.waitForJob(try #require(try await runtime.invoke("direction_sync_takes").value["id"].string))
        let d = try store.dailies()
        #expect(d.syncGroups?.count == 1 && d.syncGroups?.first?.take(roomID) != nil && d.syncGroups?.first?.take(lateID) != nil)
        #expect(Set(d.syncChecked ?? []) == [roomID, lateID])
        #expect(try await runtime.invoke("direction_sync_takes").value["note"].string != nil)
    }

    @Test func footageIsWhatTheDirectorBroughtIn() throws {
        let film = URL(fileURLWithPath: "/Films/Demo.direction"), styles = URL(fileURLWithPath: "/Styles")
        SharedSettings.stylesFolderOverride = styles
        defer { SharedSettings.stylesFolderOverride = nil }
        func asset(_ path: String) -> MediaAsset { MediaAsset(name: "a", path: path, duration: MediaTime(seconds: 10)) }
        #expect(asset("/Footage/camera.mp4").isFootage(film: film))
        #expect(asset("/Films/Demo.direction/Made/shot.mov").isFootage(film: film))
        #expect(!asset("/Films/Demo.direction/Editor/Deliveries/mix.wav").isFootage(film: film))
        #expect(!asset("/Films/Demo.direction/Style/sounds/whoosh.wav").isFootage(film: film))
        #expect(!asset("/Styles/desk-talk/sounds/pop.wav").isFootage(film: film))
        // A sibling folder that only starts with the film's name is footage.
        #expect(asset("/Films/Demo.direction copy/camera.mp4").isFootage(film: film))
        var graphic = asset("/Elsewhere/title.mov"); graphic.graphic = "title"
        #expect(!graphic.isFootage(film: film))
    }

    // MARK: Fixtures

    static func standardized(_ x: [Float]) -> [Float] {
        let mean = x.reduce(0, +) / Float(x.count), c = x.map { $0 - mean }
        let sd = (c.map { $0 * $0 }.reduce(0, +) / Float(x.count)).squareRoot()
        return c.map { $0 / sd }
    }

    /// 8 kHz noise shaped like speech.
    static func signal(seconds: Double, seed: UInt64) -> [Float] {
        let loudness = speech(seconds: seconds, seed: seed)
        var rng = SplitMix(seed: seed &+ 100)
        return (0..<Int(seconds * 8_000)).map { i in loudness[min(loudness.count - 1, i / 80)] * (Float(rng.next() % 2000) / 1000 - 1) * 0.5 }
    }

    static func wav(_ samples: [Float], to url: URL) throws {
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        text("RIFF"); u32(UInt32(36 + bytes)); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(8_000); u32(16_000); u16(2); u16(16); text("data"); u32(UInt32(bytes))
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 30_000))) }
        try data.write(to: url)
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
