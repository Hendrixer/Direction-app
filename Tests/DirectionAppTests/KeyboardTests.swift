import Testing
import AppKit
import SwiftUI
import DirectionCore
@testable import DirectionApp

/// SwiftUI offers a key press to a room's `onKeyPress` before an AppKit text view inside it sees
/// the key. Room keys must leave a note being written alone, and still work when nothing is typed.
@MainActor
@Test func spaceTypesInTheNoteFieldAndPlaysEverywhereElse() throws {
    _ = NSApplication.shared
    let m = SampleFilm.make()
    m.room = .cut
    let host = NSHostingView(rootView: CutRoom(model: m).frame(width: 1200, height: 800))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    func settle() { for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } }
    func press(_ chars: String, _ code: UInt16) {
        NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
        settle()
    }
    for _ in 0..<4 { settle() }
    // The room has the keys: Space plays and pauses.
    press(" ", 49)
    #expect(m.playing)
    press(" ", 49)
    #expect(!m.playing)
    // Writing a note, in its row: Space is a space.
    func find(_ v: NSView) -> NoteTextView? { (v as? NoteTextView) ?? v.subviews.lazy.compactMap(find).first }
    #expect(find(host) == nil)
    m.beginWriting(try #require(m.note("note-3")))
    for _ in 0..<4 { settle() }
    let field = try #require(find(host))
    _ = window.makeFirstResponder(field)
    settle()
    for (c, code) in [("a", UInt16(0)), (" ", 49), ("b", 11)] { press(c, code) }
    #expect(field.string == "a b" && m.draftText == "a b")
    #expect(!m.playing)
}
