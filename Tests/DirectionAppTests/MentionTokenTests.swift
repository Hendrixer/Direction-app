import Testing
import Foundation
import DirectionCore
@testable import DirectionApp

/// "@" in the brief's fields (techniques.md › The library): the caret a field reports can still point into
/// what it held before, like the last film's brief when a new one starts, and that's never measured.
@Test func aCaretFromOtherTextIsLeftAlone() throws {
    let before = "Tired, then proud. Quiet, not triumphant."
    #expect(MentionToken.caret(before.endIndex, in: "") == nil)
    #expect(MentionToken.caret(before.endIndex, in: "T") == nil)

    let now = "Warm, like @Fil"
    #expect(MentionToken.caret(now.startIndex, in: now) == 0)
    let end = try #require(MentionToken.caret(now.endIndex, in: now))
    #expect(end == now.utf16.count && MentionToken.find(now, caret: end)?.query == "Fil")
    // Counted in UTF-16, past a dash and a clapper.
    let wide = "Big \u{2014} \u{1F3AC} @F"
    #expect(MentionToken.caret(wide.endIndex, in: wide) == wide.utf16.count && MentionToken.find(wide, caret: wide.utf16.count)?.query == "F")
}

/// Once a name is picked and the note goes on, the list is gone: words typed after "@Film grain" are the note,
/// even where they're words in what Film grain is ("over the picture"). A name of several words still narrows.
@Test func theListClosesOnceANameIsWritten() {
    func entry(_ name: String, _ summary: String) -> LibraryEntry { LibraryEntry(id: name, name: name, kind: "effect", summary: summary, icon: "circle", use: name) }
    let grain = entry("Film grain", "Fine moving grain over the picture."), song = entry("Try Again", "A song"), drums = entry("Try Again Drums", "Its drums")
    let all = [grain, song, drums]
    // The first word offers whatever the library found for it.
    #expect(MentionToken.offer("Fil", from: [grain]) == [grain])
    #expect(MentionToken.offer("Film grain ", from: [grain]).isEmpty)
    #expect(MentionToken.offer("Film grain over the", from: [grain]).isEmpty)
    #expect(MentionToken.offer("Film grain o", from: [grain]).isEmpty)
    #expect(MentionToken.offer("Try Again ", from: all).isEmpty)
    #expect(MentionToken.offer("Try Again D", from: all) == [drums])
}
