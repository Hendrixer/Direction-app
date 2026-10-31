import SwiftUI
import DirectionCore

/// The picture with its transport: used by Notes, Changes, Finish and anywhere a cut plays
/// beside a panel. Black stage, 28 pt padding, aspect-fit frame, HUD timecode, then
/// play · timecode · scene strip · mark.
struct FilmStage<Overlay: View>: View {
    @Bindable var model: FilmModel
    var marks: [StripMark]? = nil
    var showsMarkButton = true
    var tallStrip = false
    var hudPrefix: String? = nil
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
                .contextMenu { PictureContextMenu(model: model) }
                .overlay(alignment: .bottomLeading) { HUDTag(hudPrefix.map { "\($0) · \(Timecode.format(model.position, fps: model.fps))" } ?? Timecode.format(model.position, fps: model.fps)).padding(12) }
                .overlay { if model.isPreparing { HStack(spacing: 8) { GateSpinner(); Text("Preparing picture").font(Gate.Font.small) }.padding(12).gateGlass(10) } }
                .position(x: g.size.width / 2, y: 28 + avail.height / 2)
            }
            FilmTransport(model: model, marks: marks, showsMarkButton: showsMarkButton, tall: tallStrip)
        }
        .background(Gate.Surface.canvas)
    }

    private func fit(_ aspect: CGFloat, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        return size.width / size.height > aspect ? CGSize(width: size.height * aspect, height: size.height) : CGSize(width: size.width, height: size.width / aspect)
    }
}

extension FilmStage where Overlay == EmptyView {
    init(model: FilmModel, marks: [StripMark]? = nil, showsMarkButton: Bool = true, tallStrip: Bool = false, hudPrefix: String? = nil) {
        self.init(model: model, marks: marks, showsMarkButton: showsMarkButton, tallStrip: tallStrip, hudPrefix: hudPrefix) { _ in EmptyView() }
    }
}

/// Play · timecode · scene strip · mark. Space plays; N marks.
struct FilmTransport: View {
    @Bindable var model: FilmModel
    var marks: [StripMark]? = nil
    var showsMarkButton = true
    var tall = false
    var body: some View {
        HStack(spacing: 12) {
            Button { model.togglePlayback() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill") }
                .buttonStyle(.gate(.normal, icon: true)).help(model.playing ? "Pause (Space)" : "Play (Space)")
            TimecodeLabel(time: model.position, total: model.duration, fps: model.fps)
            SceneStrip(scenes: model.stripScenes, duration: model.duration, playhead: model.position, marks: marks ?? model.noteMarks, range: model.anchorMode == .range ? model.rangeSelection : nil, tall: tall,
                       onSeek: { model.pause(); model.seek($0) },
                       onRange: { a, b in model.rangeSelection = a...b; model.anchorMode = .range }) { scene in SceneContextMenu(model: model, scene: scene) }
            if showsMarkButton {
                Button { model.mark() } label: { PinMark(size: 12) }
                    .buttonStyle(.gate(.ghost, icon: true)).help("Mark this moment (N)").accessibilityLabel("Mark this moment")
            }
            // How the screen and the camera share the frame, when there are both (layouts.md).
            if model.layouts.available(model) { LayoutButton(model: model) }
        }
        .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 16)
    }
}
