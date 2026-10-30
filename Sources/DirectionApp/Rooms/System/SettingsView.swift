import SwiftUI
import AppKit
import DirectionCore

/// Settings › General, Editor, Footage, Cutting, Services, Notifications, Shortcuts, Storage, Sharing.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, editor, footage, cutting, services, notifications, shortcuts, storage, sharing
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .editor: "gem"
        case .footage: "film.stack"
        case .cutting: "film"
        case .services: "key"
        case .notifications: "bell"
        case .shortcuts: "keyboard"
        case .storage: "externaldrive"
        case .sharing: "person.2"
        }
    }
}

/// The Settings window (frames 42–48): Direction › Settings… (⌘,). A 720 pt window whose
/// height fits the pane, toolbar tabs drawn in Gate, the tab's name as the window title,
/// the last tab remembered, every change applied at once. esc and ⌘W close it.
struct SettingsView: View {
    var app: AppModel?
    /// Snapshots and previews: sample numbers, no system queries.
    var preview = false
    /// Settings › Shortcuts starts recording this row (frame 46).
    var recording: ShortcutAction? = nil
    @AppStorage(SettingsKey.settingsTab) private var storedTab = SettingsTab.general.rawValue
    @State private var tab: SettingsTab
    /// The pane's own height, so the window fits it, or scrolls it when the screen is shorter.
    @State private var paneHeight: CGFloat = 0

    init(app: AppModel? = nil, initialTab: SettingsTab? = nil, preview: Bool = false, recording: ShortcutAction? = nil) {
        self.app = app; self.preview = preview; self.recording = recording
        let stored = UserDefaults.standard.string(forKey: SettingsKey.settingsTab).flatMap(SettingsTab.init(rawValue:))
        _tab = State(initialValue: initialTab ?? stored ?? .general)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsToolbar(tab: select)
            // A pane taller than the screen scrolls under the toolbar. Without this the window grew past
            // the screen, macOS held it to the screen, and the overflow cut the title row off the top.
            ScrollView(.vertical) {
                pane.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { paneHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
            .frame(height: paneHeight > 0 ? min(paneHeight, maxPaneHeight) : nil)
        }
        .frame(width: Gate.Size.settingsWidth)
        .background(Gate.Surface.ground)
        .overlay { GrainOverlay().allowsHitTesting(false) }
        // The toolbar is drawn under the transparent title bar, with the traffic lights in its title row.
        .ignoresSafeArea(.container, edges: .top)
        .background { if !preview { SettingsWindowConfigurator(title: tab.title) } }
        .background { tabKeys }
        .preferredColorScheme(.dark)
        .onChange(of: storedTab) { _, new in if let t = SettingsTab(rawValue: new), t != tab { select(t) } }
    }

    /// The screen's height less the title bar, the toolbar and a margin. Snapshots draw every pane whole.
    private var maxPaneHeight: CGFloat {
        guard !preview, let screen = NSScreen.main?.visibleFrame.height else { return .infinity }
        return max(360, screen - 28 - 76 - 24)
    }

    private var select: Binding<SettingsTab> {
        Binding(get: { tab }, set: { select($0) })
    }
    private func select(_ new: SettingsTab) {
        // No animated layout: the window resizes at once and only the pane's content fades in.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { tab = new }
        if storedTab != new.rawValue { storedTab = new.rawValue }
    }

    private var pane: some View { paneContent.id(tab).modifier(PaneFadeIn()) }

    @ViewBuilder private var paneContent: some View {
        switch tab {
        case .general: GeneralPane(preview: preview)
        case .editor: EditorPane(app: app)
        case .footage: FootagePane(preview: preview)
        case .cutting: CuttingPane(app: app)
        case .services: ServicesPane(preview: preview)
        case .notifications: NotificationsPane(preview: preview)
        case .shortcuts: ShortcutsPane(recording: recording)
        case .storage: StoragePane(app: app, preview: preview)
        case .sharing: SharingPane()
        }
    }

    /// ⌘1…⌘7 switch tabs while Settings is key; esc closes the window.
    private var tabKeys: some View {
        ZStack {
            ForEach(Array(SettingsTab.allCases.enumerated()), id: \.offset) { i, t in
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

/// The 76 pt toolbar: the pane name over a row of 76 pt tabs.
struct SettingsToolbar: View {
    @Binding var tab: SettingsTab
    var body: some View {
        VStack(spacing: 0) {
            Text(tab.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.secondary)
                .frame(maxWidth: .infinity).frame(height: 27)
                .background(SettingsDragArea())
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { t in tabButton(t) }
            }
            .frame(maxWidth: .infinity).frame(height: 48, alignment: .top)
            SystemHairline()
        }
        .background(Gate.Surface.ground)
    }

    private func tabButton(_ t: SettingsTab) -> some View {
        let on = t == tab
        return Button { tab = t } label: {
            VStack(spacing: 3) {
                Group {
                    if t == .editor { RoundedRectangle(cornerRadius: 1.5).frame(width: 9, height: 9).rotationEffect(.degrees(45)) }
                    else { Image(systemName: t.icon).font(.system(size: 15, weight: .medium)) }
                }
                .frame(width: 18, height: 18)
                Text(t.title).font(.system(size: 11))
            }
            .foregroundStyle(on ? Gate.Text.primary : Gate.Text.tertiary)
            .frame(width: 74).padding(.top, 5).padding(.bottom, 6)
            .background { if on { RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.raised) } }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .help("\(t.title) (⌘\(SettingsTab.allCases.firstIndex(of: t)! + 1))")
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

/// Hides the system title (it's drawn in the toolbar), keeps the traffic lights at x 20 in the
/// 28 pt title row, and sets the window title to the tab's name for the Window menu and Mission Control.
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
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
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

/// The title row drags the window like a normal title bar.
private struct SettingsDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { if event.clickCount == 2 { return }; window?.performDrag(with: event) }
    }
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
