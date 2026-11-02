import SwiftUI
import AppKit
import DirectionCore
import DirectionMedia

// Frame 59: a take's index under the take viewer. The shots row, the shot ticks and sounds lane
// on the take's scrubber, and the contact sheet (specs/footage-index.md › 59).

/// "SHOTS · LOGGED BY THE EDITOR", the Contact sheet button, then one card per shot.
/// Clicking a shot seeks the take to its start; ← → with the row focused move between shots.
struct DailiesShotsRow: View {
    var model: FilmModel
    var takeID: String
    var position: Double
    var seek: (Double) -> Void
    @Environment(\.dailiesPreview) private var preview
    @State private var showSheet = false
    @FocusState private var focused: Bool

    private var shots: [Shot] { model.index.shots(takeID) }

    /// The shot the playhead is in, with half a frame of give: the player reports a frame's own time, which can
    /// sit a hair before the start the index wrote for the shot.
    static func under(_ position: Double, in shots: [Shot], fps: Double) -> Shot? {
        shots.last { $0.start <= position + 0.5 / max(1, fps) }
    }
    private var fps: Double { model.asset(takeID)?.video.first?.frameRate ?? 24 }

    var body: some View {
        let shots = shots, current = Self.under(position, in: shots, fps: fps)?.id
        let width = CGFloat(shots.count) * DailiesShotCard.width + CGFloat(max(0, shots.count - 1)) * 10
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                GemMark(size: 7)
                SectionLabel("Shots \u{00B7} logged by the editor")
                Spacer(minLength: 8)
                Button { showSheet = true } label: { HStack(spacing: 6) { Image(systemName: "square.grid.2x2"); Text("Contact sheet") } }
                    .buttonStyle(.gate(.normal))
                    .help("The take at a glance: 16 frames with their timecodes")
                    .popover(isPresented: $showSheet, arrowEdge: .bottom) { DailiesContactSheet(model: model, takeID: takeID) { t in seek(t); showSheet = false } }
            }
            .frame(maxWidth: max(240, width), alignment: .leading)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(shots) { shot in
                            DailiesShotCard(shot: shot, on: shot.id == current, art: preview.art[takeID] ?? model.dailiesArt(takeID), fps: fps) { focused = true; seek(shot.start) }
                                .id(shot.id)
                        }
                    }
                    .padding(.bottom, width > 700 ? 10 : 0)
                }
                .scrollIndicators(.automatic)
                // The shot under the playhead is always in view: a click, ← →, or playing into the next one.
                .onChange(of: current) { _, id in
                    guard let id else { return }
                    withAnimation(gateAnimation(Gate.Motion.settle)) { proxy.scrollTo(id) }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusable().focusEffectDisabled().focused($focused)
        .onMoveCommand { d in
            guard d == .left || d == .right, let i = shots.firstIndex(where: { $0.id == current }) else { return }
            let j = d == .left ? max(0, i - 1) : min(shots.count - 1, i + 1)
            seek(shots[j].start)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shots, \(shots.count)")
    }
}

/// One shot: keyframe (16:9, radius 6), source range, the description (2 lines), a size chip and
/// flags as neutral chips. The shot under the playhead has a 1 pt text-1 ring.
struct DailiesShotCard: View {
    static let width: CGFloat = 168
    var shot: Shot
    var on: Bool
    var art: FootageArt
    var fps: Double
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ShotKeyframe(path: shot.keyframes.dropFirst().first ?? shot.keyframes.first, art: art)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1))
                    .overlay { if on { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Gate.Text.primary, lineWidth: 1).padding(-1) } }
                Text(SourceTimecode.range(shot.start, shot.end, fps: fps)).font(.system(size: 11, design: .monospaced)).monospacedDigit().foregroundStyle(Gate.Text.tertiary).lineLimit(1).padding(.top, 2)
                Text(shot.look?.description ?? "Not described yet.").font(.system(size: 12)).foregroundStyle(shot.look == nil ? Gate.Text.disabled : Gate.Text.secondary)
                    .lineLimit(2).lineSpacing(1.6).frame(height: 32.4, alignment: .topLeading)
                    .help(shot.look?.description ?? "")
                // Chips wrap inside the card instead of running into the next one.
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    if let size = shot.look?.size { Chip(size.capitalized, mono: false) }
                    ForEach(shot.look?.flags ?? [], id: \.self) { flag in Chip("\(flag.capitalized) at \(Timecode.duration(shot.middle))", mono: false) }
                }
                .frame(width: Self.width, alignment: .leading).padding(.top, 2)
            }
            .frame(width: Self.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Play from \(SourceTimecode.format(shot.start, fps: fps))")
        .accessibilityLabel("Shot \(shot.number), \(SourceTimecode.range(shot.start, shot.end, fps: fps)). \(shot.look?.description ?? "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A keyframe JPEG from the film's Index folder, or stand-in art in previews
/// ("preview:<art>:<zoom>:<x>:<y>:<brightness>" frames a part of it like the design does).
struct ShotKeyframe: View {
    var path: String?
    var art: FootageArt
    var body: some View {
        ZStack {
            Gate.Surface.sunken
            if let path, path.hasPrefix("preview:") {
                let p = path.split(separator: ":").map(String.init)
                let zoom = p.count > 2 ? Double(p[2]) ?? 1 : 1, ax = p.count > 3 ? Double(p[3]) ?? 0.5 : 0.5, ay = p.count > 4 ? Double(p[4]) ?? 0.5 : 0.5, b = p.count > 5 ? Double(p[5]) ?? 1 : 1
                FootageArtView(art: p.count > 1 ? FootageArt(rawValue: p[1]) ?? art : art)
                    .scaleEffect(zoom, anchor: UnitPoint(x: ax, y: ay)).brightness(b - 1)
            } else if let path, let image = ThumbnailCache.image(path) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                FootageArtView(art: art)
            }
        }
        .clipped()
    }
}

// MARK: The take's scrubber

/// Shot boundaries as 1 pt text-4 ticks over the strip, sounds as a 4 pt lane under it:
/// speech steel-7, laughter steel-9, music steel-8, silence empty. Hover a sound for its span.
struct DailiesIndexLane: View {
    var shots: [Shot]
    var sounds: [IndexSound]
    var duration: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                ForEach(shots.dropFirst()) { s in
                    Rectangle().fill(Gate.Text.disabled).frame(width: 1, height: 24).offset(x: x(s.start, w) - 0.5, y: 3)
                }
                ForEach(Array(sounds.enumerated()), id: \.offset) { _, s in
                    if let color = Self.color(s.kind) {
                        RoundedRectangle(cornerRadius: 1).fill(color)
                            .frame(width: max(1, x(s.end, w) - x(s.start, w)), height: 4).offset(x: x(s.start, w), y: 30)
                            .help("\(s.kind.rawValue.capitalized) \u{00B7} \(Timecode.duration(s.start))\u{2013}\(Timecode.duration(s.end))")
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
    private func x(_ t: Double, _ w: CGFloat) -> CGFloat { duration > 0 ? w * CGFloat(max(0, min(1, t / duration))) : 0 }
    static func color(_ kind: SoundKind) -> Color? {
        switch kind {
        case .speech: Gate.Steel.ramp[7]
        case .laughter: Gate.Steel.ramp[9]
        case .music: Gate.Steel.ramp[8]
        case .silence: nil
        // Not drawn in the frame; the quietest steel that still reads on the lane.
        case .applause, .wind, .traffic: Gate.Steel.ramp[6]
        }
    }
}

// MARK: Contact sheet

/// The take's sheet in a 640 pt popover. Click a cell to seek there.
struct DailiesContactSheet: View {
    var model: FilmModel
    var takeID: String
    var seek: (Double) -> Void
    @Environment(\.dailiesPreview) private var preview

    var body: some View {
        let asset = model.asset(takeID), duration = model.dailiesDuration(takeID)
        let take = model.index.takes[takeID]
        let fps = asset?.video.first?.frameRate ?? 24
        let layout = ContactSheet.layout(frames: 16, start: 0, end: duration, aspect: asset.map(ContactSheet.aspect) ?? 16 / 9)
        let times = take?.sheetTimes.count == 16 ? take!.sheetTimes : layout.times
        let scale = 628 / CGFloat(layout.width)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.dailies.takes[takeID].map(model.dailiesLabel) ?? "").font(Gate.Font.bodyMedium).foregroundStyle(Gate.Text.primary)
                Text("\(times.count) frames \u{00B7} \(Timecode.duration(duration))").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                Spacer()
            }
            .padding(.horizontal, 4).padding(.top, 2)
            ZStack(alignment: .topLeading) {
                if let path = take?.contactSheet, !model.isPreview, let image = ThumbnailCache.image(path) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Gate.Surface.canvas
                    ForEach(layout.cells.indices, id: \.self) { i in
                        let r = flipped(layout.cells[i], layout, scale)
                        ZStack(alignment: .bottomLeading) {
                            FootageArtView(art: preview.art[takeID] ?? model.dailiesArt(takeID))
                            HUDTag(SourceTimecode.format(times[i], fps: fps)).scaleEffect(0.85, anchor: .bottomLeading).padding(5)
                        }
                        .frame(width: r.width, height: r.height).clipped().offset(x: r.minX, y: r.minY)
                    }
                }
                ForEach(layout.cells.indices, id: \.self) { i in
                    let r = flipped(layout.cells[i], layout, scale)
                    Button { seek(times[i]) } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                        .help("Play from \(SourceTimecode.format(times[i], fps: fps))")
                        .accessibilityLabel("Frame at \(SourceTimecode.format(times[i], fps: fps))")
                }
            }
            .frame(width: 628, height: CGFloat(layout.height) * scale)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(6).frame(width: 640)
        .background(Gate.Surface.panel)
    }

    /// Layout cells are in CoreGraphics' bottom-up space; the view counts from the top.
    private func flipped(_ r: CGRect, _ l: ContactSheet.Layout, _ s: CGFloat) -> CGRect {
        CGRect(x: r.minX * s, y: (CGFloat(l.height) - r.maxY) * s, width: r.width * s, height: r.height * s)
    }
}

// MARK: Take states in the grid

extension FilmModel {
    /// "Couldn't look at this take" for a take whose index failed (footage-index.md › Acceptance).
    func indexFailed(_ assetID: String) -> Bool { index.state(assetID) == .failed }
}
