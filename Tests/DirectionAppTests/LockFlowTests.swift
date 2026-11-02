import Testing
import Foundation
import DirectionCore
@testable import DirectionApp

@Suite("Locks and what waits on you")
@MainActor
struct LockFlowTests {
    /// "Unlock 0 Naration and 4 Focused" unlocks both, in one answer: the editor never asks again for the second.
    /// A choice saying it's done ("I've unlocked …") unlocks a scene still locked; a choice about something else
    /// unlocks nothing.
    @Test func aChoiceUnlocksEveryLockedSceneItNames() {
        let m = SampleFilm.make()
        for i in m.dailies.scenes.indices { m.dailies.scenes[i].locked = ["Cold open", "Launch day"].contains(m.dailies.scenes[i].title) }
        #expect(m.unlockScenes(for: .init(id: "both", label: "Unlock 1 Cold open and 5 Launch day")).map(\.title) == ["Cold open", "Launch day"])
        #expect(m.unlockScenes(for: .init(id: "done", label: "I\u{2019}ve unlocked 5 Launch day")).map(\.title) == ["Launch day"])
        #expect(m.unlockScenes(for: .init(id: "skip", label: "Skip note 7 for this cut")).isEmpty)
    }

    /// The editor's questions show on the Notes tab, in its color, ahead of marks to write up.
    @Test func questionsShowWhereverYouAre() {
        let m = ChangesFixtures.question()
        #expect(m.badge(for: .notes).map { $0.0 } == "1" && m.badge(for: .notes)?.1 == false)
        m.questions = []
        #expect(m.badge(for: .notes) == nil || m.badge(for: .notes)?.1 == true)
    }
}
