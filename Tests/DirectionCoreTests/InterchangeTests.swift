import Testing
import Foundation
@testable import DirectionCore

/// The cut for other editing apps (Interchange, issue #4): what's rendered, what goes across as itself, and that
/// every clip lands on the same frames when the FCPXML is read back the way Final Cut reads it.
struct InterchangeTests {
    /// A clip in the FCPXML, where it plays in the cut and what it shows.
    struct Placed { var lane: Int; var start: Double; var end: Double; var file: String; var sourceIn: Double; var enable: String; var element: XMLElement }

    /// Reads a timeline back: spine clips at their offsets, anchored clips at their parent's time plus their offset
    /// in the parent's own time, slowed clips through their time map, each file's own start taken off.
    static func read(_ xml: String) throws -> (clips: [Placed], doc: XMLDocument) {
        let doc = try XMLDocument(xmlString: xml)
        func t(_ s: String?) -> Double {
            guard var s, !s.isEmpty else { return 0 }
            s.removeLast()
            let parts = s.split(separator: "/").compactMap { Double($0) }
            return parts.count == 2 ? parts[0] / parts[1] : parts.first ?? 0
        }
        var assets: [String: (file: String, start: Double)] = [:]
        for a in try doc.nodes(forXPath: "//resources/asset") as! [XMLElement] {
            let src = (try a.nodes(forXPath: "media-rep").first as? XMLElement)?.attribute(forName: "src")?.stringValue ?? ""
            assets[a.attribute(forName: "id")!.stringValue!] = (URL(string: src)?.lastPathComponent ?? src, t(a.attribute(forName: "start")?.stringValue))
        }
        var out: [Placed] = []
        func walk(_ e: XMLElement, parentStart: Double, parentLocal: Double, top: Bool) {
            for case let child as XMLElement in e.children ?? [] where ["asset-clip", "video", "gap"].contains(child.name ?? "") {
                let offset = t(child.attribute(forName: "offset")?.stringValue), local = t(child.attribute(forName: "start")?.stringValue)
                let start = top ? offset : parentStart + (offset - parentLocal), duration = t(child.attribute(forName: "duration")?.stringValue)
                if child.name != "gap", let ref = child.attribute(forName: "ref")?.stringValue, let a = assets[ref] {
                    var speed = 1.0
                    if let points = try? child.nodes(forXPath: "timeMap/timept") as? [XMLElement], points.count == 2 {
                        speed = (t(points[1].attribute(forName: "value")?.stringValue) - t(points[0].attribute(forName: "value")?.stringValue)) / (t(points[1].attribute(forName: "time")?.stringValue) - t(points[0].attribute(forName: "time")?.stringValue))
                    }
                    out.append(Placed(lane: Int(child.attribute(forName: "lane")?.stringValue ?? "0") ?? 0, start: start, end: start + duration, file: a.file, sourceIn: local * speed - a.start, enable: child.attribute(forName: "srcEnable")?.stringValue ?? "all", element: child))
                }
                walk(child, parentStart: start, parentLocal: local, top: false)
            }
        }
        let spine = try #require(try doc.nodes(forXPath: "//sequence/spine").first as? XMLElement)
        walk(spine, parentStart: 0, parentLocal: 0, top: true)
        return (out, doc)
    }

    func timeline(_ c: TimelineCut, rendered: Bool = true, sources: [String: Interchange.SourceFacts] = [:]) throws -> (plan: Interchange.Plan, xml: String) {
        let s = c.project.sequences[0]
        let plan = Interchange.plan(project: c.project, sequence: s, dailies: c.context.dailies)
        let renders = Dictionary(uniqueKeysWithValues: plan.renders.map { ($0.id, URL(fileURLWithPath: "/Export/Renders/\($0.name).mov")) })
        let xml = try Interchange.fcpxml(.init(project: c.project, sequence: s, filmName: "Launch film", cutName: "Cut 3", dailies: c.context.dailies, plan: plan, rendered: rendered ? renders : [:], sources: sources))
        return (plan, xml)
    }

    @Test func plainCutsGoAcrossAsThemselvesOnTheSameFrames() throws {
        let (plan, xml) = try timeline(.make(), sources: ["b": .init(timecodeStart: 3600)])
        #expect(plan.renders.isEmpty)
        let clips = try Self.read(xml).clips
        // V1 in the spine, the music anchored under it, each from the right moment of its file.
        let v1 = clips.filter { $0.lane == 0 }.sorted { $0.start < $1.start }
        #expect(v1.map(\.file) == ["a.mov", "b.mov", "c.mov"])
        #expect(zip(v1.map { ($0.start, $0.end, $0.sourceIn) }, [(0.0, 4.0, 2.0), (4, 9, 3), (9, 13, 1)]).allSatisfy { close($0.0, $1.0) && close($0.1, $1.1) && close($0.2, $1.2) })
        let music = try #require(clips.first { $0.file == "music.mov" })
        #expect(music.lane == -1 && close(music.start, 0) && close(music.end, 13) && music.element.attribute(forName: "audioRole")?.stringValue == "music")
        // b's timecode starts at an hour: its clip starts an hour and 3 seconds into the file's own time.
        #expect(v1[1].element.attribute(forName: "start")?.stringValue == "3603s")
        #expect(xml.contains("<fcpxml version=\"1.10\">") && xml.contains("<!DOCTYPE fcpxml>") && xml.contains("Scene 1: Cold open") && xml.contains("Launch film \u{2013} Cut 3"))
    }

    @Test func whatOnlyDirectionDrawsIsRenderedOnTheStoryLayerAndTheSoundStays() throws {
        var c = TimelineCut.make()
        // A freeze in b, a mask on c, a dip into c; a look filter on b and grain over V1 aren't rendered.
        var s = c.project.sequences[0]
        s.clips[1].effects = [ClipEffect(name: "filter.grain", params: ["amount": .number(0.4)])]
        s.clips[2].effects = [ClipEffect(name: "mask", params: ["shape": .string("ellipse")])]
        var dip = ClipTransition(type: "dipToBlack", frames: 12, before: 0.2, after: 0.2); dip.source = nil
        s.clips[2].transition = dip
        s.tracks = ["V1": TrackSettings(effects: [ClipEffect(name: "filter.bloom", params: ["amount": .number(0.3)])])]
        var freeze = Clip(id: "f1", assetID: "b", name: "b", start: .init(seconds: 13), sourceRange: .init(start: 4, end: 4))
        freeze.hold = .init(seconds: 1.5)
        s.clips.append(freeze)
        c.project.sequences[0] = s
        let (plan, xml) = try timeline(c)
        #expect(plan.renders.map { [$0.start, $0.end] } == [[8.8, 14.5]], "the dip, c and the freeze are one stretch: \(plan.renders.map { ($0.start, $0.end) })")
        #expect(plan.renders[0].reasons == ["a dip to black", "a mask", "a freeze"])
        #expect(plan.notes.contains("V1 has bloom over all of it, except in the renders, which already have it.") && plan.notes.contains("One shot has grain (1B T2)."), "\(plan.notes)")
        let clips = try Self.read(xml).clips
        // b plays up to the render, the render covers to the end of the freeze, and b's and c's sound play whole.
        let picture = clips.filter { $0.enable != "audio" && $0.lane == 0 }.sorted { $0.start < $1.start }
        #expect(picture.map(\.file) == ["a.mov", "b.mov", "01 Dip to black 00-08-24.mov"], "\(picture.map(\.file))")
        #expect(close(picture[1].end, 8.8, 1e-9) && close(picture[2].start, 8.8, 1e-9) && close(picture[2].end, 14.5, 1e-9))
        #expect(picture[1].enable == "video")
        let sound = clips.filter { $0.enable == "audio" }.sorted { $0.start < $1.start }
        #expect(sound.map(\.file) == ["b.mov", "c.mov"] && close(sound[0].start, 4) && close(sound[0].end, 9) && close(sound[0].sourceIn, 3) && close(sound[1].end, 13))
        // Without the render's file, there's no timeline.
        #expect(throws: DirectionError.self) { _ = try timeline(c, rendered: false) }
    }

    @Test func aDissolveOnTheStoryGoesAcrossAndARenderTakesAllOfOneItWouldCut() throws {
        var c = TimelineCut.make()
        c.project.sequences[0].clips[1].transition = ClipTransition(type: "dissolve", frames: 20, before: 1.0 / 3, after: 1.0 / 3)
        var (plan, xml) = try timeline(c)
        #expect(plan.renders.isEmpty)
        let transition = try #require(try Self.read(xml).doc.nodes(forXPath: "//spine/transition").first as? XMLElement)
        #expect(transition.attribute(forName: "offset")?.stringValue == "11/3s" && transition.attribute(forName: "duration")?.stringValue == "2/3s")
        // A freeze on a that ends inside the dissolve: the render takes the whole dissolve, so b starts clean after it.
        var freeze = Clip(id: "f1", assetID: "a", name: "a", start: .init(seconds: 3.8), sourceRange: .init(start: 5.8, end: 5.8))
        freeze.hold = .init(seconds: 0.2)
        c.project.sequences[0].clips[0].sourceRange = .init(start: 2, end: 5.8)
        c.project.sequences[0].clips.append(freeze)
        (plan, xml) = try timeline(c)
        #expect(plan.renders.count == 1 && close(plan.renders[0].start, 11.0 / 3, 1e-9) && close(plan.renders[0].end, 13.0 / 3, 1e-9), "\(plan.renders.map { ($0.start, $0.end) })")
        #expect(try Self.read(xml).doc.nodes(forXPath: "//spine/transition").isEmpty)
    }

    @Test func slowedClipsJCutsAndAnchoredClipsKeepTheirFrames() throws {
        var c = TimelineCut.make()
        var s = c.project.sequences[0]
        // b at half speed (3–8 s of b over 10 s), a J-cut into c, a cutaway on V2 over the slowed b.
        s.clips[1].speed = 0.5
        s.clips[2].start = .init(seconds: 14); s.clips[2].soundLead = 0.5
        s.clips[3].sourceRange = .init(start: 0, end: 18)
        s.clips.append(Clip(id: "v2", assetID: "d", name: "d", layer: 1, start: .init(seconds: 6), sourceRange: .init(start: 2, end: 4)))
        s.clips[s.clips.count - 1].framing.offsetX = 0.25
        c.project.sequences[0] = s
        let clips = try Self.read(try timeline(c).xml).clips
        let slowed = try #require(clips.first { $0.file == "b.mov" && $0.lane == 0 })
        #expect(close(slowed.start, 4) && close(slowed.end, 14) && close(slowed.sourceIn, 3))
        let cutaway = try #require(clips.first { $0.file == "d.mov" })
        #expect(cutaway.lane == 1 && close(cutaway.start, 6) && close(cutaway.end, 8) && close(cutaway.sourceIn, 2))
        // Moved right a quarter of the frame's width: 44.44% of its height in FCPXML's terms.
        #expect((try cutaway.element.nodes(forXPath: "adjust-transform").first as? XMLElement)?.attribute(forName: "position")?.stringValue == "44.4444 0")
        // c's picture at 14, its sound from half a second before, on its own.
        let picture = try #require(clips.first { $0.file == "c.mov" && $0.enable == "video" }), sound = try #require(clips.first { $0.file == "c.mov" && $0.enable == "audio" })
        #expect(close(picture.start, 14) && close(sound.start, 13.5) && close(sound.sourceIn, 0.5) && close(sound.end, 18) && sound.lane < 0)
    }

    @Test func soundKeepsItsLevelKeysAndFades() throws {
        var c = TimelineCut.make()
        var s = c.project.sequences[0]
        s.clips[3].gainDB = -6
        s.clips[3].fadeIn = 0.5
        s.clips[3].duckKeys = [Keyframe(t: 2, v: 0), Keyframe(t: 2.5, v: -8)]
        s.tracks = ["A2": TrackSettings(gainDB: -2)]
        s.mixGainDB = 1
        c.project.sequences[0] = s
        let clips = try Self.read(try timeline(c).xml).clips
        let music = try #require(clips.first { $0.file == "music.mov" })
        let volume = try #require(try music.element.nodes(forXPath: "adjust-volume").first as? XMLElement)
        #expect(volume.attribute(forName: "amount")?.stringValue == "-7dB")
        let keys = try volume.nodes(forXPath: "param/keyframeAnimation/keyframe").compactMap { ($0 as? XMLElement)?.attribute(forName: "value")?.stringValue }
        #expect(keys == ["-7dB", "-7dB", "-15dB", "-15dB"], "\(keys)")
        #expect((try volume.nodes(forXPath: "param/fadeIn").first as? XMLElement)?.attribute(forName: "duration")?.stringValue == "1/2s")
    }

    @Test func soundTheCutDoesntPlayStaysOutAndSoundUnderADissolveIsCutAtTheEdit() throws {
        var c = TimelineCut.make()
        var s = c.project.sequences[0]
        // The music muted; a dissolve into b; a J-cut into c reaching back past the start of c's file.
        s.clips[3].audioOverrides["2"] = { var a = AudioSettings(); a.muted = true; return a }()
        s.clips[1].transition = ClipTransition(type: "dissolve", frames: 20, before: 1.0 / 3, after: 1.0 / 3)
        s.clips[2].soundLead = 2
        c.project.sequences[0] = s
        let clips = try Self.read(try timeline(c).xml).clips
        #expect(!clips.contains { $0.file == "music.mov" })
        // a and b keep their picture in the storyline and their sound on its own, ending and starting at the edit.
        let aSound = try #require(clips.first { $0.file == "a.mov" && $0.enable == "audio" }), bSound = try #require(clips.first { $0.file == "b.mov" && $0.enable == "audio" })
        #expect(close(aSound.end, 4) && close(bSound.start, 4) && clips.filter { $0.enable == "video" }.count >= 2)
        // c starts 1 s into its file, so its sound can start only 1 s early, as Direction plays it.
        let cSound = try #require(clips.first { $0.file == "c.mov" && $0.enable == "audio" })
        #expect(close(cSound.start, 8) && close(cSound.sourceIn, 0))
    }

    @Test func graphicsOverTheLookStayOverEverythingElse() throws {
        var c = TimelineCut.make()
        var graphic = Clip(id: "g", assetID: "d", name: "lower third", layer: 1, start: .init(seconds: 1), sourceRange: .init(start: 0, end: 3))
        graphic.aboveLook = true
        c.project.sequences[0].clips += [graphic, Clip(id: "x", assetID: "c", name: "cutaway", layer: 2, start: .init(seconds: 2), sourceRange: .init(start: 6, end: 8))]
        let clips = try Self.read(try timeline(c).xml).clips
        let g = try #require(clips.first { $0.file == "d.mov" }), x = try #require(clips.first { $0.file == "c.mov" && $0.lane > 0 })
        #expect(g.lane > x.lane, "the graphic on lane \(g.lane), the cutaway on \(x.lane)")
    }

    @Test func stillsAndHeldKeysKeepTheirTiming() throws {
        var c = TimelineCut.make()
        var photo = MediaAsset(id: "p", name: "photo.png", path: "/photo.png", duration: .init(seconds: 10), video: [.init(id: 1, width: 3000, height: 2000, frameRate: 0)])
        photo.isImage = true
        c.project.assets.append(photo)
        // The second half of a photo, fading in over 0.4 s from 3 s into it, then held at 0.6 until it jumps to 1.
        var still = Clip(id: "s", assetID: "p", name: "photo", layer: 1, start: .init(seconds: 5), sourceRange: .init(start: 3, end: 6))
        still.effects = [ClipEffect(name: "transform", keys: ["opacity": [Keyframe(t: 3, v: 0), Keyframe(t: 3.4, v: 0.6, ease: "hold"), Keyframe(t: 5, v: 1)]])]
        c.project.sequences[0].clips.append(still)
        let clips = try Self.read(try timeline(c).xml).clips
        let p = try #require(clips.first { $0.file == "photo.png" })
        #expect(p.element.name == "video" && close(p.start, 5) && p.element.attribute(forName: "start")?.stringValue == "3s")
        let keys = try p.element.nodes(forXPath: "adjust-blend/param/keyframeAnimation/keyframe").compactMap { $0 as? XMLElement }
        #expect(keys.compactMap { $0.attribute(forName: "time")?.stringValue } == ["3s", "17/5s", "149/30s", "5s"], "\(keys.compactMap { $0.attribute(forName: "time")?.stringValue })")
        #expect(keys.compactMap { $0.attribute(forName: "value")?.stringValue } == ["0", "0.6", "0.6", "1"])
    }

    @Test func timesAreExact() {
        typealias R = Interchange.Rational
        let ntsc = FrameRate(30000, 1001)
        #expect(R.on(1, ntsc).description == "1001/1000s")
        #expect((R(1001, 30000) + R(1, 24)).description == "2251/30000s" && R(6, 2).description == "3s" && R.of(frames: 90, FrameRate(30, 1)).description == "3s")
        #expect(Interchange.number(44.44444) == "44.4444" && Interchange.number(-0) == "0" && Interchange.decibels(-200) == "-96dB")
    }
}
