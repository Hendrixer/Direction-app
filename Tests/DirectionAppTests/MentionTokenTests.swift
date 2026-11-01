import Testing
import Foundation
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
