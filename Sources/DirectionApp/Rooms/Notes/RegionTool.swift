import SwiftUI
import AppKit
import DirectionCore

/// Drawn over the picture in the Cut room: a box around what a note is about (frame 19). Draw a box (R, or the
/// box under the picture) and the drag makes the note; the selected note's box moves and resizes. Boxes are
/// stored as fractions of the frame, never points. One box per note.
struct RegionLayer: View {
    @Bindable var model: FilmModel
    /// The picture's size in points.
    var size: CGSize
    @State private var drag: Drag?
    @State private var hovered = false

    private enum Handle: CaseIterable { case topLeading, top, topTrailing, trailing, bottomTrailing, bottom, bottomLeading, leading }
    /// `draw`'s `toolWasOn`: Draw a box was on when the drag began (a drag away from a selected box turns it on).
    private enum Drag { case draw(CGPoint, toolWasOn: Bool), move(CGRect), resize(CGRect, Handle) }

    /// Drawing a new box, or the selected note's box can still be moved and resized.
    private var interactive: Bool { model.notesTab == .sheet && (model.drawingRegion || (model.boxEditable && model.visibleRegion != nil)) }
    private var region: CGRect? { model.visibleRegion }
    private var label: String {
        let number = model.drawingRegion ? model.nextNoteNumber : (model.selectedNote?.number ?? model.nextNoteNumber)
        return "\(number) · box"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
            if let region {
                RegionOverlay(region: region, label: label, editing: model.drawingRegion || (interactive && hovered), dim: 0.35)
                    .transition(.opacity)
                    .accessibilityElement()
                    .accessibilityLabel(spoken(region))
                if interactive { handleCursors(region) }
            }
            if model.drawingStretch {
                glassHint("Drag along the timeline to mark a stretch.").frame(maxWidth: .infinity).padding(.top, 14)
            }
            if model.drawingRegion {
                hint.frame(maxWidth: .infinity).padding(.top, 14)
                if let region {
                    HUDTag("\(percent(region.width)) \u{00D7} \(percent(region.height))%")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(12)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .pointerStyle(model.drawingRegion ? .rectSelection : nil)
        .onHover { hovered = $0 }
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged(changed).onEnded(ended), including: interactive ? .all : .subviews)
        .animation(gateAnimation(Gate.Motion.snap), value: region == nil)
    }

    private var hint: some View { glassHint("Drag a box around what you mean.") }
    private func glassHint(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
            Kbd("esc")
            Text("cancels.")
        }
        .font(Gate.Font.small).foregroundStyle(Gate.Text.primary)
        .padding(.vertical, 7).padding(.horizontal, 10)
        .gateGlass(8)
        .fixedSize()
        .allowsHitTesting(false)
    }

    /// Resize cursors over the handles, a grab hand inside.
    @ViewBuilder private func handleCursors(_ r: CGRect) -> some View {
        let frame = rect(r)
        Color.clear.contentShape(Rectangle())
            .frame(width: max(0, frame.width - 12), height: max(0, frame.height - 12))
            .position(x: frame.midX, y: frame.midY)
            .pointerStyle(.grabIdle)
            .allowsHitTesting(!model.drawingRegion)
        ForEach(Handle.allCases, id: \.self) { h in
            Color.clear.contentShape(Rectangle()).frame(width: 14, height: 14)
                .position(point(h, in: frame))
                .pointerStyle(.frameResize(position: position(h)))
        }
    }

    // MARK: Dragging

    private func changed(_ value: DragGesture.Value) {
        guard size.width > 0, size.height > 0 else { return }
        if drag == nil {
            // The selected note's box takes a drag on it; anywhere else, a drag draws a new box and its note. A click
            // away from it does nothing: it neither turns Draw a box on nor pauses the picture.
            let shown = model.drawingRegion || !model.boxEditable ? nil : model.visibleRegion
            if let r = shown, let h = handle(at: value.startLocation, in: rect(r)) { drag = .resize(r, h) }
            else if let r = shown, rect(r).contains(value.startLocation) { drag = .move(r) }
            else {
                guard model.drawingRegion || hypot(value.translation.width, value.translation.height) > 3 else { return }
                drag = .draw(value.startLocation, toolWasOn: model.drawingRegion); model.region = nil; model.drawingRegion = true; model.pause()
            }
        }
        switch drag {
        case .draw(let start, _):
            let a = normalized(start), b = normalized(value.location)
            model.region = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .move(let r):
            let dx = value.translation.width / size.width, dy = value.translation.height / size.height
            model.region = CGRect(x: clamp(r.minX + dx, 0, 1 - r.width), y: clamp(r.minY + dy, 0, 1 - r.height), width: r.width, height: r.height)
        case .resize(let r, let h):
            model.region = resized(r, h, to: normalized(value.location), keepAspect: NSEvent.modifierFlags.contains(.shift))
        case nil: break
        }
    }

    private func ended(_ value: DragGesture.Value) {
        defer { drag = nil }
        switch drag {
        case .draw(_, let toolWasOn):
            if let r = model.region, r.width > 0.01, r.height > 0.01 { model.finishBox(new: true) }
            else { model.region = nil; if !toolWasOn { model.drawingRegion = false } }
        case .move, .resize: model.finishBox(new: false)
        case nil: break
        }
    }

    private func resized(_ r: CGRect, _ h: Handle, to p: CGPoint, keepAspect: Bool) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch h {
        case .topLeading: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topTrailing: maxX = p.x; minY = p.y
        case .trailing: maxX = p.x
        case .bottomTrailing: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeading: minX = p.x; maxY = p.y
        case .leading: minX = p.x
        }
        var out = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: max(0.02, abs(maxX - minX)), height: max(0.02, abs(maxY - minY)))
        if keepAspect, r.height > 0 {
            let aspect = r.width / r.height
            if [.top, .bottom].contains(h) { out.size.width = out.height * aspect } else { out.size.height = out.width / aspect }
        }
        out.origin.x = clamp(out.minX, 0, 1 - min(1, out.width)); out.origin.y = clamp(out.minY, 0, 1 - min(1, out.height))
        out.size.width = min(out.width, 1 - out.minX); out.size.height = min(out.height, 1 - out.minY)
        return out
    }

    // MARK: Geometry

    private func rect(_ r: CGRect) -> CGRect { CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height) }
    private func normalized(_ p: CGPoint) -> CGPoint { CGPoint(x: clamp(p.x / size.width, 0, 1), y: clamp(p.y / size.height, 0, 1)) }
    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), max(lo, hi)) }
    private func point(_ h: Handle, in f: CGRect) -> CGPoint {
        switch h {
        case .topLeading: CGPoint(x: f.minX, y: f.minY)
        case .top: CGPoint(x: f.midX, y: f.minY)
        case .topTrailing: CGPoint(x: f.maxX, y: f.minY)
        case .trailing: CGPoint(x: f.maxX, y: f.midY)
        case .bottomTrailing: CGPoint(x: f.maxX, y: f.maxY)
        case .bottom: CGPoint(x: f.midX, y: f.maxY)
        case .bottomLeading: CGPoint(x: f.minX, y: f.maxY)
        case .leading: CGPoint(x: f.minX, y: f.midY)
        }
    }
    private func handle(at p: CGPoint, in f: CGRect) -> Handle? {
        Handle.allCases.first { h in let q = point(h, in: f); return abs(q.x - p.x) <= 7 && abs(q.y - p.y) <= 7 }
    }
    private func position(_ h: Handle) -> FrameResizePosition {
        switch h {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .trailing: .trailing
        case .bottomTrailing: .bottomTrailing
        case .bottom: .bottom
        case .bottomLeading: .bottomLeading
        case .leading: .leading
        }
    }
    private func percent(_ v: CGFloat) -> String { String(Int((v * 100).rounded())) }
    private func spoken(_ r: CGRect) -> String { "Region, \(percent(r.width)) by \(percent(r.height)) percent, at left \(percent(r.minX)), top \(percent(r.minY))" }
}

