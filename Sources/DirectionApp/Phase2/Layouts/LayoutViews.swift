import SwiftUI
import DirectionCore

// Layouts (layouts.md): the director changes how the screen and the camera share the frame, at once,
// from the transport under the picture. No editor, no turnover; ⌘Z undoes.

@MainActor @Observable final class LayoutsModel {
    enum Scope: String, CaseIterable { case scene, selection, film }
    var scope: Scope = .scene
    var open = false
    private(set) var working = false
    var message: String?
    /// What the popover shows and changes: the layout at the playhead, or the standard one.
    var draft = FrameLayout.standard
    @ObservationIgnored private var prepared = false

    /// A camera and a screen recording are in sync somewhere in the film.
    func available(_ film: FilmModel) -> Bool {
        if film.isPreview { return true }
        guard let assets = film.project?.assets else { return false }
        return (film.dailies.syncGroups ?? []).contains { g in g.takes.filter { t in assets.contains { $0.id == t.assetID && !$0.video.isEmpty && !$0.isImage } }.count > 1 }
    }
    /// Why the latest cut can't change now, or nil when it can.
    func blocked(_ film: FilmModel) -> String? {
        guard let latest = film.latestCut else { return "There\u{2019}s no cut yet." }
        if film.watchedCut?.id != latest.id { return "Layouts change \(latest.name). Watch it to change them." }
        if film.directing.pictureLocked { return "Picture is locked." }
        if let p = film.project, latest.editRevision != p.editRevision { return "The editor is making the next cut." }
        return nil
    }
    func current(_ film: FilmModel) -> FrameLayout? { film.sequence?.layout(at: film.position) }

    /// The stretch a change covers: the scene at the playhead, the selection on the strip, or the film.
    func range(_ film: FilmModel) -> MediaRange? {
        switch scope {
        case .film: return nil
        case .selection: return film.rangeSelection.map { MediaRange(start: $0.lowerBound, end: $0.upperBound) }
        case .scene: return film.stripScene(at: film.position).map { MediaRange(start: $0.start, end: $0.end) }
        }
    }

    func show(_ film: FilmModel) {
        draft = current(film) ?? draft
        if film.rangeSelection != nil && film.anchorMode == .range { scope = .selection } else if scope == .selection { scope = .scene }
        message = nil
        open = true
        prepare(film)
    }

    /// Faces are found the first time the control shows, so the first change doesn't wait on them.
    func prepare(_ film: FilmModel) {
        guard !prepared, !film.isPreview, let runtime = film.runtime else { return }
        prepared = true
        Task { await runtime.prepareLayouts() }
    }

    func apply(_ layout: FrameLayout, film: FilmModel) {
        draft = layout
        guard !working else { return }
        if let why = blocked(film) { message = why; return }
        guard !film.isPreview, let runtime = film.runtime else { return }
        let r = range(film)
        working = true; message = nil
        Task {
            defer { working = false }
            do {
                let made = try await runtime.setLayout(layout, range: r)
                if let w = made.warnings.first { message = w }
                film.registerUndo("Change Layout") { m in m.layouts.undo(made.editRevision, redo: (layout, r), film: m) }
                reload(film)
            } catch { message = (error as? DirectionError)?.message ?? error.localizedDescription }
        }
    }

    /// Undo: the cut goes back to before the change while nothing else has changed since.
    func undo(_ revision: Int, redo: (FrameLayout, MediaRange?), film: FilmModel) {
        guard let store = film.store else { return }
        do {
            try store.undoDirectorEdit(revision: revision)
            film.registerUndo("Change Layout") { m in
                let saved = m.layouts.scope
                m.layouts.reapply(redo.0, range: redo.1, film: m)
                m.layouts.scope = saved
            }
            reload(film)
        } catch { film.error = (error as? DirectionError)?.message ?? error.localizedDescription }
    }

    /// Redo: the same layout over the same stretch.
    private func reapply(_ layout: FrameLayout, range: MediaRange?, film: FilmModel) {
        guard let runtime = film.runtime else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let made = try await runtime.setLayout(layout, range: range)
                film.registerUndo("Change Layout") { m in m.layouts.undo(made.editRevision, redo: (layout, range), film: m) }
                reload(film)
            } catch { film.error = (error as? DirectionError)?.message ?? error.localizedDescription }
        }
    }

    private func reload(_ film: FilmModel) {
        film.refresh(force: true)
        film.loadDisplayed(force: true)
        film.preparePlayback(force: true)
    }
}

/// The transport's Layout button: a drawing of the layout at the playhead. Opens the picker.
struct LayoutButton: View {
    @Bindable var model: FilmModel
    private var layouts: LayoutsModel { model.layouts }
    var body: some View {
        let current = layouts.current(model)
        Button { layouts.open ? (layouts.open = false) : layouts.show(model) } label: {
            LayoutGlyph(layout: current, size: CGSize(width: 22, height: 14), lit: layouts.open)
        }
        .buttonStyle(.gate(.ghost, icon: true))
        .help(current.map { "Layout: \($0.label)" } ?? "Layout")
        .accessibilityLabel("Layout")
        .accessibilityValue(current?.label ?? "As cut")
        .popover(isPresented: Binding(get: { layouts.open && !model.isPreview }, set: { layouts.open = $0 }), arrowEdge: .top) {
            LayoutPicker(model: model).background(Gate.Surface.panel)
        }
        .onAppear { layouts.prepare(model) }
    }
}

/// The picker (layouts.md › Where the director sets it): four layouts, then the bubble's corner, size and
/// shape, the screen's framing, and what it applies to. Every choice applies at once.
struct LayoutPicker: View {
    @Bindable var model: FilmModel
    private var layouts: LayoutsModel { model.layouts }

    var body: some View {
        let d = layouts.draft
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Layout").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                Spacer(minLength: 0)
                if layouts.working { GateSpinner() }
            }
            HStack(spacing: 8) {
                ForEach(FrameLayout.Kind.allCases, id: \.self) { kind in tile(kind, on: layouts.current(model)?.kind == kind) }
            }
            if d.kind == .screenAndYou {
                row("Corner") { CornerPicker(corner: Binding(get: { d.corner }, set: { c in change { $0.corner = c } })) }
                row("Size") { GateSegmented(options: FrameLayout.Size.allCases.map { ($0, $0.label) }, selection: Binding(get: { d.size }, set: { s in change { $0.size = s } })) }
                row("Shape") { GateSegmented(options: FrameLayout.Shape.allCases.map { ($0, $0.label) }, selection: Binding(get: { d.shape }, set: { s in change { $0.shape = s } })) }
            }
            if d.kind == .screen || d.kind == .screenAndYou {
                row("Screen") { GateSegmented(options: FrameLayout.Screen.allCases.map { ($0, $0.label) }, selection: Binding(get: { d.screen }, set: { s in change { $0.screen = s } })) }
            }
            row("Apply to") {
                GateSegmented(options: [(LayoutsModel.Scope.scene, "Scene")] + (model.rangeSelection != nil ? [(.selection, "Selection")] : []) + [(.film, "Film")], selection: Binding(get: { layouts.scope }, set: { layouts.scope = $0 }))
            }
            if let message = layouts.message ?? layouts.blocked(model) {
                Text(message).font(.system(size: 11.5)).foregroundStyle(Gate.State.alert).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Changes the cut at once. \u{2318}Z undoes.").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }

    /// One layout, drawn: picking it applies it with the options above.
    private func tile(_ kind: FrameLayout.Kind, on: Bool) -> some View {
        var l = layouts.draft; l.kind = kind
        return Button { layouts.apply(l, film: model) } label: {
            VStack(spacing: 6) {
                LayoutGlyph(layout: l, size: CGSize(width: 52, height: 30), lit: on)
                Text(kind.label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(on ? Gate.Text.primary : Gate.Text.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }
            .padding(.vertical, 6).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).fill(on ? Gate.Surface.hover : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).strokeBorder(on ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(layouts.working)
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func change(_ edit: (inout FrameLayout) -> Void) {
        var l = layouts.draft; edit(&l)
        layouts.apply(l, film: model)
    }

    private func row<Control: View>(_ label: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary).frame(width: 64, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }
}

/// Four dots, one a corner.
struct CornerPicker: View {
    @Binding var corner: FrameLayout.Corner
    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow { dot(.topLeft); dot(.topRight) }
            GridRow { dot(.bottomLeft); dot(.bottomRight) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Gate.Surface.sunken))
    }
    private func dot(_ c: FrameLayout.Corner) -> some View {
        Button { corner = c } label: {
            Circle().fill(corner == c ? Gate.Text.primary : Gate.Line.strong).frame(width: 9, height: 9).frame(width: 16, height: 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.label.capitalized)
        .accessibilityAddTraits(corner == c ? .isSelected : [])
    }
}

/// A layout drawn small, from the same geometry the renderer uses: the frame, the screen, the camera.
struct LayoutGlyph: View {
    var layout: FrameLayout?
    var size: CGSize
    var lit = false
    var body: some View {
        let frame = LayoutGeometry.Size(16, 9)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2.5).fill(Gate.Surface.sunken)
            if let l = layout {
                if l.kind != .you { shape(LayoutGeometry.screenRect(l, frame: frame, screen: .init(16, 9)), radius: l.kind == .sideBySide || l.screen == .framed ? 1.5 : 0, Gate.Steel.ramp[6]) }
                if l.kind != .screen {
                    let r = LayoutGeometry.cameraRect(l, frame: frame)
                    shape(r, radius: l.kind == .screenAndYou ? min(r.w * size.width, r.h * size.height) * l.shape.radius : l.kind == .sideBySide ? 1.5 : 0, lit ? Gate.Text.primary : Gate.Text.secondary)
                }
            } else {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: size.height * 0.6, weight: .medium)).foregroundStyle(Gate.Text.tertiary).frame(width: size.width, height: size.height)
            }
            RoundedRectangle(cornerRadius: 2.5).strokeBorder(lit ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 2.5))
    }
    private func shape(_ r: LayoutGeometry.Rect, radius: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
            .frame(width: r.w * size.width, height: r.h * size.height)
            .offset(x: r.x * size.width, y: r.y * size.height)
    }
}
