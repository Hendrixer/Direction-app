import SwiftUI
import DirectionCore

/// The picture with its transport: used by the Cut room, Finish and anywhere a cut plays
/// beside a panel. Black stage, 28 pt padding, aspect-fit frame with a hairline at its edge (so black in the
/// picture reads apart from the stage around it), the shape's tag, then
/// play · time · scene strip · the four ways to make a note, and in the Cut room Play changes and Watch through.
struct FilmStage<Overlay: View>: View {
    @Bindable var model: FilmModel
    var marks: [StripMark]? = nil
    var showsMarkButton = true
    var tallStrip = false
    /// The Cut room's ways to watch: Play changes when the cut has any, and Watch through (W).
    var showsWatch = false
    /// Drawn over the picture, in picture coordinates (regions, A/B tags).
    @ViewBuilder var overlay: (CGSize) -> Overlay

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { g in
                let avail = CGSize(width: g.size.width - 56, height: g.size.height - 36)
                let size = fit(model.aspect, in: avail)
                ZStack {
                    PictureView(player: model.isPreview ? nil : model.player, still: model.isPreview ? model.stripScene(at: model.position)?.art ?? .room : nil, aspect: model.aspect)
                    overlay(size)
                }
                .frame(width: size.width, height: size.height)
                .overlay { Rectangle().strokeBorder(Gate.Line.strong, lineWidth: 1).padding(-1).allowsHitTesting(false) }
                .contextMenu { PictureContextMenu(model: model) }
                .overlay(alignment: .bottomLeading) {
                    if let s = model.sequence, s.width > 0 {
                        ShapeTag(width: s.width, height: s.height).padding(12)
                            .help("The cut is \(model.shapeLabel), \(s.width) \u{00D7} \(s.height). Black inside the line is in the picture.")
                    }
                }
                .overlay { if model.isPreparing { HStack(spacing: 8) { GateSpinner(); Text("Preparing picture").font(Gate.Font.small) }.padding(12).gateGlass(10) } }
                .position(x: g.size.width / 2, y: 28 + avail.height / 2)
            }
            FilmTransport(model: model, marks: marks, showsMarkButton: showsMarkButton, tall: tallStrip, showsWatch: showsWatch)
        }
        .background(Gate.Surface.canvas)
    }

    private func fit(_ aspect: CGFloat, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        return size.width / size.height > aspect ? CGSize(width: size.height * aspect, height: size.height) : CGSize(width: size.width, height: size.width / aspect)
    }
}

extension FilmStage where Overlay == EmptyView {
    init(model: FilmModel, marks: [StripMark]? = nil, showsMarkButton: Bool = true, tallStrip: Bool = false, showsWatch: Bool = false) {
        self.init(model: model, marks: marks, showsMarkButton: showsMarkButton, tallStrip: tallStrip, showsWatch: showsWatch) { _ in EmptyView() }
    }
}

/// Play · timecode · scene strip · mark. Space plays; N marks.
struct FilmTransport: View {
    @Bindable var model: FilmModel
    var marks: [StripMark]? = nil
    var showsMarkButton = true
    var tall = false
    var showsWatch = false
    var body: some View {
        HStack(spacing: 12) {
            Button { model.togglePlayback() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill") }
                .buttonStyle(.gate(.normal, icon: true)).help(model.playing ? "Pause (Space)" : "Play (Space)")
            TimecodeLabel(time: model.position, total: model.duration, fps: model.fps, showsFrames: model.showsFrames && !model.playing)
            // A notice showing its passage on the strip shows it, read-only; the pointer on the strip puts the
            // selected note's stretch back, to pull longer or shorter or move. Mark a stretch (or ⌥- or ⇧-drag)
            // draws a new one, and letting go makes its note.
            let showing = model.notesUI.stripHighlight != nil, notes = showsMarkButton && !model.looksBack
            SceneStrip(scenes: model.stripScenes, duration: model.duration, playhead: model.position, marks: marks ?? model.noteMarks, range: model.stripRange, tall: tall,
                       onSeek: { model.pause(); model.seek($0) },
                       onRange: showing || !notes ? nil : { a, b in model.rangeSelection = a...b },
                       rangeEditable: model.drawingStretch || model.stretchEditable, drawsOnDrag: model.drawingStretch,
                       onRangeEnd: { new in model.finishStretch(new: new) }) { scene in SceneContextMenu(model: model, scene: scene) }
                .onHover { if $0 && showing { model.endStripHighlight() } }
            if showsMarkButton { NoteTools(model: model) }
            if showsWatch { watch }
        }
        .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 16)
    }
}

extension FilmTransport {
    /// Only what moved, then the whole cut: the two ways to watch from the Cut room (specs/cut.md).
    @ViewBuilder fileprivate var watch: some View {
        let reel = model.changesDuration(in: model.watchedCut)
        if reel > 0 {
            Button { model.openChangesReel() } label: { Text("Play changes") }
                .buttonStyle(.gate(.ghost)).fixedSize()
                .help("Play only what the editor changed, \(Timecode.duration(reel)) with handles (\u{21E7}\u{2318}P)")
        }
        Button { model.watchThrough() } label: { Text("Watch through") }
            .buttonStyle(.gate(.ghost)).fixedSize()
            .help("Watch \(model.watchedCut?.name ?? "the cut") straight through, full screen. N marks a moment (W)")
    }
}

/// The four ways to make a note, under the picture: a moment, a stretch of the strip, a box on the picture,
/// and the whole cut. Each one is a note at once, with no words yet (specs/cut.md › Making a note).
struct NoteTools: View {
    @Bindable var model: FilmModel
    var body: some View {
        HStack(spacing: 2) {
            Button { model.mark() } label: { PinMark(size: 12) }
                .buttonStyle(.gate(.ghost, icon: true)).help("Mark this moment (N)").accessibilityLabel("Mark this moment")
            tool("arrow.left.and.right", "Mark a stretch", help: "Mark a stretch: drag along the timeline", on: model.drawingStretch) {
                if model.drawingStretch { model.cancelDrawing() } else { model.beginStretch() }
            }
            tool("viewfinder", "Draw a box", help: "Draw a box around something in the picture (R)", on: model.drawingRegion) {
                if model.drawingRegion { model.cancelDrawing() } else { model.beginRegion() }
            }
            tool("text.bubble", "Note on the whole cut", help: "Note on the whole cut", on: false) { model.noteWholeCut() }
        }
        .disabled(model.duration <= 0 || model.looksBack)
    }

    private func tool(_ icon: String, _ label: String, help: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(on ? Gate.Voice.director : Gate.Text.secondary) }
            .buttonStyle(.gate(.ghost, icon: true))
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Gate.Voice.directorWash : .clear))
            .help(on ? "\(help). esc stops." : help)
            .accessibilityLabel(label).accessibilityAddTraits(on ? .isSelected : [])
    }
}
