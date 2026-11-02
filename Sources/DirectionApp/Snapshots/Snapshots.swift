import SwiftUI
import AppKit

/// A frame from design/spec rendered from real SwiftUI views and sample state.
struct SnapshotScene {
    var size = CGSize(width: 1440, height: 900)
    var view: AnyView
    init<V: View>(size: CGSize = CGSize(width: 1440, height: 900), _ view: V) { self.size = size; self.view = AnyView(view) }
    /// The film window for a prepared model.
    @MainActor static func film(_ model: FilmModel) -> SnapshotScene { .init(FilmWindow(app: nil, model: model)) }
}

/// Renders frames offscreen so each room can be compared with design/spec/renders/<id>@1x.png.
///   DirectionApp --snapshot 17-notes-drafts out.png
///   DirectionApp --snapshot-all <dir>
@MainActor
enum Snapshots {
    /// Frame IDs match design/spec/frames.js. Each room group registers its own frames.
    static var registry: [String: () -> SnapshotScene] {
        var all: [String: () -> SnapshotScene] = ["00-shell": { .film(SampleFilm.make()) }]
        for group in [StartFixtures.frames, DailiesFixtures.frames, ScriptFixtures.frames, ScreeningFixtures.frames, NotesFixtures.frames, ChangesFixtures.frames, FinishFixtures.frames, SystemFixtures.frames, Phase2Fixtures.frames] {
            all.merge(group) { a, _ in a }
        }
        return all
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 {
            BrandAssets.registerFonts(); _ = NSApplication.shared; NSApp.appearance = NSAppearance(named: .darkAqua)
            exit(render(args[i + 1], to: URL(fileURLWithPath: args[i + 2])) ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--snapshot-all"), args.count > i + 1 {
            BrandAssets.registerFonts(); _ = NSApplication.shared; NSApp.appearance = NSAppearance(named: .darkAqua)
            let dir = URL(fileURLWithPath: args[i + 1]); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var ok = true
            for id in registry.keys.sorted() { ok = render(id, to: dir.appendingPathComponent("\(id).png")) && ok }
            exit(ok ? 0 : 1)
        }
        if args.contains("--popover-probe") { PopoverProbe.run() }
    }

    @discardableResult
    static func render(_ id: String, to url: URL) -> Bool {
        guard let make = registry[id] else { FileHandle.standardError.write(Data("No snapshot named \(id). Known: \(registry.keys.sorted().joined(separator: ", "))\n".utf8)); return false }
        let scene = make()
        // Ids starting "zz-" are motion studies: ImageRenderer draws SwiftUI blend modes, which cacheDisplay drops.
        if id.hasPrefix("zz-") {
            let renderer = ImageRenderer(content: scene.view.frame(width: scene.size.width, height: scene.size.height).environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
            do { try data.write(to: url); print("rendered \(id) → \(url.path)"); return true } catch { return false }
        }
        let host = NSHostingView(rootView: scene.view.frame(width: scene.size.width, height: scene.size.height).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: scene.size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000)); window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url); print("rendered \(id) → \(url.path)"); window.orderOut(nil); return true } catch { return false }
    }
}
