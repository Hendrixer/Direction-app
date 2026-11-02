import Testing
import Foundation
import DirectionCore
@testable import DirectionApp

/// A shot clicked in a take is the one lit: the frame the player lands on can report a hair before the
/// shot's start (29.97 frames a second against a start written at 30), and that's still the shot.
@Test @MainActor func theShotClickedIsTheShotLit() {
    let shots = [Shot(assetID: "t", number: 1, start: 0, end: 26.867), Shot(assetID: "t", number: 2, start: 26.867, end: 30.8), Shot(assetID: "t", number: 3, start: 30.8, end: 32.333)]
    #expect(DailiesShotsRow.under(30.7974, in: shots, fps: 29.97)?.number == 3)
    #expect(DailiesShotsRow.under(30.8 - 1 / 29.97, in: shots, fps: 29.97)?.number == 2)
    #expect(DailiesShotsRow.under(0, in: shots, fps: 30)?.number == 1)
}

/// What every shot has is said once above the row ("11 shots, all close, all underexposed"); a card keeps only
/// what's its own, like the one shaky shot.
@Test @MainActor func whatEveryShotHasIsSaidOnce() {
    func shot(_ n: Int, _ flags: [String]) -> Shot {
        Shot(assetID: "t", number: n, start: Double(n), end: Double(n) + 1.5, look: ShotLook(description: "Close on hands at a keyboard.", size: "close", flags: flags))
    }
    let dark = (1...10).map { shot($0, ["underexposed"]) } + [shot(11, ["underexposed", "shaky"])]
    let common = DailiesShotsRow.common(dark)
    #expect(common.line(count: dark.count) == "11 shots, all close, all underexposed")
    // Sizes that differ, or a flag only some have, stay on their cards.
    var mixed = dark; mixed[0].look?.size = "wide"; mixed[1].look?.flags = []
    #expect(DailiesShotsRow.common(mixed).line(count: mixed.count) == "11 shots")
}
