import Testing
import Foundation
@testable import DirectionCore

/// Naming footage in a note (cut.md › Naming footage): "@Scene 2", "@2A", "@2A Take 3", as Dailies shows them.
private func film() -> (Dailies, [MediaAsset], Sequence) {
    let asset = { (id: String, name: String) in MediaAsset(id: id, name: name, path: "/\(name)", duration: .init(seconds: 20), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 24)]) }
    let assets = [asset("t1", "A011_C001.mov"), asset("t3", "A011_C003.mov"), asset("slides", "deck.mov"), asset("s20", "late.mov"), asset("loose", "MVI_0001.MP4")]
    var d = Dailies(scenes: [DailiesScene(id: "scene-2", number: 2, title: "Pricing", setups: [DailiesSetup(code: "2A", description: "Talking head"), DailiesSetup(code: "2B", description: "")]),
                             DailiesScene(id: "scene-20", number: 20, title: "Outtakes")], takes: [:])
    func take(_ id: String, _ scene: String?, _ setup: String?, _ code: String?, _ caption: String? = nil, circled: Bool = false) {
        var t = TakeInfo(assetID: id); t.sceneID = scene; t.setupCode = setup; t.code = code; t.caption = caption; t.circled = circled; d.takes[id] = t
    }
    take("t1", "scene-2", "2A", "T1", "\u{201C}It costs less than lunch.\u{201D}")
    take("t3", "scene-2", "2A", "T3", "Laughs, then the line.", circled: true)
    take("slides", "scene-2", "2B", "T1")
    take("s20", "scene-20", nil, "T2")
    var cut = Sequence(name: "Cut 1")
    cut.clips = [Clip(assetID: "t3", name: "A011_C003.mov", start: .init(seconds: 70), sourceRange: .init(start: 2, end: 14)), Clip(assetID: "slides", name: "deck.mov", start: .init(seconds: 82), sourceRange: .init(start: 0, end: 8))]
    return (d, assets, cut)
}

@Test func scenesSetupsAndTakesHaveTheNamesDailiesShows() {
    let (d, assets, _) = film()
    let names = FootageNames.all(d, assets: assets)
    #expect(names.map(\.name) == ["Scene 2", "2A", "2B", "Scene 20", "2A Take 1", "2A Take 3", "2B Take 1", "Scene 20 Take 2", "MVI_0001"])
    #expect(names.first { $0.name == "2A" }?.summary == "Talking head \u{00B7} Scene 2 Pricing")
    #expect(names.first { $0.name == "2A Take 3" }?.summary == "Laughs, then the line. \u{00B7} Circled")
    #expect(names.last?.summary == "Not logged yet")
}

@Test func aNoteNamesWholeNamesLongestFirst() {
    let (d, assets, _) = film()
    let names = FootageNames.all(d, assets: assets)
    let found = FootageNames.mentions(in: "Use @2A Take 3 here, not anything from @Scene 20, and keep @2B.", names: names)
    #expect(Set(found.map(\.name)) == ["2A Take 3", "Scene 20", "2B"])
    #expect(FootageNames.mentions(in: "@Scene 2's ending, then @2a take 1", names: names).map(\.name).sorted() == ["2A Take 1", "Scene 2"])
    #expect(FootageNames.mentions(in: "email@2A.com, no names", names: names).isEmpty)
}

@Test func theEditorReadsWhichTakeSetupOrSceneEachIs() {
    let (d, assets, cut) = film()
    let names = FootageNames.all(d, assets: assets)
    func explain(_ text: String) -> String { FootageNames.explain(FootageNames.mentions(in: text, names: names), dailies: d, assets: assets, cut: cut) }
    #expect(explain("@2A Take 3") == "@2A Take 3 is the take A011_C003.mov (assetID t3) in scene 2 Pricing, setup 2A Talking head: \u{201C}Laughs, then the line.\u{201D}, circled. In the cut at 1:10\u{2013}1:22.")
    #expect(explain("@2A Take 1") == "@2A Take 1 is the take A011_C001.mov (assetID t1) in scene 2 Pricing, setup 2A Talking head: \u{201C}It costs less than lunch.\u{201D}. Not in the cut.")
    #expect(explain("@2A") == "@2A is setup 2A, Talking head, in scene 2 Pricing: 2A T1, 2A T3 (circled). In the cut at 1:10\u{2013}1:22.")
    #expect(explain("@Scene 2") == "@Scene 2 is scene 2 Pricing (scene-2): 3 takes, 2A T1, 2A T3 (circled), 2B T1. In the cut at 1:10\u{2013}1:30.")
    #expect(explain("@MVI_0001") == "@MVI_0001 is the take MVI_0001.MP4 (assetID loose) not in a scene yet. Not in the cut.")
}
