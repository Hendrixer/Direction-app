import Foundation
import DirectionCore
import DirectionMedia

// Sync (specs/footage-index.md › Sync). Direction finds takes that recorded the same moment by
// their sound, the way it looks at and listens to footage: by itself, when footage arrives.
extension ToolCatalog {
    static var syncDefinitions: [ToolDefinition] {
        [
            definition("direction_sync_takes", "Find takes that recorded the same moment (two cameras, a camera and a screen recording, a camera and a sound recorder) by matching their sound, on this Mac. Returns a job (poll direction_job); Direction runs it by itself when footage arrives. The result is direction_dailies › syncGroups: each group's soundAssetID is the take whose sound the cut uses, and each take's offset puts it on that take's clock (sound time = take time + offset). Takes that don't share sound are never linked. force compares every take again.", ["force": bool], readOnly: false),
        ]
    }
}

extension ToolRuntime {
    func invokeSync(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        guard name == "direction_sync_takes" else { return nil }
        let p = try store.read(), d = try store.dailies()
        let speaking = p.assets.filter { !$0.isImage && !$0.audio.isEmpty && $0.duration.seconds >= SoundSync.minimumOverlap }
        let checked = a["force"].bool == true ? [] : Set(d.syncChecked ?? [])
        let fresh = speaking.filter { !checked.contains($0.id) }
        // Nothing new, or nothing to pair it with: note it as compared and stop.
        guard !fresh.isEmpty, speaking.count > 1 else {
            if !fresh.isEmpty { try store.saveSync(d.syncGroups ?? [], checked: fresh.map(\.id)) }
            return ToolResponse(.object(["syncGroups": try .wrapping(d.syncGroups ?? []), "note": .string("Nothing new to compare.")]))
        }
        let store = store, cache = cacheDirectory.appendingPathComponent("Sync")
        let job = try startJob(kind: "sync", revision: p.editRevision, phase: "Comparing the takes\u{2019} sound") {
            try await SyncPass.run(store: store, assets: speaking, cache: cache)
        }
        return ToolResponse(try .wrapping(job))
    }
}

/// One pass over every take with sound: curves (kept on disk), every pair the director hasn't
/// ruled out, then the groups.
enum SyncPass {
    static func run(store: ProjectStore, assets: [MediaAsset], cache: URL) async throws -> JSONValue {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var curves: [String: SoundSync.Curve] = [:]
        for asset in assets {
            try Task.checkCancellation()
            if let c = try await curve(asset, cache: cache) { curves[asset.id] = c }
        }
        let ruledOut = Set((try store.dailies().notInSync ?? []).map { $0.sorted().joined(separator: "|") })
        let ids = assets.map(\.id).filter { curves[$0] != nil }
        var matches: [(a: String, b: String, match: SoundSync.Match)] = []
        for (i, a) in ids.enumerated() {
            for b in ids[(i + 1)...] where !ruledOut.contains([a, b].sorted().joined(separator: "|")) {
                try Task.checkCancellation()
                if let m = SoundSync.match(curves[a]!.values, curves[b]!.values) { matches.append((a, b, m)) }
            }
        }
        let audioOnly = Set(assets.filter { $0.video.isEmpty }.map(\.id))
        let groups = SoundSync.groups(matches, curves: curves, audioOnly: audioOnly)
        try store.saveSync(groups, checked: assets.map(\.id))
        let names = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0.name) })
        for g in groups {
            DirectionLog.info("In sync by sound: " + g.takes.map { "\(names[$0.assetID] ?? $0.assetID) \($0.offset >= 0 ? "+" : "")\(String(format: "%.3f", $0.offset)) s (\($0.match))" }.joined(separator: ", ") + "; sound from \(names[g.soundAssetID] ?? g.soundAssetID)", "sync")
        }
        return .object(["syncGroups": try .wrapping(groups), "compared": .number(Double(matches.count))])
    }

    /// A take's curve, kept on disk for as long as the file and its muted tracks don't change.
    static func curve(_ asset: MediaAsset, cache: URL) async throws -> SoundSync.Curve? {
        let muted = asset.audio.filter(\.settings.muted).map { String($0.id) }.joined(separator: ",")
        let key = AudioProcessor.digest(Data("\(asset.path):\(asset.fileSize):\(asset.modifiedAt):\(muted):sync-v1".utf8))
        let file = cache.appendingPathComponent(key + ".json")
        if let data = try? Data(contentsOf: file), let c = try? JSONDecoder().decode(SoundSync.Curve.self, from: data) { return c }
        guard let c = try await SoundSync.curve(asset: asset) else { return nil }
        try? JSONEncoder().encode(c).write(to: file, options: .atomic)
        return c
    }
}
