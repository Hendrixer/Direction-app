import SwiftUI
import AVFoundation
import DirectionCore

/// Plays one take's reading of a line: the line plus 0.5 s either side, from the original file.
@MainActor @Observable
final class ReadingPlayer {
    private(set) var playingID: String?
    /// 0…1 through the played span.
    private(set) var progress = 0.0
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var path: String?
    @ObservationIgnored private var observer: Any?

    func toggle(_ reading: ScriptReading, path: String?) {
        if playingID == reading.id { stop() } else { play(reading, path: path) }
    }

    func play(_ reading: ScriptReading, path: String?) {
        stop()
        guard let path, FileManager.default.fileExists(atPath: path) else { return }
        let start = max(0, reading.start - 0.5), end = reading.end + 0.5
        if self.path != path || player == nil { player = AVPlayer(url: URL(fileURLWithPath: path)); self.path = path }
        guard let player else { return }
        playingID = reading.id; progress = 0
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated { if self?.playingID == reading.id { player.play() } }
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1 / 30, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.playingID == reading.id else { return }
                self.progress = max(0, min(1, (time.seconds - start) / max(0.1, end - start)))
                if time.seconds >= end { self.stop() }
            }
        }
    }

    func stop() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil; playingID = nil; progress = 0
    }

    /// Snapshots show a reading mid-play without a player.
    func preview(_ id: String?, progress: Double) { playingID = id; self.progress = progress }
}

/// Every take that contains a line, so the director can hear them side by side.
/// In the cut first, then the editor's suggestion, then the rest by take, unusable last.
struct ReadingsPopover: View {
    var model: FilmModel
    var document: ScriptDocument
    var line: ScriptLine
    var player: ReadingPlayer
    @Binding var focusID: String?
    var onUse: (ScriptReading) -> Void
    var onClose: () -> Void
    @State private var hoveredID: String?
    @FocusState private var focused: Bool

    var readings: [ScriptReading] {
        func rank(_ r: ScriptReading) -> Int { r.assetID == line.assetID ? 0 : unusable(r) ? 3 : suggestion(r) != nil ? 1 : 2 }
        return line.readings.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return document.takeLabel(a.assetID).localizedStandardCompare(document.takeLabel(b.assetID)) == .orderedAscending
        }
    }
    private var longest: Double { max(3.9, readings.map(\.duration).max() ?? 0) }

    var body: some View {
        let list = readings
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionLabel("\(line.label) \u{00B7} \(list.count == 1 ? "1 reading" : "\(list.count) readings")")
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)) }
                        .buttonStyle(.gate(.ghost, .small, icon: true)).help("Close (esc)").accessibilityLabel("Close")
                }
                Text("\u{201C}\(line.text)\u{201D}").font(.system(size: 15)).foregroundStyle(Gate.Text.primary).lineLimit(2).padding(.vertical, 2)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            .hairlineBorder(.bottom)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, reading in
                row(reading)
                if i < list.count - 1 { Hairline() }
            }
            Text(footer(list))
                .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).padding(.vertical, 1.5)
                .padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hairlineBorder(.top)
        }
        .frame(width: 620)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Gate.Surface.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Gate.Line.strong, lineWidth: 1))
        .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1).padding(.horizontal, 12).padding(.top, 1) }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.9), radius: 30, y: 24)
        .focusable().focusEffectDisabled().focused($focused)
        .onAppear { focused = true; if focusID == nil { focusID = list.first?.id } }
        .onKeyPress(.upArrow) { moveFocus(-1, list); return .handled }
        .onKeyPress(.downArrow) { moveFocus(1, list); return .handled }
        .onKeyPress(.space) { if let r = list.first(where: { $0.id == focusID }) { play(r) }; return .handled }
        .onKeyPress(.return) { if let r = list.first(where: { $0.id == focusID }), r.assetID != line.assetID { onUse(r) }; return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onDisappear { player.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Readings of line \(line.number)")
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ r: ScriptReading) -> some View {
        let playing = player.playingID == r.id
        let inCut = r.assetID == line.assetID
        let showsUse = !inCut && (playing || hoveredID == r.id || focusID == r.id)
        let take = document.takeLabel(r.assetID)
        return HStack(spacing: 12) {
            Button { play(r) } label: { Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(PlayChipStyle(active: playing)).help(playing ? "Stop" : "Play this reading (space)")
                .accessibilityLabel(playing ? "Stop \(take)" : "Play \(take)")
            Thumbnail(path: model.asset(r.assetID)?.thumbnailPath, art: FootageArt.forScene(line.sceneNumber))
                .frame(width: 64, height: 36).clipShape(RoundedRectangle(cornerRadius: 4)).opacity(playing ? 0.85 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(take).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.primary)
                Text(setup(r)).font(.system(size: 11)).foregroundStyle(Gate.Text.disabled).lineLimit(1)
            }
            .frame(width: 96, alignment: .leading)
            LineWaveform(seed: r.id, fraction: r.duration / longest, playing: playing, progress: playing ? player.progress : nil)
                .frame(maxWidth: .infinity, maxHeight: 22)
            Text(String(format: "%.1f s", r.duration)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.Text.tertiary)
                .frame(width: 44, alignment: .leading)
            HStack(spacing: 6) {
                tags(r, inCut: inCut)
                if showsUse { Button("Use this") { onUse(r) }.buttonStyle(.gate(.normal, .small)).help("Add a note to use this reading (\u{21A9})") }
            }
            .frame(width: 170, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(height: 52)
        .background(playing || focusID == r.id ? Gate.Surface.raised : .clear)
        .opacity(unusable(r) ? 0.55 : 1)
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? r.id : (hoveredID == r.id ? nil : hoveredID) }
        .onTapGesture { focusID = r.id }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(r, inCut: inCut))
        .accessibilityAction(named: "Use this reading") { if !inCut { onUse(r) } }
    }

    @ViewBuilder private func tags(_ r: ScriptReading, inCut: Bool) -> some View {
        if inCut {
            HStack(spacing: 5) { RingMark(size: 8); Text("In \(model.watchedCut?.name ?? "the cut")").font(Gate.Font.mono) }
                .foregroundStyle(Gate.Voice.director).padding(.horizontal, 7).frame(height: Gate.Size.chip)
                .background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(Gate.Voice.directorWash))
        } else if let reason = suggestion(r) {
            HStack(spacing: 5) { GemMark(size: 6); Text(reason).font(Gate.Font.mono) }
                .foregroundStyle(Gate.Voice.agent).padding(.horizontal, 7).frame(height: Gate.Size.chip)
                .background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(Gate.Voice.agentWash))
                .help(model.dailies.take(r.assetID).suggestion ?? "")
        } else if let aside = r.aside {
            caption(aside)
        } else if !r.exact {
            caption("\u{201C}\(r.text.count > 28 ? String(r.text.prefix(27)).trimmingCharacters(in: .whitespaces) + "\u{2026}" : r.text)\u{201D}")
        } else if r.offCamera {
            caption("Off camera")
        }
    }

    private func caption(_ text: String) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary).lineLimit(1) }

    /// "Warmest read of the line, and she holds…" → "Warmest".
    private func suggestion(_ r: ScriptReading) -> String? {
        // A suggestion on a cutaway is about its picture, not this reading.
        guard r.assetID != line.assetID, !r.offCamera, let s = model.dailies.take(r.assetID).suggestion, !s.isEmpty else { return nil }
        let clause = s.split(whereSeparator: { ",.;".contains($0) }).first.map(String.init) ?? s
        return clause.count <= 16 ? clause : String(clause.split(separator: " ").first ?? "")
    }
    private func unusable(_ r: ScriptReading) -> Bool { model.dailies.take(r.assetID).unusable }
    private func setup(_ r: ScriptReading) -> String {
        let t = model.dailies.take(r.assetID)
        let description = model.dailies.scenes.first { $0.id == t.sceneID }?.setups.first { $0.code == t.setupCode }?.description
        return description.map { String($0.split(separator: ",").first ?? "") } ?? (model.asset(r.assetID)?.video.isEmpty == true ? "Sound only" : "")
    }
    private func footer(_ list: [ScriptReading]) -> String {
        guard list.count > 1 else { return "This is the only reading." }
        let example = list.first { $0.id == focusID && $0.assetID != line.assetID } ?? list.first { suggestion($0) != nil } ?? list.first { $0.assetID != line.assetID }
        return "Choosing a reading adds a note: \u{201C}Use \(document.takeLabel(example?.assetID ?? ""))\u{2019}s reading.\u{201D} It\u{2019}s cut at turnover."
    }
    private func accessibility(_ r: ScriptReading, inCut: Bool) -> String {
        let t = model.dailies.take(r.assetID)
        var parts = ["\(t.setupCode ?? "") Take \((t.code ?? "").replacingOccurrences(of: "T", with: ""))", String(format: "%.1f seconds", r.duration)]
        if inCut { parts.append("in \(model.watchedCut?.name ?? "the cut")") }
        if let s = suggestion(r) { parts.append("editor suggests: \(s.lowercased())") }
        if r.offCamera { parts.append("off camera") }
        if !inCut { parts.append("Use this reading.") }
        return parts.joined(separator: ", ")
    }
    private func play(_ r: ScriptReading) {
        focusID = r.id
        model.pause()
        player.toggle(r, path: model.asset(r.assetID)?.path)
    }
    private func moveFocus(_ delta: Int, _ list: [ScriptReading]) {
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == focusID } ?? 0
        let next = list[max(0, min(list.count - 1, i + delta))]
        focusID = next.id
        model.pause()
        player.play(next, path: model.asset(next.assetID)?.path)
    }
}

/// `.btn.icon.sm`: 22 pt raised square; hover look while its reading plays.
private struct PlayChipStyle: ButtonStyle {
    var active: Bool
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Gate.Text.primary)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? Gate.Surface.panel : active || hovered ? Gate.Surface.hover : Gate.Surface.raised)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
            .onHover { hovered = $0 }
            .contentShape(Rectangle())
    }
}

/// A waveform of one reading. Bars from the take's line, a playhead while it plays.
struct LineWaveform: View {
    var seed: String
    var fraction: Double
    var playing: Bool
    var progress: Double?
    var body: some View {
        Canvas { context, size in
            let width = size.width * CGFloat(max(0.08, min(1, fraction)))
            var rng = UInt64(truncatingIfNeeded: seed.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ UInt64($1) })
            var x: CGFloat = 0
            let color = playing ? Gate.Steel.ramp[8] : Gate.Steel.ramp[6]
            while x + 1.5 <= width {
                rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
                let jitter = 0.45 + 0.55 * Double(rng % 1000) / 1000
                let u = (Double(x / width) - 0.4) / 0.6
                let envelope = max(0, 1 - u * u)
                let h = max(1, size.height * CGFloat(envelope * jitter))
                context.fill(Path(CGRect(x: x, y: (size.height - h) / 2, width: 1.5, height: h)), with: .color(color))
                x += 3.5
            }
            if let progress {
                context.fill(Path(CGRect(x: width * CGFloat(progress) - 0.75, y: -3, width: 1.5, height: size.height + 6)), with: .color(Gate.Text.primary))
            }
        }
        .accessibilityHidden(true)
    }
}
