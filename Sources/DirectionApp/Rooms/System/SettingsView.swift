import SwiftUI
import AppKit
import DirectionCore

/// Settings › General, Editor, Engines, Cutting, Styles, Notifications, Shortcuts, Storage, Sharing.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, editor, engines, cutting, styles, library, notifications, shortcuts, storage, sharing
    var id: String { rawValue }
    /// A remembered tab; Footage and Services went into Engines.
    static func stored(_ raw: String?) -> SettingsTab? {
        guard let raw else { return nil }
        return ["footage", "services"].contains(raw) ? .engines : SettingsTab(rawValue: raw)
    }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .editor: "gem"
        case .engines: "cpu"
        case .cutting: "film"
        case .styles: "swatchpalette"
        case .library: "books.vertical"
        case .notifications: "bell"
        case .shortcuts: "keyboard"
        case .storage: "externaldrive"
        case .sharing: "person.2"
        }
    }
}

/// The Settings window (frames 42–48, 54): Direction › Settings… (⌘,). One size for every
/// section, like System Settings: 940 wide, a sidebar of sections on the left and the section
/// scrolling on the right, as tall as the screen allows up to 760. It never resizes, so it never
/// runs off the screen. The section's name is the window title; the last one is remembered;
/// every change applies at once. ⌘1…⌘9 choose a section; esc and ⌘W close it.
struct SettingsView: View {
    var app: AppModel?
    /// Snapshots and previews: sample numbers, no system queries, and the whole section drawn.
    var preview = false
    /// Settings › Shortcuts starts recording this row (frame 46).
    var recording: ShortcutAction? = nil
    @AppStorage(SettingsKey.settingsTab) private var storedTab = SettingsTab.general.rawValue
    @State private var tab: SettingsTab

    init(app: AppModel? = nil, initialTab: SettingsTab? = nil, preview: Bool = false, recording: ShortcutAction? = nil) {
        self.app = app; self.preview = preview; self.recording = recording
        let stored = SettingsTab.stored(UserDefaults.standard.string(forKey: SettingsKey.settingsTab))
        _tab = State(initialValue: initialTab ?? stored ?? .general)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Snapshots draw the title bar's row; the real window has its own.
            if preview {
                Text(tab.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.secondary)
                    .frame(maxWidth: .infinity).frame(height: 28)
                SystemHairline()
            }
            HStack(spacing: 0) {
                SettingsSidebar(tab: select)
                Rectangle().fill(Gate.Line.subtle).frame(width: 1)
                Group {
                    if preview { pane.frame(maxHeight: .infinity, alignment: .top) }
                    else { ScrollView(.vertical) { pane }.scrollIndicators(.automatic).id(tab) }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: Gate.Size.settingsWidth, height: preview ? nil : windowHeight)
        .background(Gate.Surface.ground)
        .overlay { GrainOverlay().allowsHitTesting(false) }
        .background { if !preview { SettingsWindowConfigurator(title: tab.title) } }
        .background { tabKeys }
        .preferredColorScheme(.dark)
        .onChange(of: storedTab) { _, new in if let t = SettingsTab.stored(new), t != tab { select(t) } }
    }

    /// 760, or the screen's height less the title bar and a margin on a smaller screen.
    private var windowHeight: CGFloat {
        guard let screen = NSScreen.main?.visibleFrame.height else { return Gate.Size.settingsHeight }
        return max(420, min(Gate.Size.settingsHeight, screen - 28 - 48))
    }

    private var select: Binding<SettingsTab> {
        Binding(get: { tab }, set: { select($0) })
    }
    private func select(_ new: SettingsTab) {
        // Nothing moves: the window keeps its size and only the section's content fades in.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { tab = new }
        if storedTab != new.rawValue { storedTab = new.rawValue }
    }

    private var pane: some View { paneContent.id(tab).modifier(PaneFadeIn()) }

    @ViewBuilder private var paneContent: some View {
        switch tab {
        case .general: GeneralPane(preview: preview)
        case .editor: EditorPane(app: app)
        case .engines: EnginesPane(app: app, preview: preview)
        case .cutting: CuttingPane(app: app, preview: preview)
        case .styles: StylesPane(app: app, preview: preview)
        case .library: LibraryPane(preview: preview)
        case .notifications: NotificationsPane(preview: preview)
        case .shortcuts: ShortcutsPane(recording: recording)
        case .storage: StoragePane(app: app, preview: preview)
        case .sharing: SharingPane()
        }
    }

    /// ⌘1…⌘9 choose a section while Settings is key; esc closes the window.
    private var tabKeys: some View {
        ZStack {
            ForEach(Array(SettingsTab.allCases.prefix(9).enumerated()), id: \.offset) { i, t in
                Button(t.title) { select(t) }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
            }
            Button("Close") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut(.cancelAction)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

/// A pane's content fades in when its tab is chosen; nothing slides or resizes in motion.
private struct PaneFadeIn: ViewModifier {
    @State private var shown = false
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0)
            .onAppear { if SettingsKey.reducesMotion { shown = true } else { withAnimation(.easeOut(duration: 0.16)) { shown = true } } }
    }
}

/// The sections, top to bottom: an 18 icon and a 13 pt name, 30 tall; the chosen one on a
/// `--raised` fill, radius 7, in text-1.
struct SettingsSidebar: View {
    @Binding var tab: SettingsTab
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { t in item(t) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .frame(width: Gate.Size.settingsSidebar)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Gate.Surface.panel.opacity(0.5))
    }

    private func item(_ t: SettingsTab) -> some View {
        let on = t == tab
        return Button { tab = t } label: {
            HStack(spacing: 9) {
                Group {
                    if t == .editor { RoundedRectangle(cornerRadius: 1.5).frame(width: 8, height: 8).rotationEffect(.degrees(45)) }
                    else { Image(systemName: t.icon).font(.system(size: 13, weight: .medium)) }
                }
                .frame(width: 18, height: 18)
                Text(t.title).font(.system(size: 13, weight: on ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? Gate.Text.primary : Gate.Text.secondary)
            .padding(.horizontal, 8).frame(height: 30)
            .background { if on { RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.raised) } }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .help("\(t.title) (\u{2318}\(SettingsTab.allCases.firstIndex(of: t)! + 1))")
    }
}

/// The pane body: padding 4/28/22, groups stacked.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Window

/// A standard title bar in the window's ground color, titled with the section's name, with the
/// traffic lights at x 20. The sidebar and the section sit below it.
struct SettingsWindowConfigurator: NSViewRepresentable {
    var title: String
    func makeNSView(context: Context) -> SettingsWindowView { SettingsWindowView() }
    func updateNSView(_ view: SettingsWindowView, context: Context) { view.title = title; view.apply() }
}

final class SettingsWindowView: NSView {
    var title = "General"
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
        guard let window else { return }
        for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.layoutLights() } })
        }
    }
    func apply() {
        guard let window else { return }
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.styleMask.remove(.fullSizeContentView)
        window.tabbingMode = .disallowed
        window.backgroundColor = NSColor(Gate.Surface.ground)
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbar = nil
        layoutLights()
    }
    private func layoutLights() {
        guard let window, let close = window.standardWindowButton(.closeButton), let container = close.superview else { return }
        for (i, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = window.standardWindowButton(type) else { continue }
            b.setFrameOrigin(NSPoint(x: Gate.Size.trafficLightsX + CGFloat(i) * 20, y: container.frame.height - 14 - b.frame.height / 2))
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

/// Opens Settings at a tab (and flashes a row). Use from views; menus use `SettingsLink`-style buttons below.
struct OpenSettingsButton<Label: View>: View {
    var tab: SettingsTab
    var flash: String? = nil
    @ViewBuilder var label: Label
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button {
            UserDefaults.standard.set(tab.rawValue, forKey: SettingsKey.settingsTab)
            if let flash { UserDefaults.standard.set(flash, forKey: SettingsKey.settingsFlash) }
            openSettings()
        } label: { label }
    }
}
