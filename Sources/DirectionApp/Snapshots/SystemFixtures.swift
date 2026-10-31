import SwiftUI
import DirectionCore

// Owner: System agent (39–53). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum SystemFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "39-share": { let m = SampleFilm.make(); m.sheet = .share; return .film(m) },
            "41-agent-popover": { popover() },
            "42-settings-general": { settings(.general, height: 789) },
            "54-settings-engines": { RunsFixtures.previewPrograms(chosen: true); return settings(.engines, height: 1651) },
            "44-settings-cutting": { settings(.cutting, height: 789) },
            "65-settings-styles": { settings(.styles, height: 789) },
            "66-brief-style-list": { SnapshotScene(size: CGSize(width: 460, height: 420), StyleList(styles: StyleSamples.styles, chosen: "desk-talk") { _ in }.frame(maxHeight: .infinity, alignment: .top).background(Gate.Surface.ground).preferredColorScheme(.dark)) },
            "45-settings-notifications": { settings(.notifications, height: 789) },
            "46-settings-shortcuts": { settings(.shortcuts, height: 789, recording: .region) },
            "47-settings-storage": { settings(.storage, height: 789) },
            "48-settings-sharing": { settings(.sharing, height: 789) },
            "49-command": { command() },
            "50-shortcuts": { let m = SampleFilm.make(); m.showShortcuts = true; return .film(m) },
            "51-offline": { let m = SampleFilm.make(); m.offline = true; return .film(m) },
            "52-media-missing": { missing() },
            "53-menus": { menus() },
        ]
    }

    private static func settings(_ tab: SettingsTab, height: CGFloat, recording: ShortcutAction? = nil) -> SnapshotScene {
        SettingsKey.register()
        return SnapshotScene(size: CGSize(width: Gate.Size.settingsWidth, height: height),
                             // Snapshots draw the whole section; the frame's fixed height clips at the bottom, never the top.
                             SettingsView(initialTab: tab, preview: true, recording: recording).frame(width: Gate.Size.settingsWidth, height: height, alignment: .top).clipped().background(Gate.Surface.ground))
    }

    /// Frame 41: the popover drawn where NSPopover puts it, under the pill.
    private static func popover() -> SnapshotScene {
        let m = SampleFilm.make()
        m.dailies.updatedAt = SampleFilm.date(10, 20, 10, 4)
        var t = Turnover(id: "turnover-2", number: 2, kind: "notes", noteIDs: ["note-1", "note-2"], baseRevision: 8, baseCutID: "cut-2", sequenceID: "sequence-main", latitude: .faithful, waitForOK: true, state: .delivered,
                         readBackApproved: true, resultCutID: "cut-3", createdAt: SampleFilm.date(10, 26, 13, 50), updatedAt: SampleFilm.date(10, 26, 13, 58))
        t.readBack = Array(SampleFilm.sampleReadBack.prefix(5))
        m.turnovers = [t]
        m.runs.previewPillOpen = true
        return SnapshotScene(ZStack(alignment: .topLeading) {
            FilmWindow(app: nil, model: m)
            PopoverChrome { EditorPopover(model: m) }.offset(x: 1440 - 126 - 360, y: 46)
        })
    }

    private static func command() -> SnapshotScene {
        let m = SampleFilm.make()
        m.showCommandMenu = true
        SystemPreview.commandQuery[ObjectIdentifier(m)] = "lock"
        return .film(m)
    }

    /// Frame 52: 14 takes on an unplugged drive, the relink sheet 12 of 14 through.
    private static func missing() -> SnapshotScene {
        let m = SampleFilm.make()
        let order = ["take-2a-t1", "take-2a-t2", "take-2a-t3", "take-2b-t1", "take-4c-t2", "take-5a-t3", "take-2a-t4", "take-2b-t2", "take-2b-t3", "take-3a-t2", "take-3a-t3", "take-3b-t1", "take-4a-t1", "take-4b-t1"]
        MissingFootage.setPreviewMissing(order, for: m)
        m.missingTakes = order.count
        let rows: [RelinkSearch.Row] = order.compactMap { id in
            guard let asset = m.project?.assets.first(where: { $0.id == id }) else { return nil }
            let label = MissingFootage.label(asset, dailies: m.dailies)
            let day = asset.name.hasSuffix("1021.mov") ? "Day 1" : asset.name.hasSuffix("1019.mov") ? "Day 2" : "Day 3"
            let notFound = ["take-4c-t2", "take-5a-t3"].contains(id)
            let status: RelinkSearch.Status = notFound ? .notFound : .found(AssetRelink(assetID: id, path: "/Volumes/Shoot SSD backup/\(day)/\(asset.name)", fileSize: 1, modifiedAt: 0, duration: asset.duration))
            return RelinkSearch.Row(id: id, label: label, originalPath: "/Volumes/Shoot SSD/\(day)/\(asset.name)", status: status)
        }
        SystemPreview.relink[ObjectIdentifier(m)] = .init(folder: "/Volumes/Shoot SSD backup", current: "Day 3", rows: rows)
        m.sheet = .relink
        return .film(m)
    }

    /// Frame 53: the three context menus at once, for reference only.
    private static func menus() -> SnapshotScene {
        let m = SampleFilm.make()
        let ridge = m.stripScenes.first { $0.number == 3 }!
        let note = m.notes.first { $0.number == 2 }!
        return SnapshotScene(ZStack(alignment: .topLeading) {
            FilmWindow(app: nil, model: m)
            GateMenuCard(entries: PictureContextMenu.entries(model: m), highlighted: "Mark This Frame").offset(x: 300, y: 250)
            GateMenuCard(entries: SceneContextMenu.entries(model: m, scene: ridge), highlighted: ridge.locked ? "Unlock Scene" : "Lock Scene").offset(x: 460, y: 560)
            GateMenuCard(entries: NoteContextMenu.entries(model: m, note: note), minWidth: 240).offset(x: 1140, y: 300)
        })
    }
}

/// What NSPopover draws around the editor popover: panel, radius 12, line-2 ring, arrow toward the pill.
/// The shadow is `.pop`'s `0 24px 60px -12px`, inset before the blur so it doesn't darken the pill.
private struct PopoverChrome<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .clipShape(shape)
            .background(shape.fill(Color.black.opacity(0.9)).padding(12).offset(y: 24).blur(radius: 30))
            .overlay(shape.strokeBorder(Gate.Line.strong, lineWidth: 1))
            .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1).padding(.horizontal, 12).padding(.top, 1) }
            .overlay(alignment: .topTrailing) {
                // The arrow: a 12 pt square turned 45°, its two upper edges in line-2.
                Rectangle().fill(Gate.Surface.panel).frame(width: 12, height: 12)
                    .overlay(alignment: .top) { Gate.Line.strong.frame(height: 1) }
                    .overlay(alignment: .leading) { Gate.Line.strong.frame(width: 1) }
                    .rotationEffect(.degrees(45))
                    .offset(x: -86, y: -6)
            }
    }
}
