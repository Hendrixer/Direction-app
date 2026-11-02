import SwiftUI
import DirectionCore

/// Dailies › Made (made-media.md › Where made things show): every made clip after the bins, each opening
/// its provenance, so it can be watched and reused like footage. Removing the key leaves these playable.
struct DailiesMadeGroup: View {
    @Bindable var model: FilmModel
    private var made: MadeModel { model.made }

    var body: some View {
        if !made.records.isEmpty {
            SectionLabel("Made").frame(height: 11).padding(.horizontal, 9).padding(.top, 14).padding(.bottom, 6)
            ForEach(made.records) { r in row(r) }
        }
    }

    private func row(_ r: MadeRecord) -> some View {
        let open = made.dailiesID == r.assetID
        return Button { made.dailiesID = open ? nil : r.assetID } label: {
            HStack(spacing: 9) {
                Image(systemName: r.icon).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).frame(width: 15)
                Text(r.asked).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                if let length = r.lengthText { Text(length).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled) }
            }
            .font(.system(size: 13)).foregroundStyle(open ? Gate.Text.primary : Gate.Text.secondary)
            .padding(.horizontal, 9).frame(height: 30)
            .background { RoundedRectangle(cornerRadius: 7).fill(open ? Gate.Surface.raised : .clear).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(open ? Gate.Line.subtle : .clear, lineWidth: 1)) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gatePopover(isPresented: Binding(get: { open && !model.isPreview }, set: { if !$0, open { made.dailiesID = nil } }), arrowEdge: .trailing) {
            MadeProvenance(film: model, record: r, showsDailies: false).background(Gate.Surface.panel)
        }
        .help("\(r.kind.label) made with \(r.versionName)")
        .accessibilityLabel("\(r.kind.label) made with \(r.versionName): \(r.asked)")
        .accessibilityAddTraits(open ? .isSelected : [])
    }
}
