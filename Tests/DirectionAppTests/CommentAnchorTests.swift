import Foundation
import Testing
@testable import DirectionApp
@testable import DirectionCore
import DirectionTools

/// These title-only sequences need no footage or rendering to exercise review interactions.
private func reviewFixture() -> Project {
    func sequence(_ id: String, duration: Double) -> DirectionCore.Sequence {
        var title = Clip(id: id + "-title", assetID: nil, name: "Review fixture", kind: .title,
                         sourceRange: .init(start: 0, end: duration))
        title.title = "Review fixture"
        return .init(id: id, clips: [title])
    }
    var project = Project(name: "Comment anchor fixture")
    project.editRevision = 1
    project.sequences = [sequence("main", duration: 10), sequence("short", duration: 4)]
    return project
}

struct RangeDrag: Sendable {
    let start: Double
    let end: Double
    let expectedStart: Double
    let expectedEnd: Double
}

@Suite("Review comment anchors")
@MainActor
struct CommentAnchorTests {
    private func model() -> EditorModel {
        let model = EditorModel()
        let project = reviewFixture()
        model.project = project
        model.displayedProject = project
        model.selectedSequenceID = "main"
        return model
    }

    @Test func choosingAMomentReplacesAnOldRangeAndFrameSelection() {
        let model = model()
        model.selectCommentRange(from: 2, to: 8)
        model.commentRegion = .init(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        model.annotating = true
        model.selectedCommentID = "old-comment"
        model.commentDraft = "Keep this performance."
        model.panel = .media
        model.playing = true

        model.beginMomentComment(at: 14)

        #expect(model.commentScope == "moment")
        #expect(model.position == 10)
        #expect(model.selectionStart == 10 && model.selectionEnd == 10)
        #expect(model.commentRegion == nil && !model.annotating)
        #expect(model.selectedCommentID == nil)
        #expect(model.panel == .feedback && !model.playing)
        #expect(model.commentFocusPending)
        #expect(model.commentDraft == "Keep this performance.")

        model.beginMomentComment(at: -4)
        #expect(model.position == 0)
        #expect(model.selectionStart == 0 && model.selectionEnd == 0)
    }

    @Test(arguments: [
        RangeDrag(start: 2, end: 8, expectedStart: 2, expectedEnd: 8),
        RangeDrag(start: 8, end: 2, expectedStart: 2, expectedEnd: 8),
        RangeDrag(start: -5, end: 15, expectedStart: 0, expectedEnd: 10),
        RangeDrag(start: 15, end: -5, expectedStart: 0, expectedEnd: 10),
    ])
    func draggingInEitherDirectionCreatesAnInBoundsRange(_ drag: RangeDrag) {
        let model = model()
        model.commentDraft = "Give this a little room."
        model.panel = .transcript
        model.playing = true

        model.selectCommentRange(from: drag.start, to: drag.end)

        #expect(model.commentScope == "range")
        #expect(model.selectionStart == drag.expectedStart)
        #expect(model.selectionEnd == drag.expectedEnd)
        #expect(model.position == drag.expectedStart)
        #expect(model.panel == .feedback && !model.playing)
        #expect(model.commentFocusPending)
        #expect(model.commentDraft == "Give this a little room.")
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity])
    func invalidGestureTimesDoNotReplaceTheCurrentAnchor(_ invalid: Double) {
        let model = model()
        model.selectCommentRange(from: 2, to: 4, focus: false)

        model.selectCommentRange(from: invalid, to: 8)
        model.selectCommentRange(from: 1, to: invalid)
        model.beginMomentComment(at: invalid)

        #expect(model.commentScope == "range")
        #expect(model.selectionStart == 2 && model.selectionEnd == 4)
        #expect(model.position == 2)
        #expect(!model.commentFocusPending)
    }

    @Test func clickingWithoutADragChoosesAMomentInsteadOfAnEmptyRange() {
        let model = model()
        model.selectCommentRange(from: 2, to: 8)

        model.selectCommentRange(from: 5, to: 5)

        #expect(model.commentScope == "moment")
        #expect(model.position == 5)
        #expect(model.selectionStart == 5 && model.selectionEnd == 5)
    }

    @Test func adjustingAnExistingRangeDoesNotStealTextFocus() {
        let model = model()
        model.selectCommentRange(from: 2, to: 8)
        model.commentFocusPending = false // The composer has consumed the initial request.
        let request = model.commentFocusRequest

        model.selectCommentRange(from: 3, to: 7, focus: false)

        #expect(model.selectionStart == 3 && model.selectionEnd == 7)
        #expect(model.commentFocusRequest == request)
        #expect(!model.commentFocusPending)
    }

    @Test func wholeVideoCheckboxRestoresTheCurrentTemporalAnchor() {
        let model = model()
        model.selectCommentRange(from: 2, to: 4)
        model.setWholeVideoComment(true)
        #expect(model.commentScope == "cut")
        model.setWholeVideoComment(false)
        #expect(model.commentScope == "range")
        #expect(model.selectionStart == 2 && model.selectionEnd == 4)

        model.beginMomentComment(at: 6)
        model.setWholeVideoComment(true)
        model.setWholeVideoComment(false)
        #expect(model.commentScope == "moment")
        #expect(model.position == 6)
        #expect(model.selectionStart == 6 && model.selectionEnd == 6)
    }

    @Test func openingAnExistingMomentCannotResurrectAnOlderRange() {
        let model = model()
        let comment = ReviewComment(id: "moment", cutID: nil, editRevision: 1, sequenceID: "main",
                                    scope: "moment", range: nil, time: .init(seconds: 6), region: nil,
                                    text: "Hold this frame.", author: "Director", status: "open",
                                    anchors: [], transcriptContext: [], replies: [], createdAt: 0, cursor: 1)
        model.selectCommentRange(from: 1, to: 3)

        model.seekComment(comment)
        model.setWholeVideoComment(true)
        model.setWholeVideoComment(false)

        #expect(model.selectedCommentID == comment.id)
        #expect(model.commentScope == "moment")
        #expect(model.position == 6)
        #expect(model.selectionStart == 6 && model.selectionEnd == 6)
    }

    @Test func switchingSequencesClearsReviewAnchorsAndThePreviousSavedCut() {
        let model = model()
        model.selectCommentRange(from: 7, to: 9)
        model.commentRegion = .init(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        model.annotating = true
        model.selectedCommentID = "previous-note"
        model.selectedCutID = "previous-saved-cut"
        model.commentDraft = "A note still being written."

        model.selectSequence("short")

        #expect(model.selectedSequenceID == "short" && model.duration == 4)
        #expect(model.commentScope == "moment")
        #expect(model.position == 0 && model.selectionStart == 0 && model.selectionEnd == 0)
        #expect(model.selectedCutID == nil && model.selectedCommentID == nil)
        #expect(model.commentRegion == nil && !model.annotating)
        #expect(!model.commentFocusPending)
        #expect(model.commentDraft == "A note still being written.")
    }

    @Test func reviewingAnEarlierEmptyCutDiscardsAnchorsFromTheLongerEdit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("direction-anchor-" + UUID().uuidString + ".direction")
        let store = try ProjectStore.create(at: url, name: "Earlier cut")
        let runtime = try ToolRuntime(store: store)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: runtime.cacheDirectory)
        }
        let empty = try store.read()
        let model = model()
        // The current in-memory edit and persisted revision share one sequence identity.
        model.displayedProject?.id = empty.id
        model.displayedProject?.sequences[0].id = empty.sequences[0].id
        model.project = model.displayedProject
        model.selectedSequenceID = empty.sequences[0].id
        model.runtime = runtime
        model.selectCommentRange(from: 7, to: 9)
        model.commentRegion = .init(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        model.selectedCommentID = "later-note"
        model.commentDraft = "An unfinished thought."

        model.showRevision(0)

        #expect(model.displayedProject?.editRevision == 0 && model.duration == 0)
        #expect(model.commentScope == "moment")
        #expect(model.position == 0 && model.selectionStart == 0 && model.selectionEnd == 0)
        #expect(model.commentRegion == nil && model.selectedCommentID == nil)
        #expect(!model.commentFocusPending)
        #expect(model.commentDraft == "An unfinished thought.")
        #expect(model.error == nil)
    }

    @Test func openingNotesIsSignaledEvenWhenTheAnchorHasNotChanged() {
        let model = model()
        let comment = ReviewComment(id: "moment", cutID: nil, editRevision: 1, sequenceID: "main",
                                    scope: "moment", range: nil, time: .init(seconds: 6), region: nil,
                                    text: "Hold this frame.", author: "Director", status: "open",
                                    anchors: [], transcriptContext: [], replies: [], createdAt: 0, cursor: 1)
        model.beginMomentComment(at: 6)
        let focus = model.commentFocusRequest
        let navigation = model.notesNavigationRequest
        model.seekComment(comment)
        model.seekComment(comment)
        #expect(model.notesNavigationRequest == navigation + 2)
        #expect(model.commentFocusRequest == focus) // Viewing a saved note does not steal text focus.
        model.markIn()
        model.markOut()
        #expect(model.notesNavigationRequest == navigation + 4)
    }

    @Test func regionAnnotationLeavesWholeCutScopeAndKeepsTheDraft() {
        let model = model()
        model.selectCommentRange(from: 2, to: 4)
        model.setWholeVideoComment(true)
        model.commentDraft = "Tighter on her here."
        model.playing = true
        model.toggleRegionAnnotation()
        #expect(model.commentScope == "range")
        #expect(model.selectionStart == 2 && model.selectionEnd == 4)
        #expect(model.annotating && !model.playing)
        #expect(model.commentDraft == "Tighter on her here.")
        model.toggleRegionAnnotation()
        #expect(!model.annotating)
        model.beginMomentComment(at: 6)
        model.setWholeVideoComment(true)
        model.toggleRegionAnnotation()
        #expect(model.commentScope == "moment" && model.position == 6)
    }

    @Test func cutLabelsUseSavedNamesRatherThanInternalEditNumbers() {
        let model = model()
        model.pinnedRevision = 1
        #expect(model.cutLabel == "Earlier cut")
        model.cuts = [
            ReviewCut(id: "cut-2", name: "Cut 02", editRevision: 1, sequenceID: "main", createdAt: 0),
            ReviewCut(id: "other-sequence", name: "Other film", editRevision: 1, sequenceID: "short", createdAt: 1),
        ]
        #expect(model.cutLabel == "Cut 02")
        model.pinnedRevision = nil
        #expect(model.cutLabel == "Working cut")
        model.selectedCutID = "cut-2"
        #expect(model.cutLabel == "Cut 02")
    }
}
