import Foundation
import DirectionCore

/// The film's shape (FilmShape): the brief sets it, the stage shows it, and changing it once there's a cut
/// puts the shots in whole with black where they don't reach, or asks the editor to fill the frame
/// (start.md › 03 · Shape, cut.md › Changing the shape).
extension FilmModel {
    /// The cut on screen's shape, the way a director says it ("9:16").
    var shapeLabel: String { sequence.map { FilmShape.label(width: $0.width, height: $0.height) } ?? "" }

    /// The footage's own shape, once there's footage.
    var footageShapeLabel: String? {
        guard let store, let size = project?.footageSize(film: store.url) else { return nil }
        return FilmShape.label(width: size.width, height: size.height)
    }

    /// What a brief with `shape` would do to the latest cut, when it would change its shape: the cut, its shape now
    /// and after, and whether it gets taller (black above and below its wide shots) or wider (at their sides).
    func shapeChange(to shape: FilmShape?) -> (cut: ReviewCut, from: String, to: String, taller: Bool)? {
        guard let cut = latestCut, let s = try? project?.sequence(cut.sequenceID) else { return nil }
        let size: (width: Int, height: Int)
        if isPreview {
            // Snapshots have no film on disk: the sample's first footage, or the cut's own shape.
            let v = project?.assets.first(where: { !$0.isImage && !$0.video.isEmpty })?.video.first
            let footage = v.map { (width: $0.width, height: $0.height) } ?? (width: s.width, height: s.height)
            size = shape.map { $0.size(footage: footage) } ?? footage
        } else {
            guard let store, let made = try? store.cutSize(for: shape) else { return nil }
            size = made
        }
        let from = FilmShape.label(width: s.width, height: s.height), to = FilmShape.label(width: size.width, height: size.height)
        guard from != to else { return nil }
        return (cut, from, to, Double(size.width) / Double(size.height) < Double(s.width) / Double(s.height))
    }

    /// Why the shape can't change now, when it can't.
    var shapeBlocker: String? {
        guard latestCut != nil else { return nil }
        if isPictureLocked { return "Picture is locked. Unlock it to change the shape." }
        if openTurnover != nil { return "The editor is making the next cut. Change the shape once it\u{2019}s handed back." }
        return nil
    }

    /// Changes the cut to `shape`: at once before anything's cut; with black where the shots don't reach once
    /// there's a cut, and with `fill` a note for the editor to fill the frame in the next turnover.
    func reshape(_ shape: FilmShape?, fill: Bool) -> (ok: Bool, note: String?) {
        guard let store, !isPreview else { return (true, nil) }
        let change = shapeChange(to: shape)
        do {
            let made = try store.reshape(shape)
            // As a layout does: the cut plays at its new size at once.
            refresh(force: true); loadDisplayed(force: true); preparePlayback(force: true)
            guard let made, let change else { return (true, nil) }
            let note = fill ? addNote(text: "Fill the \(change.to) frame: crop each shot instead of the black bars.", kind: .picture) : nil
            let detail = note.map { "Note \($0.number.map(String.init) ?? "") asks the editor to fill the frame. It goes in your next turnover." }
                ?? made.warnings.first ?? "Every shot is whole, with black where it doesn\u{2019}t reach."
            toast = Toast(title: "\(change.cut.name) is \(change.to) now", detail: detail)
            return (true, note?.id)
        } catch {
            self.error = (error as? DirectionError)?.message ?? error.localizedDescription
            return (false, nil)
        }
    }
}
