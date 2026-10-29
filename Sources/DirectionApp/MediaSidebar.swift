import SwiftUI
import AppKit
import DirectionCore

struct MediaSidebar: View {
    @Bindable var model: EditorModel
    @State private var query = ""
    private var assets: [MediaAsset] { (model.project?.assets ?? []).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: Gate.Space.s4) {
            HStack(spacing: Gate.Space.s2) {
                Image(systemName: "magnifyingglass").foregroundStyle(Gate.Text.tertiary)
                TextField("Search media", text: $query).textFieldStyle(.plain).accessibilityLabel("Search media")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Gate.Text.tertiary)
                    }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear media search")
                }
            }.font(Gate.Font.control).padding(Gate.Space.s3).directionField(cornerRadius: Gate.Radius.control)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Gate.Space.s4) {
                    ForEach(assets) { asset in
                        MediaAssetCard(asset: asset)
                    }
                }
                if assets.isEmpty {
                    SidebarEmptyState(
                        symbol: query.isEmpty ? "square.stack" : "magnifyingglass",
                        title: query.isEmpty ? "No media yet" : "No matching files",
                        detail: query.isEmpty ? "Add video, images, or audio to begin." : "Try another filename."
                    ).padding(.top, Gate.Space.s14)
                }
            }
            Button(action: model.chooseMedia) {
                Label("Bring footage", systemImage: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(QuietButton(prominent: true)).disabled(model.busyCount > 0)
        }.padding(.horizontal, Gate.Space.s4).padding(.bottom, Gate.Space.s4)
    }
}

private struct MediaAssetCard: View {
    let asset: MediaAsset
    private var symbol: String { asset.isImage ? "photo" : (asset.video.isEmpty ? "waveform" : "film") }
    var body: some View {
        VStack(alignment: .leading, spacing: Gate.Space.s2) {
            ZStack(alignment: .bottomTrailing) {
                GeometryReader { geometry in
                    if let path = asset.thumbnailPath, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else {
                        Gate.Surface.sunken.overlay {
                            Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(Gate.Text.tertiary)
                        }
                    }
                }
                Text(timecode(asset.duration.seconds, frames: false)).font(Gate.Font.timecode)
                    .padding(.horizontal, 5).padding(.vertical, 4)
                    .background(Gate.Surface.canvas.opacity(0.8), in: RoundedRectangle(cornerRadius: Gate.Radius.frame)).padding(Gate.Space.s1)
            }.frame(height: 86).clipShape(RoundedRectangle(cornerRadius: Gate.Radius.frame))
            Text(asset.name).font(Gate.Font.caption).foregroundStyle(Gate.Text.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 28, alignment: .top)
        }
            .contextMenu {
                Button("Reveal source") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: asset.path)])
                }
            }
    }
}
