import SwiftUI
import AppKit
import AVKit
import DirectionCore

/// One take open (frame 08): the picture with its own transport and the setup's takes in a reel;
/// beside it the editor's reason, the transcript and the circle button.
/// ← → change takes and keep the place within the line, so readings can be compared.
struct DailiesTakeViewer: View {
    @Bindable var model: FilmModel
    var takeID: String
    var bin: String?
    @Environment(\.dailiesPreview) private var preview
    @State private var player = DailiesTakePlayer()
    @FocusState private var focused: Bool

    private var take: TakeInfo? { model.dailies.takes[takeID] }
    private var asset: MediaAsset? { model.asset(takeID) }
    /// The take's own frame rate: its timecodes count frames the way its shots do.
    private var fps: Double { asset?.video.first?.frameRate ?? 24 }
    private var duration: Double { model.dailiesDuration(takeID) }
    private var lines: [DailiesLine] { model.dailiesLines(takeID) }
    private var position: Double { model.isPreview ? preview.takePosition ?? 0 : player.position }
    private var playing: Bool { model.isPreview ? preview.takePlaying : player.playing }
    private var art: FootageArt { preview.art[takeID] ?? model.dailiesArt(takeID) }

    /// Takes grouped the way ↑ ↓ walk them: the scene's setups, or the whole bin as one row.
    private var rows: [[TakeInfo]] {
        if let t = take, let sceneID = t.sceneID, model.scene(sceneID) != nil { return model.dailiesSetups(inScene: sceneID).map(\.takes).filter { !$0.isEmpty } }
        let all = model.dailiesTakes(inBin: bin)
        return [all.isEmpty ? [take].compactMap { $0 } : all]
    }
    private var reel: [TakeInfo] { rows.first { $0.contains { $0.assetID == takeID } } ?? [] }
    private var setupDescription: String? {
        guard let t = take, let scene = model.scene(t.sceneID) else { return nil }
        return scene.setups.first { $0.code == t.setupCode }?.description
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                head
                picture.frame(maxWidth: .infinity, maxHeight: .infinity)
                transport
                // Frame 59: the take's shots, once Direction has looked at it.
                if hasShots { DailiesShotsRow(model: model, takeID: takeID, position: position) { seek($0) } }
                else if model.indexFailed(takeID) { indexFailedRow }
                reelRow
            }
            .background(Gate.Surface.canvas)
            info.frame(width: 320)
        }
        .focusable().focusEffectDisabled().focused($focused)
        .onAppear { focused = true; player.load(asset, at: startTime, autoplay: false) }
        .onChange(of: takeID) { old, new in
            let at = carriedPosition(from: old, to: new)
            let wasPlaying = player.playing
            player.load(model.asset(new), at: at, autoplay: wasPlaying)
        }
        .onDisappear { player.stop() }
        .onMoveCommand(perform: move)
        .onExitCommand { back() }
        .onKeyPress(phases: .down) { press in keys(press) }
    }

    // MARK: Viewer

    private var head: some View {
        HStack(spacing: 10) {
            Button { back() } label: { Label("All takes", systemImage: "chevron.left") }
                .buttonStyle(.gate(.ghost, .small)).help("Back to the takes (Esc)")
            Rectangle().fill(Gate.Line.subtle).frame(width: 1, height: 16)
            if let take { Text(model.dailiesLabel(take)).font(Gate.Font.title).foregroundStyle(Gate.Text.primary) }
            Text([setupDescription, asset?.name].compactMap { $0 }.joined(separator: " \u{00B7} ")).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if take?.suggestion != nil {
                HStack(spacing: 5) { GemMark(size: 6.4); Text("Suggested") }
                    .font(Gate.Font.mono).foregroundStyle(Gate.Voice.agent)
                    .padding(.horizontal, 7).frame(height: Gate.Size.chip)
                    .background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(Gate.Voice.agentWash))
                    .accessibilityLabel("Suggested by the editor")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var picture: some View {
        GeometryReader { g in
            let width = max(0, g.size.width - 40), height = min(width * 9 / 16, max(0, g.size.height - 8))
            let w = height * 16 / 9
            ZStack {
                Gate.Surface.canvas
                if model.isPreview { FootageArtView(art: art) }
                else if player.missing {
                    VStack(spacing: 6) {
                        Image(systemName: "questionmark.folder").font(.system(size: 22)).foregroundStyle(Gate.Text.tertiary)
                        Text("This file isn't where it was.").font(Gate.Font.body).foregroundStyle(Gate.Text.secondary)
                        Text(asset?.path ?? "").font(Gate.Font.small).foregroundStyle(Gate.Text.disabled).lineLimit(1).truncationMode(.middle).frame(maxWidth: 420)
                    }
                } else { PlayerSurface(player: player.player).allowsHitTesting(false) }
            }
            .frame(width: w, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.frame))
            .overlay(alignment: .bottomTrailing) { HUDTag("\(Timecode.format(position, fps: fps)) / \(Timecode.duration(duration))").padding(12) }
            .contentShape(Rectangle())
            .onTapGesture { toggle() }
            .position(x: g.size.width / 2, y: g.size.height / 2)
            .accessibilityElement().accessibilityLabel("Picture, \(take.map(model.dailiesLabel) ?? "")").accessibilityAddTraits(.isButton)
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button { toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                .buttonStyle(.gate(.normal, icon: true)).help(playing ? "Pause (Space)" : "Play (Space)")
            TimecodeLabel(time: position, total: duration, fps: fps)
            DailiesTakeStrip(position: position, duration: duration, asset: asset, art: art, preview: model.isPreview, shots: hasShots ? model.index.shots(takeID) : [], sounds: model.index.sounds(takeID)) { player.seek($0) }
            Button { player.muted.toggle() } label: { Image(systemName: player.muted ? "speaker.slash" : "speaker.wave.2") }
                .buttonStyle(.gate(.ghost, icon: true)).help(player.muted ? "Unmute" : "Mute")
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, hasShots ? 4 : 6)
    }

    private var hasShots: Bool { !model.index.shots(takeID).isEmpty && !(asset?.video.isEmpty ?? true) }
    /// Where the take starts: at a shot when it was opened from search, else the top.
    private var startTime: Double {
        guard let at = model.index.openAt, at.assetID == takeID else { return 0 }
        model.index.openAt = nil
        return at.time
    }
    private func seek(_ t: Double) { if model.isPreview { return }; player.seek(t) }

    private var indexFailedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary)
            Text("Couldn\u{2019}t look at this take").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            Button("Try Again") { model.index.retry(takeID, film: model) }.buttonStyle(.gate(.ghost, .small))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private var reelRow: some View {
        HStack(spacing: 8) {
            ForEach(reel) { t in
                Button { model.openTakeID = t.assetID } label: {
                    DailiesTakePicture(model: model, take: t, selected: t.assetID == takeID, showsNumber: true)
                        .frame(width: 150)
                        .opacity(t.unusable ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .help(model.dailiesLabel(t))
                .accessibilityLabel("\(model.dailiesLabel(t))\(t.circled ? ", circled" : "")\(t.assetID == takeID ? ", open" : "")")
            }
            Spacer(minLength: 8)
            Text("\u{2190} \u{2192} takes \u{00B7} \u{2191} \u{2193} setups").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 18)
        .hairlineBorder(.top)
    }

    // MARK: Info panel

    private var info: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let reason = take?.suggestionReason { DailiesSayLine(text: reason.main, detail: reason.more) }
                else if let take {
                    Text(model.dailiesCaption(take)).font(Gate.Font.body).foregroundStyle(Gate.Text.secondary)
                    if !take.flags.isEmpty { Text(take.flags.joined(separator: " \u{00B7} ")).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary) }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .hairlineBorder(.bottom)
            if let group = model.dailies.syncGroup(for: takeID) { angles(group) }
            transcript.frame(maxHeight: .infinity)
            footer
        }
        .background(Gate.Surface.ground)
        .hairlineBorder(.leading)
    }

    /// Takes in sync with this one: switch between them at the same moment.
    private func angles(_ group: SyncGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionLabel("Angles")
                Spacer()
                Text("In sync by sound").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
            }
            HStack(spacing: 6) {
                ForEach(group.takes, id: \.assetID) { t in
                    let label = model.dailiesLabel(model.dailies.take(t.assetID)), open = t.assetID == takeID
                    Button { if !open { model.openTakeID = t.assetID } } label: {
                        HStack(spacing: 5) {
                            if t.assetID == group.soundAssetID { Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(Gate.Text.tertiary) }
                            Text(label).font(.system(size: 12, weight: open ? .semibold : .regular, design: .monospaced))
                        }
                        .padding(.horizontal, 9).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(open ? Gate.Surface.raised : .clear).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(open ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1)))
                        .contentShape(Rectangle())
                    }
                    // A circled angle reads in the director's color: circling any of them asks for the moment.
                    .buttonStyle(.plain).foregroundStyle(model.dailies.take(t.assetID).circled ? Gate.Voice.director : open ? Gate.Text.primary : Gate.Text.secondary)
                    .help(t.assetID == group.soundAssetID ? "\(label): the cut uses this take\u{2019}s sound" : "\(label), \(Self.offsetText(t.offset)) from the sound take")
                    .accessibilityLabel("\(label)\(model.dailies.take(t.assetID).circled ? ", circled" : "")\(t.assetID == group.soundAssetID ? ", its sound is used" : "")\(open ? ", open" : "")")
                }
            }
            // A camera and a screen: how they share the frame in the cut (layouts.md). The assembly follows it.
            if model.layouts.available(model) {
                HStack(spacing: 8) {
                    Text("In the cut").font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary)
                    Spacer(minLength: 0)
                    GateSelect(options: Self.layouts(model).map { ($0, $0.label) }, selection: Binding(get: { model.directing.layout ?? model.layouts.starting(model) }, set: { l in model.perform { _ = try $0.updateDirectingState(summary: "Layout for the film: \(l.label)") { $0.layout = l } } }))
                }
                .padding(.top, 2)
                .help("How the camera and the screen recording share the frame. The editor lays out the cut with it; change any scene from the Layout button under the picture.")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .hairlineBorder(.bottom)
    }

    /// The layouts Dailies offers for the film: the style's by name, then you in each corner, then the rest.
    static func layouts(_ model: FilmModel) -> [FrameLayout] {
        let named = model.appliedStyle.layouts
        return named + filmLayouts.filter { l in !named.contains { $0.unnamed == l } }
    }
    static let filmLayouts: [FrameLayout] = FrameLayout.Corner.allCases.reversed().map { FrameLayout(kind: .screenAndYou, corner: $0) } + [FrameLayout(kind: .sideBySide), FrameLayout(kind: .you), FrameLayout(kind: .screen)]

    /// "89 ms early", "1.2 s late".
    static func offsetText(_ offset: Double) -> String {
        let ms = abs(offset) * 1000
        let amount = ms < 1000 ? "\(Int(ms.rounded())) ms" : String(format: "%.1f s", abs(offset))
        return offset == 0 ? "in step" : "\(amount) \(offset > 0 ? "late" : "early")"
    }

    /// No words yet: say why, truthfully, and offer the way out.
    @ViewBuilder private var emptyTranscript: some View {
        switch model.isPreview ? .none : model.transcriptStatus(takeID) {
        case .transcribing:
            HStack(spacing: 8) { GateSpinner(); Text("Transcribing\u{2026}").font(Gate.Font.body).foregroundStyle(Gate.Text.secondary) }
        case .waiting:
            Text("Waiting to transcribe").font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary)
        case .failed(let why):
            Text("Couldn\u{2019}t transcribe this take.").font(Gate.Font.body).foregroundStyle(Gate.Text.secondary)
            Text(why).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { model.index.transcribeAgain(takeID, film: model) }.buttonStyle(.gate(.normal, .small))
        case .words, .none:
            Text("No dialogue").font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary)
            DailiesWaveform().frame(height: 40)
            if asset?.audio.isEmpty == false, !model.isPreview {
                Button("Transcribe") { model.index.transcribeAgain(takeID, film: model) }.buttonStyle(.gate(.ghost, .small))
            }
        }
    }

    private var transcript: some View {
        let current = lines.lastIndex { $0.start <= position + 0.001 }
        let flub = take.flatMap(model.dailiesFlub)
        return ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel("Transcript")
                        Spacer()
                        if !lines.isEmpty, !model.isPreview, model.transcriptStatus(takeID) != .transcribing {
                            Button("Transcribe Again") { model.index.transcribeAgain(takeID, film: model) }.buttonStyle(.gate(.ghost, .small))
                                .help("Make this take\u{2019}s words again with the engine in Settings \u{203A} Engines")
                        }
                    }
                    if lines.isEmpty { emptyTranscript }
                    ForEach(lines) { line in
                        let state = current.map { line.id < $0 ? -1 : line.id == $0 ? 0 : 1 } ?? 1
                        Button { player.seek(line.start) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(String(format: "%02d:%02d", Int(line.start) / 60, Int(line.start) % 60))
                                    .font(Gate.Font.mono).foregroundStyle(state == 0 ? Gate.Text.primary : Gate.Text.disabled).frame(width: 52, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(line.text).font(.system(size: 13)).italic(line.direction)
                                        .foregroundStyle(line.direction || state < 0 ? Gate.Text.tertiary : state == 0 ? Gate.Text.primary : Gate.Text.secondary)
                                        .lineSpacing(3).padding(.vertical, 1.5).fixedSize(horizontal: false, vertical: true)
                                    if let flub, flub.1 >= line.start, flub.1 < max(line.end, line.start + 0.5) { Chip(flub.0, style: .bad, mono: false) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).id(line.id)
                        .accessibilityLabel("\(line.text), at \(Int(line.start)) seconds")
                        .accessibilityAddTraits(state == 0 ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: current) { _, line in
                guard let line, !model.isPreview else { return }
                withAnimation(gateAnimation(Gate.Motion.glide)) { scroll.scrollTo(line, anchor: UnitPoint(x: 0, y: 0.33)) }
            }
        }
    }

    private var footer: some View {
        let circled = take?.circled ?? false, unusable = take?.unusable ?? false
        return VStack(spacing: 10) {
            Button { if let take { model.setCircle(take.assetID, !take.circled) } } label: {
                HStack(spacing: 10) {
                    ZStack {
                        if circled { HandCircle().fill(Gate.Voice.director.opacity(0.3)) }
                        HandCircle().stroke(Gate.Voice.director, style: .init(lineWidth: 1.8, lineCap: .round))
                    }.frame(width: 26, height: 20)
                    Text(circled ? "Circled" : "Circle this take")
                    Kbd("C").padding(.leading, 4)
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Voice.director)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(circled ? Gate.Voice.directorWash : .clear))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Gate.Voice.director.opacity(0.55), lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).disabled(unusable).opacity(unusable ? 0.4 : 1)
            .help(circled ? "Uncircle (C)" : "Circle this take (C)")
            .accessibilityLabel(circled ? "Uncircle \(take.map(model.dailiesLabel) ?? "")" : "Circle \(take.map(model.dailiesLabel) ?? "")")
            HStack(spacing: 8) {
                Button { if let take { model.setUnusable(take.assetID, !take.unusable) } } label: {
                    HStack(spacing: 6) { Image(systemName: "trash"); Text(unusable ? "Usable again" : "Not usable"); KeyHint("X") }
                }.buttonStyle(.gate(.ghost, .small))
                Spacer(minLength: 8)
                Button { model.go(.script) } label: { Label("Open in Script", systemImage: "doc.text") }.buttonStyle(.gate(.ghost, .small))
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .hairlineBorder(.top)
    }

    // MARK: Behavior

    private func back() { player.stop(); model.openTakeID = nil }
    private func toggle() { if model.isPreview { return }; player.toggle() }

    private func move(_ direction: MoveCommandDirection) {
        let rows = rows
        guard let r = rows.firstIndex(where: { $0.contains { $0.assetID == takeID } }), let i = rows[r].firstIndex(where: { $0.assetID == takeID }) else { return }
        switch direction {
        case .left: if i > 0 { model.openTakeID = rows[r][i - 1].assetID }
        case .right: if i + 1 < rows[r].count { model.openTakeID = rows[r][i + 1].assetID }
        case .up: if r > 0 { model.openTakeID = rows[r - 1][min(i, rows[r - 1].count - 1)].assetID }
        case .down: if r + 1 < rows.count { model.openTakeID = rows[r + 1][min(i, rows[r + 1].count - 1)].assetID }
        @unknown default: break
        }
    }

    private func keys(_ press: KeyPress) -> KeyPress.Result {
        guard !TextInput.hasFocus, press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
        if press.key == .space { toggle(); return .handled }
        switch press.characters.lowercased() {
        case "c": if let take, !take.unusable { model.setCircle(take.assetID, !take.circled) }; return .handled
        case "x": if let take { model.setUnusable(take.assetID, !take.unusable) }; return .handled
        case "j": player.shuttle(player.player.rate < 0 ? player.player.rate * 2 : -1); return .handled
        case "k": player.shuttle(0); return .handled
        case "l": player.shuttle(player.player.rate > 0 ? min(4, player.player.rate * 2) : 1); return .handled
        default: return .ignored
        }
    }

    /// The same moment in the next take: same line (by its words, else its place), same offset into it.
    private func carriedPosition(from old: String, to new: String) -> Double {
        let pos = player.position, newDuration = model.dailiesDuration(new)
        // An angle of the same moment: exactly where this one is.
        if let t = model.dailies.syncedTime(pos, from: old, to: new) { return min(max(0, t), max(0, newDuration - 0.05)) }
        let a = model.dailiesLines(old), b = model.dailiesLines(new)
        func words(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0 == " " } }
        if let i = a.lastIndex(where: { $0.start <= pos }) {
            let offset = pos - a[i].start
            if let j = b.firstIndex(where: { words($0.text) == words(a[i].text) }) ?? (b.indices.contains(i) ? i : nil) {
                return min(b[j].start + offset, max(0, newDuration - 0.05))
            }
        }
        let oldDuration = model.dailiesDuration(old)
        return oldDuration > 0 ? min(newDuration, pos / oldDuration * newDuration) : 0
    }
}

/// The take's own strip: one segment, playhead, click or drag to seek. Once the take is indexed
/// it's 38 tall: shot ticks over the picture and the sounds lane under it (frame 59).
private struct DailiesTakeStrip: View {
    var position: Double
    var duration: Double
    var asset: MediaAsset?
    var art: FootageArt
    var preview: Bool
    var shots: [Shot] = []
    var sounds: [IndexSound] = []
    var seek: (Double) -> Void
    private var indexed: Bool { !shots.isEmpty }
    var body: some View {
        GeometryReader { g in
            let x = duration > 0 ? g.size.width * min(1, position / duration) : 0
            ZStack(alignment: indexed ? .topLeading : .leading) {
                DailiesTakeThumb(asset: asset, art: art, preview: preview).opacity(0.55)
                    .frame(height: 24).clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Gate.Line.strong, lineWidth: 1))
                    .offset(y: indexed ? 3 : 0)
                if indexed { DailiesIndexLane(shots: shots, sounds: sounds, duration: duration) }
                Playhead(height: indexed ? 36 : 30).position(x: x, y: indexed ? 18 : 15)
            }
            .frame(height: indexed ? 38 : 30)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in seek(max(0, min(duration, Double(v.location.x / max(1, g.size.width)) * duration))) })
        }
        .frame(height: indexed ? 38 : 30)
        .accessibilityElement().accessibilityLabel("Position in take")
        .accessibilityValue(Timecode.format(position))
        .accessibilityAdjustableAction { d in seek(max(0, min(duration, position + (d == .increment ? 1 : -1)))) }
    }
}

/// Stand-in band for takes with no dialogue.
private struct DailiesWaveform: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                let h = size.height * (0.35 + 0.3 * abs(sin(x * 0.09) * cos(x * 0.031)))
                context.fill(Path(CGRect(x: x, y: (size.height - h) / 2, width: 1, height: h)), with: .color(Gate.Steel.ramp[6]))
                x += 3
            }
        }
        .opacity(0.7).accessibilityHidden(true)
    }
}

/// Plays one take straight from its file. Owned by the viewer; nothing here touches the cut's player.
@MainActor @Observable final class DailiesTakePlayer {
    @ObservationIgnored let player = AVPlayer()
    var position = 0.0
    var playing = false
    var missing = false
    var muted = false { didSet { player.isMuted = muted } }
    @ObservationIgnored private var path: String?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var activity: NSObjectProtocol?
    /// A seek on its way: the clock still reports where the take was, so it isn't read until the seek lands.
    @ObservationIgnored private var seeking = false
    @ObservationIgnored private var seeks = 0

    func load(_ asset: MediaAsset?, at time: Double, autoplay: Bool) {
        guard let asset else { return }
        if path != asset.path {
            path = asset.path
            missing = !FileManager.default.fileExists(atPath: asset.path)
            player.replaceCurrentItem(with: missing ? nil : AVPlayerItem(url: URL(fileURLWithPath: asset.path)))
            observe()
        }
        seek(time)
        if autoplay && !missing { player.play(); playing = true; keepAwake() }
    }
    func toggle() {
        if player.rate != 0 { player.pause() } else { player.play() }
        playing = player.rate != 0; keepAwake()
    }
    func seek(_ seconds: Double) {
        let target = max(0, seconds)
        position = target; seeking = true; seeks += 1
        let n = seeks
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            // Only the latest seek lets the clock be read again; one it replaced lands nowhere.
            Task { @MainActor in
                guard let self, n == self.seeks else { return }
                self.seeking = false
                if finished { self.position = target }
            }
        }
    }
    func shuttle(_ rate: Float) { player.rate = rate; playing = rate != 0; keepAwake() }
    func stop() {
        player.pause(); playing = false; keepAwake()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil; endObserver = nil; path = nil
        player.replaceCurrentItem(with: nil)
    }
    private func observe() {
        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 24), queue: .main) { [weak self] time in
                MainActor.assumeIsolated { guard let self, time.seconds.isFinite, !self.seeking else { return }; self.position = time.seconds; self.playing = self.player.rate != 0 }
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let item = player.currentItem
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playing = false; self?.keepAwake() }
        }
    }
    /// Keeps the display awake while a take plays.
    private func keepAwake() {
        if playing, activity == nil { activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Playing a take") }
        if !playing, let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }
}
