import Testing
import Foundation
import SwiftUI
import DirectionCore
@testable import DirectionApp

@Suite("Settings pages")
@MainActor
struct SettingsPagesTests {
    /// A page opens over its section and Back returns; Back says where it goes, or just "Back" when that has the
    /// page's own name.
    @Test func backReturnsToWhereThePageCameFrom() {
        let pages = SettingsPages(); pages.root = "Styles"
        pages.open(SettingsPage(id: "style:a", title: "Desk Talk") { EmptyView() })
        #expect(pages.backTitle == "Styles")
        pages.root = "Library"; pages.stack = [SettingsPage(id: "library", title: "Library") { EmptyView() }]
        #expect(pages.backTitle == "Back")
        pages.open(SettingsPage(id: "library:dissolve", title: "Dissolve") { EmptyView() })
        #expect(pages.backTitle == "Library")
        pages.back(); pages.back()
        #expect(pages.stack.isEmpty)
    }

    /// A style's page writes what it says: a rule still being typed goes in with it, a new one needs its name, and
    /// typing in the add row alone changes nothing written.
    @Test func aStylePageWritesWhatItSays() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-style-page-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var draft = StyleDraft.new
        #expect(throws: DirectionError.self) { try draft.save(in: folder) }
        draft.name = "Desk Talk"; draft.summary = "Quick explainers."
        let before = draft.written
        draft.pending = "Tighten every pause over 0.35 s."; draft.pendingArea = "pace"
        #expect(draft.written == before)
        draft.addPending()
        let made = try draft.save(in: folder)
        #expect(made.name == "Desk Talk" && made.rules.map(\.text) == ["Tighten every pause over 0.35 s."] && made.rules.first?.area == "pace")

        var again = StyleDraft(made); again.rules[0].text = "Tighten every pause over 0.3 s."
        _ = try again.save(in: folder)
        #expect(StyleLibrary.list(in: folder).first?.rules.first?.text == "Tighten every pause over 0.3 s.")
    }
}
