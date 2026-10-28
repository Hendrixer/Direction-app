import SwiftUI
import AppKit
import DirectionCore

struct MediaSidebar: View {
    @Bindable var model: EditorModel
    @State private var query = ""
    private var assets: [MediaAsset] { (model.project?.assets ?? []).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search media", text: $query).textFieldStyle(.plain).accessibilityLabel("Search media")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                    }.buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear media search")
                }
            }.font(.system(size: 12)).padding(11).directionField(cornerRadius: 9)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(assets) { asset in
                        MediaAssetCard(asset: asset)
                    }
                }
                if assets.isEmpty {
                    SidebarEmptyState(
                        symbol: query.isEmpty ? "square.stack" : "magnifyingglass",
                        title: query.isEmpty ? "No media yet" : "No matching files",
                        detail: query.isEmpty ? "Add video, images, or audio to begin." : "Try another filename."
                    ).padding(.top, 48)
                }
            }
            Button(action: model.chooseMedia) {
                Label("Add media", systemImage: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(QuietButton()).disabled(model.busyCount > 0)
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }
}

private struct MediaAssetCard: View {
    let asset: MediaAsset
    private var symbol: String { asset.isImage ? "photo" : (asset.video.isEmpty ? "waveform" : "film") }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                GeometryReader { geometry in
                    if let path = asset.thumbnailPath, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else {
                        Palette.inset.overlay {
                            Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(Palette.muted)
                        }
                    }
                }
                Text(timecode(asset.duration.seconds)).font(.system(size: 9, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 4)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4)).padding(6)
            }.frame(height: 86).clipShape(RoundedRectangle(cornerRadius: 7))
            Text(asset.name).font(.system(size: 11, weight: .regular)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 28, alignment: .top)
        }
            .contextMenu {
                Button("Reveal source") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: asset.path)])
                }
            }
    }
}
