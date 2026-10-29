import SwiftUI
import DirectionCore

struct AudioPanel: View {
    @Bindable var model: EditorModel
    private var assets: [MediaAsset] { (model.displayedProject?.assets ?? []).filter { !$0.audio.isEmpty } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gate.Space.s4) {
                Text("Source audio").font(Gate.Font.title)
                Text("Enable the tracks you want to hear. Source settings apply wherever that footage appears.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineSpacing(3)
                if !assets.isEmpty {
                    Picker("Source", selection: Binding(get: { model.selectedAsset?.audio.isEmpty == false ? model.selectedAsset?.id ?? "" : assets[0].id }, set: { model.selectedAssetID = $0 })) { ForEach(assets) { asset in Text(asset.name).tag(asset.id) } }.font(Gate.Font.control)
                    if let asset = model.selectedAsset, !asset.audio.isEmpty {
                        ForEach(asset.audio) { track in AudioTrackCard(model: model, asset: asset, track: track).id(asset.id + ":" + String(track.id)) }
                    } else if let asset = assets.first { ForEach(asset.audio) { track in AudioTrackCard(model: model, asset: asset, track: track) } }
                } else {
                    SidebarEmptyState(symbol: "waveform", title: "No audio tracks", detail: "Import footage with audio to see its source tracks.").padding(.top, 30)
                }
            }.padding(Gate.Space.s4)
        }.background(Gate.Surface.ground)
    }
}

struct AudioTrackCard: View {
    @Bindable var model: EditorModel
    let asset: MediaAsset
    let track: AudioStream
    @State private var gain = 0.0
    var body: some View {
        VStack(alignment: .leading, spacing: Gate.Space.s3) {
            HStack(spacing: Gate.Space.s2) {
                Image(systemName: track.settings.muted ? "speaker.slash" : "waveform").font(.system(size: 17)).foregroundStyle(track.settings.muted ? Gate.Text.tertiary : Gate.Text.secondary)
                VStack(alignment: .leading, spacing: 3) { Text(track.label).font(Gate.Font.control); Text("\(track.channels) ch · \(Int(track.sampleRate / 1000)) kHz · stream \(track.id)").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary) }
                Spacer()
                Button { model.updateAudio(asset: asset, track: track, muted: !track.settings.muted) } label: { Text(track.settings.muted ? "Muted" : "On").font(Gate.Font.caption.weight(.medium)).foregroundStyle(track.settings.muted ? Gate.Text.tertiary : Gate.Text.secondary).padding(.horizontal, 9).padding(.vertical, 5).background(track.settings.muted ? Gate.Surface.sunken : Gate.Text.secondary.opacity(0.12), in: Capsule()) }.buttonStyle(.plain).accessibilityLabel("\(track.settings.muted ? "Unmute" : "Mute") \(track.label)")
            }
            HStack { Text("Gain").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary); Spacer(); Text(String(format: "%+.1f dB", gain)).font(Gate.Font.timecode) }
            Slider(value: $gain, in: -48...12, onEditingChanged: { editing in if !editing { model.updateAudio(asset: asset, track: track, gain: gain) } }).controlSize(.small).tint(Gate.Text.secondary).accessibilityLabel("\(track.label) gain")
            DirectionDivider()
            Picker("High-pass", selection: Binding(get: { Int(track.settings.effects.highPassHz) }, set: { model.updateAudio(asset: asset, track: track, extra: ["highPassHz": .number(Double($0))]) })) { Text("Off").tag(0); Text("80 Hz").tag(80); Text("120 Hz").tag(120); Text("200 Hz").tag(200) }.font(Gate.Font.caption)
            Toggle("Dialogue compression", isOn: Binding(get: { track.settings.effects.compressor }, set: { model.updateAudio(asset: asset, track: track, extra: ["compressor": .bool($0)]) })).font(Gate.Font.caption).toggleStyle(.switch).controlSize(.mini)
            Toggle("Track limiter", isOn: Binding(get: { track.settings.effects.limiter }, set: { model.updateAudio(asset: asset, track: track, extra: ["limiter": .bool($0)]) })).font(Gate.Font.caption).toggleStyle(.switch).controlSize(.mini)
        }.padding(.vertical, Gate.Space.s4).overlay(alignment: .bottom) { DirectionDivider() }.disabled(!model.canEdit)
        .onAppear { gain = track.settings.gainDB }.onChange(of: track.settings.gainDB) { _, value in gain = value }
    }
}

struct LookPanel: View {
    @Bindable var model: EditorModel
    @State private var grade = ColorGrade()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gate.Space.s4) {
                Text("Picture").font(Gate.Font.title)
                if let clip = model.selectedClip {
                    Text(clip.name).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(2)
                    control("Exposure", value: $grade.exposure, range: -3...3, suffix: " EV")
                    control("Contrast", value: $grade.contrast, range: 0.3...2, suffix: "")
                    control("Saturation", value: $grade.saturation, range: 0...2, suffix: "")
                    control("Warmth", value: $grade.temperature, range: -2000...2000, suffix: " K")
                    control("Tint", value: $grade.tint, range: -50...50, suffix: "")
                    Button("Reset look") { grade = .init(); model.updateGrade(grade) }.buttonStyle(QuietButton())
                    Text("Your adjustments carry through to the final export.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineSpacing(3)
                } else { SidebarEmptyState(symbol: "slider.horizontal.3", title: "No footage selected", detail: "Choose footage to adjust its color and exposure.").padding(.top, 28) }
            }.padding(Gate.Space.s4).disabled(!model.canEdit)
        }.onAppear { grade = model.selectedClip?.grade ?? .init() }.onChange(of: model.selectedClip?.grade) { _, value in grade = value ?? .init() }.onChange(of: model.selectedClip?.id) { _, _ in grade = model.selectedClip?.grade ?? .init() }
    }
    private func control(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: Gate.Space.s2) {
            HStack { Text(name).font(Gate.Font.control); Spacer(); Text(String(format: suffix == " K" ? "%.0f" : "%.2f", value.wrappedValue) + suffix).font(Gate.Font.timecode).foregroundStyle(Gate.Text.tertiary) }
            Slider(value: value, in: range, onEditingChanged: { editing in if !editing { model.updateGrade(grade) } }).controlSize(.small).accessibilityLabel(name)
        }
    }
}
