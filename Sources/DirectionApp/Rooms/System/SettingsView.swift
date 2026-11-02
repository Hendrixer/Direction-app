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
    @State private var pages = SettingsPages()

    init(app: AppModel? = nil, initialTab: SettingsTab? = nil, preview: Bool = false, recording: ShortcutAction? = nil, page: SettingsPage? = nil) {
        self.app = app; self.preview = preview; self.recording = recording
        let stored = SettingsTab.stored(UserDefaults.standard.string(forKey: SettingsKey.settingsTab))
        let tab = initialTab ?? stored ?? .general
        _tab = State(initialValue: tab)
        let pages = SettingsPages(); pages.root = tab.title
        if let page { pages.stack = [page] }
        _pages = State(initialValue: pages)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Snapshots draw the title bar's row; the real window has its own.
            if preview {
                Text(pages.stack.last?.title ?? tab.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.secondary)
                    .frame(maxWidth: .infinity).frame(height: 28)
                SystemHairline()
            }
            HStack(spacing: 0) {
                SettingsSidebar(tab: select)
                Rectangle().fill(Gate.Line.subtle).frame(width: 1)
                Group {
                    // A page opened from the section (a style, the library) takes the section's place, with a way back.
                    if let page = pages.stack.last { page.view.id(page.id).modifier(PaneFadeIn()).frame(maxHeight: .infinity, alignment: .top) }
                    else if preview { pane.frame(maxHeight: .infinity, alignment: .top) }
                    else { ScrollView(.vertical) { pane }.scrollIndicators(.automatic).id(tab) }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.settingsPages, pages)
        .environment(\.settingsPreview, preview)
        .frame(width: Gate.Size.settingsWidth, height: preview ? nil : windowHeight)
        .background(Gate.Surface.ground)
        .grainOverlay()
        .background { if !preview { SettingsWindowConfigurator(title: pages.stack.last?.title ?? tab.title) } }
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
        withTransaction(t) { tab = new; pages.stack = []; pages.root = new.title }
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
        case .library: LibraryPane(app: app, preview: preview)
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
            // esc goes back from a page first, then closes the window.
            Button("Close") { if pages.stack.isEmpty { NSApp.keyWindow?.performClose(nil) } else { pages.back() } }.keyboardShortcut(.cancelAction)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

// MARK: Pages

/// A page inside a section: a style, the library. It takes the section's place in the window, with Back
/// above it, instead of opening a sheet or another window.
struct SettingsPage: Identifiable {
    var id: String
    var title: String
    var view: AnyView
    init<V: View>(id: String, title: String, @ViewBuilder _ view: () -> V) { self.id = id; self.title = title; self.view = AnyView(view()) }
}

/// The pages open in the Settings window, the latest last; switching sections closes them.
@MainActor @Observable final class SettingsPages {
    var stack: [SettingsPage] = []
    /// The section's name, for Back from the first page.
    var root = ""
    func open(_ page: SettingsPage) { stack.append(page) }
    func back() { _ = stack.popLast() }
    /// What Back returns to; just "Back" when that has the page's own name (Library › Library).
    var backTitle: String {
        let title = stack.count > 1 ? stack[stack.count - 2].title : root
        return title == stack.last?.title ? "Back" : title
    }
}

extension EnvironmentValues {
    @Entry var settingsPages: SettingsPages? = nil
    /// Snapshots draw a section or page whole, without scrolling.
    @Entry var settingsPreview = false
}

/// A page's frame: Back and the page's own buttons on a bar, its title, the page scrolling under it, and
/// buttons pinned at the foot when it has any (a new style's Make Style).
struct SettingsPageLayout<Content: View, Actions: View, Foot: View>: View {
    var title: String
    var subtitle: String? = nil
    /// The foot's buttons show only while there's something to confirm.
    var footShown = true
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content
    @ViewBuilder var foot: Foot
    @Environment(\.settingsPages) private var pages
    @Environment(\.settingsPreview) private var preview

    var body: some View {
        VStack(spacing: 0) {
            SettingsBackBar { actions }
            Group {
                if preview { page }
                else { ScrollView(.vertical) { page }.scrollIndicators(.automatic) }
            }
            .frame(maxHeight: preview ? nil : .infinity, alignment: .top)
            if Foot.self != EmptyView.self && footShown {
                HStack(spacing: 8) { foot }
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .overlay(alignment: .top) { SystemHairline() }
            }
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary).accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.45, size: 12).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.horizontal, 30).padding(.top, 2).padding(.bottom, 8)
            SettingsPane { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Back to where the page came from, the page's title beside it when the page has no heading of its own,
/// and the page's buttons at the right.
struct SettingsBackBar<Actions: View>: View {
    var title: String? = nil
    @ViewBuilder var actions: Actions
    @Environment(\.settingsPages) private var pages
    var body: some View {
        HStack(spacing: 8) {
            Button { pages?.back() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)); Text(pages?.backTitle ?? "Back") }
            }
            .buttonStyle(.gate(.ghost, .small))
            .help("Back to \(pages?.backTitle ?? "the section") (esc)")
            if let title { Text(title).font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary).lineLimit(1).padding(.leading, 6).accessibilityAddTraits(.isHeader) }
            Spacer(minLength: 8)
            actions
        }
        .padding(.leading, 20).padding(.trailing, 24).frame(height: 44)
    }
}

extension SettingsBackBar where Actions == EmptyView {
    init(title: String?) { self.init(title: title) { EmptyView() } }
}

extension SettingsPageLayout where Foot == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, footShown: false, actions: actions, content: content, foot: { EmptyView() })
    }
}

/// A section row that opens a page: the whole row is the button, with a chevron at its end.
struct SettingsLinkRow: View {
    var label: String
    var detail: String? = nil
    var first = false
    var open: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: open) {
            SettingsRow(label: label, detail: detail, first: first, minHeight: 56) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Gate.Text.tertiary)
            }
            .background(hovering ? Gate.Surface.hover.opacity(0.5) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityHint(detail ?? "")
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
