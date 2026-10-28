import SwiftUI
import DirectionCore

struct AudioPanel: View {
    @Bindable var model: EditorModel
    private var assets: [MediaAsset] { (model.displayedProject?.assets ?? []).filter { !$0.audio.isEmpty } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Source audio").font(.system(size: 15, weight: .medium)).tracking(-0.2)
                Text("Enable the tracks you want to hear. Source settings apply wherever that footage appears.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
                if !assets.isEmpty {
                    Picker("Source", selection: Binding(get: { model.selectedAsset?.audio.isEmpty == false ? model.selectedAsset?.id ?? "" : assets[0].id }, set: { model.selectedAssetID = $0 })) { ForEach(assets) { asset in Text(asset.name).tag(asset.id) } }.font(.system(size: 11))
                    if let asset = model.selectedAsset, !asset.audio.isEmpty {
                        ForEach(asset.audio) { track in AudioTrackCard(model: model, asset: asset, track: track).id(asset.id + ":" + String(track.id)) }
                    } else if let asset = assets.first { ForEach(asset.audio) { track in AudioTrackCard(model: model, asset: asset, track: track) } }
                } else {
                    SidebarEmptyState(symbol: "waveform", title: "No audio tracks", detail: "Import footage with audio to see its source tracks.").padding(.top, 30)
                }
            }.padding(18)
        }.background(Palette.panel)
    }
}

struct AudioTrackCard: View {
    @Bindable var model: EditorModel
    let asset: MediaAsset
    let track: AudioStream
    @State private var gain = 0.0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: track.settings.muted ? "speaker.slash" : "waveform").font(.system(size: 17)).foregroundStyle(track.settings.muted ? Palette.muted : Palette.audio)
                VStack(alignment: .leading, spacing: 3) { Text(track.label).font(.system(size: 12, weight: .medium)); Text("\(track.channels) ch · \(Int(track.sampleRate / 1000)) kHz · stream \(track.id)").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                Spacer()
                Button { model.updateAudio(asset: asset, track: track, muted: !track.settings.muted) } label: { Text(track.settings.muted ? "Muted" : "On").font(.system(size: 10, weight: .medium)).foregroundStyle(track.settings.muted ? Palette.muted : Palette.audio).padding(.horizontal, 9).padding(.vertical, 5).background(track.settings.muted ? Palette.background : Palette.audio.opacity(0.12), in: Capsule()) }.buttonStyle(.plain).accessibilityLabel("\(track.settings.muted ? "Unmute" : "Mute") \(track.label)")
            }
            HStack { Text("Gain").font(.system(size: 10)).foregroundStyle(Palette.muted); Spacer(); Text(String(format: "%+.1f dB", gain)).font(.system(size: 10, design: .monospaced)) }
            Slider(value: $gain, in: -48...12, onEditingChanged: { editing in if !editing { model.updateAudio(asset: asset, track: track, gain: gain) } }).controlSize(.small).tint(Palette.audio).accessibilityLabel("\(track.label) gain")
            DirectionDivider()
            Picker("High-pass", selection: Binding(get: { Int(track.settings.effects.highPassHz) }, set: { model.updateAudio(asset: asset, track: track, extra: ["highPassHz": .number(Double($0))]) })) { Text("Off").tag(0); Text("80 Hz").tag(80); Text("120 Hz").tag(120); Text("200 Hz").tag(200) }.font(.system(size: 10))
            Toggle("Dialogue compression", isOn: Binding(get: { track.settings.effects.compressor }, set: { model.updateAudio(asset: asset, track: track, extra: ["compressor": .bool($0)]) })).font(.system(size: 10)).toggleStyle(.switch).controlSize(.mini)
            Toggle("Track limiter", isOn: Binding(get: { track.settings.effects.limiter }, set: { model.updateAudio(asset: asset, track: track, extra: ["limiter": .bool($0)]) })).font(.system(size: 10)).toggleStyle(.switch).controlSize(.mini)
        }.padding(.vertical, 16).overlay(alignment: .bottom) { DirectionDivider() }.disabled(!model.canEdit)
        .onAppear { gain = track.settings.gainDB }.onChange(of: track.settings.gainDB) { _, value in gain = value }
    }
}

struct LookPanel: View {
    @Bindable var model: EditorModel
    @State private var grade = ColorGrade()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                Text("Picture").font(.system(size: 15, weight: .medium)).tracking(-0.2)
                if let clip = model.selectedClip {
                    Text(clip.name).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
                    control("Exposure", value: $grade.exposure, range: -3...3, suffix: " EV")
                    control("Contrast", value: $grade.contrast, range: 0.3...2, suffix: "")
                    control("Saturation", value: $grade.saturation, range: 0...2, suffix: "")
                    control("Warmth", value: $grade.temperature, range: -2000...2000, suffix: " K")
                    control("Tint", value: $grade.tint, range: -50...50, suffix: "")
                    Button("Reset look") { grade = .init(); model.updateGrade(grade) }.buttonStyle(QuietButton())
                    Text("Your adjustments carry through to the final export.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
                } else { SidebarEmptyState(symbol: "slider.horizontal.3", title: "No footage selected", detail: "Choose footage to adjust its color and exposure.").padding(.top, 28) }
            }.padding(18).disabled(!model.canEdit)
        }.onAppear { grade = model.selectedClip?.grade ?? .init() }.onChange(of: model.selectedClip?.grade) { _, value in grade = value ?? .init() }.onChange(of: model.selectedClip?.id) { _, _ in grade = model.selectedClip?.grade ?? .init() }
    }
    private func control(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: 9) {
            HStack { Text(name).font(.system(size: 11)); Spacer(); Text(String(format: suffix == " K" ? "%.0f" : "%.2f", value.wrappedValue) + suffix).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted) }
            Slider(value: value, in: range, onEditingChanged: { editing in if !editing { model.updateGrade(grade) } }).controlSize(.small).accessibilityLabel(name)
        }
    }
}
