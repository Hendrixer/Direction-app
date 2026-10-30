import SwiftUI
import AppKit
import Network
import DirectionCore

/// The 36 pt banners under the titlebar: offline (frame 51) and footage missing (frame 52).
/// Also the window-level watchers that belong to no room: the network, unplugged drives,
/// deliveries finishing, notifications held through a screening, and the `?` key.
struct SystemBanners: View {
    @Bindable var model: FilmModel
    @State private var network = NetworkMonitor.shared
    @State private var missing: [MediaAsset] = []
    @State private var keys = WindowKeys()

    var body: some View {
        VStack(spacing: 0) {
            if model.offline { offlineBanner.transition(.move(edge: .top).combined(with: .opacity)) }
            if !shownMissing.isEmpty { missingBanner.transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .animation(SettingsKey.reducesMotion ? nil : Gate.Motion.settle, value: model.offline)
        .animation(SettingsKey.reducesMotion ? nil : Gate.Motion.settle, value: shownMissing.count)
        .task(id: assetSignature) { refreshMissing() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in refreshMissing() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in refreshMissing() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshMissing() }
        .onChange(of: network.online, initial: true) { _, online in syncOffline(online) }
        .onChange(of: model.jobs.map(\.status)) { _, _ in DeliveryWatch.check(model) }
        .onChange(of: model.room) { old, _ in if old == .screening { SystemNotifications.releaseHeld(film: model) } }
        .onChange(of: model.turnovers.count) { _, n in if n > 0 { SystemNotifications.requestPermissionIfNeeded() } }
        .background { if !model.isPreview { SceneTracker(model: model) } }
        .onChange(of: missing.count, initial: true) { _, n in if !model.isPreview { MenuState.shared.missingCount = n; model.missingTakes = n } }
        .onAppear { if !model.isPreview { keys.install(model) } }
        .onDisappear { keys.remove(); if !model.isPreview { MenuState.shared.sceneID = nil; MenuState.shared.missingCount = 0 } }
    }

    // MARK: Offline (51)

    private func syncOffline(_ online: Bool) {
        guard !model.isPreview else { return }
        let wasOffline = model.offline
        model.offline = !online
        if wasOffline && online { model.toast = Toast(title: "Back online.", detail: model.openTurnover == nil ? nil : "Your editor can pick up where it left off.", editor: true) }
    }

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            if network.reconnecting { RingSpinner(size: 13) }
            else { Image(systemName: "wifi.slash").font(.system(size: 12, weight: .medium)).foregroundStyle(Gate.Text.secondary) }
            TextRun.line([
                TextRun(network.reconnecting ? "Reconnecting\u{2026}" : "You\u{2019}re offline.", Gate.Text.primary, .semibold),
                TextRun(network.reconnecting ? "" : " You can watch, mark, write notes and turn them over. An editor that works online picks them up when you\u{2019}re back.", Gate.Text.tertiary),
            ], size: 12.5)
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if let last = network.lastConnected ?? (model.isPreview ? SampleFilm.date(10, 28, 14, 2) : nil) {
                Text("Last connected \(Date(timeIntervalSince1970: last).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))")
                    .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1).fixedSize()
            }
            Button("Try again") { network.retry() }.buttonStyle(.gate(.normal, .small)).disabled(network.reconnecting)
        }
        .padding(.horizontal, 16).frame(height: 36)
        .background(Gate.Surface.panel)
        .overlay(alignment: .bottom) { SystemHairline() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("You\u{2019}re offline")
        .onAppear { if !model.isPreview { Self.announce("You\u{2019}re offline.") } }
    }

    /// Banners are announced once as a status update when they appear.
    static func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    // MARK: Footage missing (52)

    private var assetSignature: String { (model.project?.assets ?? []).map { "\($0.id)=\($0.path)" }.joined(separator: "|") }
    private var shownMissing: [MediaAsset] { model.isPreview ? MissingFootage.previewAssets(model) : missing }

    private func refreshMissing() {
        guard !model.isPreview else { return }
        missing = MissingFootage.assets(in: model)
    }

    private var missingBanner: some View {
        let count = shownMissing.count
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .medium)).foregroundStyle(Gate.State.alert)
            TextRun.line([
                TextRun(count == 1 ? "1 take is missing." : "\(count) takes are missing.", Gate.Text.primary, .semibold),
                TextRun(" " + MissingFootage.reason(shownMissing) + " The editor can\u{2019}t cut scenes that use them.", Gate.Text.secondary),
            ], size: 12.5)
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Button("Find footage\u{2026}") { model.sheet = .relink }.buttonStyle(.gate(.normal, .small))
        }
        .padding(.horizontal, 16).frame(height: 36)
        .background(Gate.State.alert.opacity(0.14))
        .overlay(alignment: .bottom) { SystemHairline() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(count == 1 ? "1 take is missing" : "\(count) takes are missing")
        .onAppear { if !model.isPreview { SystemBanners.announce(count == 1 ? "1 take is missing." : "\(count) takes are missing.") } }
    }
}

/// Follows the playhead's scene for the menu bar. Only this empty view re-runs with the playhead.
private struct SceneTracker: View {
    var model: FilmModel
    var body: some View {
        let id = model.stripScene(at: model.position).flatMap { s in model.dailies.scenes.first { $0.id == s.id }?.id }
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: id, initial: true) { _, new in if MenuState.shared.sceneID != new { MenuState.shared.sceneID = new } }
    }
}

// MARK: Missing footage

@MainActor
enum MissingFootage {
    /// Takes whose original file can't be reached.
    static func assets(in model: FilmModel) -> [MediaAsset] {
        (model.project?.assets ?? []).filter { !FootageMatch.isReachable($0) }
    }

    /// "The drive “Shoot SSD” isn't connected." when every missing file was on one unmounted volume.
    static func reason(_ assets: [MediaAsset]) -> String {
        let volumes = Set(assets.map { volumeName($0.path) })
        if volumes.count == 1, let name = volumes.first ?? nil, !FileManager.default.fileExists(atPath: "/Volumes/\(name)") {
            return "The drive \u{201C}\(name)\u{201D} isn\u{2019}t connected."
        }
        return assets.count == 1 ? "Its file was moved or renamed." : "Their files were moved or renamed."
    }

    static func volumeName(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        return parts.count > 1 && parts[0] == "Volumes" ? String(parts[1]) : nil
    }

    /// The take's label in this film: "2A T2", falling back to the file name.
    static func label(_ asset: MediaAsset, dailies: Dailies) -> String {
        let t = dailies.take(asset.id)
        if let setup = t.setupCode, let code = t.code { return "\(setup) \(code)" }
        return t.code ?? asset.name
    }

    // Previews: which sample takes to show as missing, per model.
    private static var preview: [ObjectIdentifier: [String]] = [:]
    static func setPreviewMissing(_ ids: [String], for model: FilmModel) { preview[ObjectIdentifier(model)] = ids }
    static func previewAssets(_ model: FilmModel) -> [MediaAsset] {
        guard let ids = preview[ObjectIdentifier(model)] else { return [] }
        return (model.project?.assets ?? []).filter { ids.contains($0.id) }
    }
}

// MARK: Network

/// Whether this Mac has a network path. Direction itself works offline; an editor that runs
/// online (and screening links, when they exist) needs one.
@MainActor @Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var online = true
    private(set) var lastConnected: Double?
    private(set) var reconnecting = false
    @ObservationIgnored private var monitor: NWPathMonitor?

    private init() { start() }

    private func start() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.update(satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "dev.direction.network"))
        self.monitor = monitor
    }

    private func update(_ satisfied: Bool) {
        if online && !satisfied { lastConnected = Date().timeIntervalSince1970 }
        online = satisfied
        if satisfied { lastConnected = nil }
        reconnecting = false
    }

    /// Try again: look at the network afresh.
    func retry() {
        reconnecting = true
        monitor?.cancel(); monitor = nil
        start()
        Task { try? await Task.sleep(for: .seconds(2)); reconnecting = false }
    }
}

// MARK: Keys

/// A text field or text view has the keyboard. SwiftUI offers a key press to a room's
/// `onKeyPress` before an AppKit text view inside it sees the key, so a room that uses Space or
/// the arrows would take them from a note being written. Every room key handler asks first and
/// leaves the keystroke to the text.
enum TextInput {
    /// Asks the window the key press came from, else the key window, else (no window is key,
    /// as when a test sends the key) any window.
    @MainActor static var hasFocus: Bool {
        if let window = NSApp.currentEvent?.window ?? NSApp.keyWindow { return window.firstResponder is NSText }
        return NSApp.windows.contains { $0.firstResponder is NSText }
    }
}

/// `?` opens the keyboard shortcuts and esc closes them, whenever no text field has focus.
@MainActor
final class WindowKeys {
    private var monitor: Any?
    func install(_ model: FilmModel) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            let used = MainActor.assumeIsolated { () -> Bool in
                guard let model, event.window?.frameAutosaveName == "DirectionMainWindow" else { return false }
                let typing = event.window?.firstResponder is NSText
                let mods = event.modifierFlags.intersection([.command, .option, .control])
                if model.showShortcuts, event.keyCode == 53 { model.showShortcuts = false; return true }
                if !typing, mods.isEmpty, event.charactersIgnoringModifiers == "?" || (event.charactersIgnoringModifiers == "/" && event.modifierFlags.contains(.shift)),
                   model.sheet == nil, !model.showCommandMenu {
                    model.showShortcuts.toggle(); return true
                }
                return false
            }
            return used ? nil : event
        }
    }
    func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}
