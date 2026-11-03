import SwiftUI
import AppKit
import DirectionCore

/// A film the size of a real one (279 rows, a breakdown in progress), switching rooms, each switch timed from
/// the click to the window drawn:
///   DirectionApp --room-probe
@MainActor
enum RoomProbe {
    static func run() -> Never {
        BrandAssets.registerFonts()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // ROOM_PROBE_ROUNDS=12 ROOM_PROBE_ROOM=script switches only between Dailies and that room, for sampling.
        // ROOM_PROBE_SCRIPT and ROOM_PROBE_BREAKDOWN are JSON files (a film's directing payloads) to use instead.
        let env = ProcessInfo.processInfo.environment
        let m = film(script: env["ROOM_PROBE_SCRIPT"], breakdown: env["ROOM_PROBE_BREAKDOWN"])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: FilmWindow(app: nil, model: m).environment(\.colorScheme, .dark))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
        let only = env["ROOM_PROBE_ROOM"].flatMap { r in Room.allCases.first { "\($0)" == r } }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            for round in 1...(env["ROOM_PROBE_ROUNDS"].flatMap(Int.init) ?? 3) {
                for room in only.map({ [Room.dailies, $0] }) ?? [Room.dailies, .script, .dailies, .breakdown, .script, .breakdown, .dailies] {
                    let t = Date()
                    m.go(room)
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    print(String(format: "round %d  %-9@ %6.0f ms", round, room.title as NSString, Date().timeIntervalSince(t) * 1000))
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            exit(0)
        }
        app.run()
        exit(0)
    }

    /// 279 rows with pictures, and a breakdown the size of a real one: the narration over 234 rows, then 276
    /// shots in 12 setups.
    static func film(script: String? = nil, breakdown: String? = nil) -> FilmModel {
        func load<T: Decodable>(_ path: String?, _ type: T.Type) -> T? { path.flatMap { try? JSONDecoder().decode(type, from: Data(contentsOf: URL(fileURLWithPath: $0))) } }
        if let s = load(script, AVScript.self) { return PrepFixtures.film(room: .dailies, script: s, breakdown: load(breakdown, Breakdown.self)) }
        var s = PrepFixtures.script()
        let base = s.rows
        s.rows = (0..<279).map { i in
            var r = base[i % base.count]; r.id = "row-\(i + 1)"
            if r.picture.isEmpty { r.picture = AVPicture(text: "Scott at the desk, close, lit by the screen.", size: .close, board: .close) }
            return r
        }
        s.okAt = 1; s.okRevision = s.revision
        var b = Breakdown()
        b.setups = (1...13).map { BreakdownSetup(id: "setup-\($0)", number: $0, name: "Setup \($0)", needs: "After dark · lamp off") }
        b.shots = [BreakdownShot(id: "shot-1A", code: "1A", setupID: "setup-1", rowIDs: (1...234).map { "row-\($0)" }, what: "The narration, read through.", seconds: 1375, source: .sound)]
        for n in 2...13 { for l in 0..<23 { let code = "\(n)\(Character(UnicodeScalar(UInt8(65 + l))))"; b.shots.append(BreakdownShot(id: "shot-\(code)", code: code, setupID: "setup-\(n)", rowIDs: ["row-\(min(279, (n - 2) * 23 + l + 1))"], what: "Hands on the keyboard, close.", size: .detail, seconds: 3, source: .shoot, board: .detail)) } }
        b.scriptRevision = s.revision
        let m = PrepFixtures.film(room: .dailies, script: s, breakdown: b)
        return m
    }
}
