import SwiftUI
import AppKit
import DirectionCore

/// The Films window: "Start a film" when there are none (01), otherwise every film as a card (02).
struct FilmsView: View {
    @Bindable var app: AppModel
    @State private var search = ""
    @State private var sort = Sort.recent
    @State private var selection: String?
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var trashing: FilmSummary?
    @FocusState private var searchFocused: Bool
    @FocusState private var gridFocused: Bool
    @FocusState private var renameFocused: Bool

    enum Sort: Hashable { case recent, name }

    private var films: [FilmSummary] { app.summaries }
    private var shown: [FilmSummary] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? films : films.filter { $0.name.localizedCaseInsensitiveContains(query) }
        switch sort {
        case .recent: return app.previewFilms != nil ? matching : matching.sorted { app.lastOpened($0.path) > app.lastOpened($1.path) }
        case .name: return matching.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                FilmsTitlebar(app: app, empty: films.isEmpty, sheetOpen: trashing != nil)
                if films.isEmpty { FilmsWelcome(app: app) } else { list }
            }
            .background(films.isEmpty ? Gate.Surface.canvas : Gate.Surface.ground)
            if let film = trashing { trashSheet(film) }
            GrainOverlay().ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in FilmsView.received(await FootageFiles.urls(from: providers), app: app) }
            return true
        }
        .task {
            // Each film's store is read again only after its database changes on disk.
            guard app.previewFilms == nil else { return }
            app.reloadFilms()
            while !Task.isCancelled {
                FilmLibraryIndex.shared.refresh(app.films)
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if app.previewFilms == nil { app.reloadFilms() }
        }
        .animation(gateAnimation(Gate.Motion.glide), value: trashing?.id)
    }

    // MARK: List (02)

    private var list: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Films").font(Gate.Font.brandXL).foregroundStyle(Gate.Text.primary)
                    Text(subtitle).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Gate.Text.disabled)
                    TextField("", text: $search)
                        .textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).focused($searchFocused)
                        .startPlaceholder("Search films", shown: search.isEmpty, inset: .init())
                        .accessibilityLabel("Search films")
                        .onExitCommand { search = ""; gridFocused = true }
                }
                .padding(.horizontal, 10).frame(width: 240, height: Gate.Size.control)
                .background(GateFieldBackground(focused: searchFocused))
                .background { Button("Find") { searchFocused = true }.keyboardShortcut("f").hidden() }
                GateSegmented(options: [(Sort.recent, "Recent"), (.name, "Name")], selection: $sort).accessibilityLabel("Sort")
            }
            .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 4)
            if shown.isEmpty {
                VStack(spacing: 12) {
                    Text("No films match \u{201C}\(search)\u{201D}.").font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary)
                    Button("Clear search") { search = "" }.buttonStyle(.gate(.ghost))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22, alignment: .top), count: 4), alignment: .leading, spacing: 28) {
                        ForEach(shown) { film in card(film) }
                        if search.isEmpty { newCard }
                    }
                    .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
                }
                .scrollIndicators(.automatic)
                .focusable().focusEffectDisabled().focused($gridFocused)
                .onMoveCommand(perform: move)
                .onKeyPress(.return) { guard !TextInput.hasFocus, let f = selected else { return .ignored }; open(f); return .handled }
                .onKeyPress(.delete, phases: .down) { press in
                    guard !TextInput.hasFocus, press.modifiers.contains(.command), let f = selected else { return .ignored }
                    trashing = f; return .handled
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Films, \(shown.count) items")
            }
        }
    }

    private var subtitle: String {
        let waiting = app.waitingCount
        return DailiesFormat.count(films.count, "film") + (waiting > 0 ? " \u{00B7} \(waiting) waiting for you" : "")
    }

    private var selected: FilmSummary? { shown.first { $0.id == (selection ?? shown.first?.id) } }

    private func card(_ film: FilmSummary) -> some View {
        FilmCardView(film: film, selected: film.id == selected?.id, progress: FilmLibraryIndex.shared.card(film.path)?.progress,
                     renaming: renaming == film.id ? $renameText : nil, renameFocused: $renameFocused,
                     commitRename: { commitRename(film) })
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 2).onEnded { open(film) })
            .simultaneousGesture(TapGesture().onEnded { selection = film.id; gridFocused = true })
            .contextMenu {
                Button("Open") { open(film) }
                Button("Open in New Window") {}.disabled(true)
                Button("Rename\u{2026}") { renameText = film.name; renaming = film.id; renameFocused = true }
                Button("Duplicate Brief") { duplicateBrief(film) }.disabled(FilmLibraryIndex.shared.card(film.path)?.brief.isComplete != true)
                Button("Show Footage in Finder") { showFootage(film) }.disabled(FilmLibraryIndex.shared.card(film.path)?.footage.isEmpty ?? true)
                Divider()
                Button("Move to Trash\u{2026}") { trashing = film }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(film.id == selected?.id ? .isSelected : [])
            .accessibilityLabel([film.name, film.status, film.waiting].compactMap { $0 }.joined(separator: ". "))
            .accessibilityAction { open(film) }
    }

    private var newCard: some View {
        Button { app.newFilm() } label: {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    HStack(spacing: 8) { Image(systemName: "plus").font(.system(size: 12)); Text("New film") }
                        .font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary)
                }
                .background(RoundedRectangle(cornerRadius: Gate.Radius.card).fill(Gate.Surface.sunken))
                .overlay(RoundedRectangle(cornerRadius: Gate.Radius.card).strokeBorder(Gate.Line.strong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New film (\u{2318}N)")
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func move(_ d: MoveCommandDirection) {
        guard !shown.isEmpty else { return }
        let i = shown.firstIndex { $0.id == selected?.id } ?? 0
        let step = d == .left ? -1 : d == .right ? 1 : d == .up ? -4 : 4
        selection = shown[max(0, min(shown.count - 1, i + step))].id
    }

    private func open(_ film: FilmSummary) {
        guard app.previewFilms == nil else { return }
        app.open(URL(fileURLWithPath: film.path))
    }

    private func commitRename(_ film: FilmSummary) {
        defer { renaming = nil }
        guard app.previewFilms == nil else { return }
        do { try FilmLibraryIndex.shared.rename(film.path, to: renameText); app.reloadFilms(); FilmLibraryIndex.shared.refresh(app.films) }
        catch { app.error = error.localizedDescription }
    }

    /// A new film that starts from this one's brief. You land on the brief to change what's different.
    private func duplicateBrief(_ film: FilmSummary) {
        guard let brief = FilmLibraryIndex.shared.card(film.path)?.brief else { return }
        app.newFilm()
        if let new = app.film { OnboardingSession.of(new).brief = brief }
    }

    private func showFootage(_ film: FilmSummary) {
        let urls = (FilmLibraryIndex.shared.card(film.path)?.footage ?? []).map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty { app.error = "This film's footage isn't where it was." } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    private func trashSheet(_ film: FilmSummary) -> some View {
        AttachedSheet(width: 460, onDismiss: { trashing = nil }) {
            SheetHeader(title: "Move \(film.name) to the Trash?", subtitle: "Your footage stays where it is.")
            Spacer().frame(height: 14)
            SheetFooter {
                EmptyView()
            } trailing: {
                Button("Cancel") { trashing = nil }.buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button("Move to Trash") { trash(film) }.buttonStyle(.gate(.danger)).keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func trash(_ film: FilmSummary) {
        trashing = nil
        guard app.previewFilms == nil else { return }
        let url = URL(fileURLWithPath: film.path), projectID = ProjectLibrary.projectID(at: url)
        NSWorkspace.shared.recycle([url]) { _, error in
            Task { @MainActor in
                if let error { app.error = error.localizedDescription; return }
                // Its cache goes with it, and the library forgets it (system.md › Deleting a film).
                FilmLibraryIndex.noteTrashed(film.path); CacheCleanup.forget(film: url, projectID: projectID); app.reloadFilms()
            }
        }
    }

    /// Dropped on the window: a film opens; footage or a folder starts a new film with it attached.
    static func received(_ urls: [URL], app: AppModel) {
        guard app.previewFilms == nil else { return }
        if let film = urls.first(where: { $0.pathExtension == "direction" }) { app.open(film); return }
        let footage = FootageFiles.expand(urls).footage
        guard !footage.isEmpty else { return }
        app.newFilm()
        if let film = app.film { OnboardingSession.of(film).add(footage, wait: false) }
    }

    /// Start from a folder…: a new film with the folder's footage attached; logging starts after the brief.
    static func startFromFolder(_ app: AppModel) {
        let panel = NSOpenPanel(); panel.title = "Start from a folder"; panel.prompt = "Start"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return }
        received(panel.urls, app: app)
    }
}

/// The Films window's titlebar: crumb, the editor's most urgent activity across films, New film.
private struct FilmsTitlebar: View {
    var app: AppModel
    var empty: Bool
    var sheetOpen: Bool
    var body: some View {
        ZStack {
            TitlebarDragArea()
            HStack(spacing: 10) {
                Color.clear.frame(width: 62, height: 1)
                Text("Films").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).padding(.horizontal, 7).allowsHitTesting(false)
                Spacer(minLength: 12)
                EditorPill(state: pill).help("The editor")
                // On the empty screen the hero's New film is the steel button; this one is plain.
                Button { app.newFilm() } label: { HStack(spacing: 6) { Image(systemName: "plus"); Text("New film"); KeyHint("\u{2318}N") } }
                    .buttonStyle(.gate(empty || sheetOpen ? .normal : .steel))
                    .disabled(sheetOpen)
            }
            .padding(.leading, 20).padding(.trailing, 12)
        }
        .frame(height: Gate.Size.titlebar)
        .background(empty ? Color.clear : Gate.Surface.ground)
        .overlay(alignment: .bottom) { if !empty { Hairline() } }
    }

    /// "Cutting Night shift" with its meter; "Cutting 2 films" when several are busy.
    private var pill: EditorPillState {
        let busy = app.summaries.filter(\.editorBusy)
        guard let first = busy.first else { return .ready }
        if busy.count > 1 { return .working("Cutting \(busy.count) films", nil) }
        let verb = first.status.contains("assembly") ? "Assembling" : "Cutting"
        let progress = FilmLibraryIndex.shared.card(first.path)?.progress ?? first.status.firstMatch(of: /(\d+) of (\d+)/).flatMap { m in Double(m.1).flatMap { a in Double(m.2).map { a / max(1, $0) } } }
        return .working("\(verb) \(first.name)", progress)
    }
}

/// One film: poster with its badge and duration, the name, then stage, what's waiting and when.
private struct FilmCardView: View {
    var film: FilmSummary
    var selected: Bool
    var progress: Double?
    var renaming: Binding<String>?
    var renameFocused: FocusState<Bool>.Binding
    var commitRename: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            poster
            if let renaming {
                TextField("Film name", text: renaming).textFieldStyle(.plain).font(Gate.Font.brand(size: 15, width: 112, weight: 700)).foregroundStyle(Gate.Text.primary)
                    .focused(renameFocused).onSubmit(commitRename).onExitCommand(perform: commitRename)
            } else {
                Text(film.name).font(Gate.Font.brand(size: 15, width: 112, weight: 700)).foregroundStyle(Gate.Text.primary).lineLimit(1)
            }
            HStack(spacing: 7) {
                if film.editorBusy { GemMark(size: 6) }
                Text(film.status).foregroundStyle(film.editorBusy ? Gate.Voice.agent : Gate.Text.tertiary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if hovered { Text("Open \u{21A9}").foregroundStyle(Gate.Text.disabled).fixedSize() }
            }
            .font(Gate.Font.small)
        }
        .onHover { hovered = $0 }
    }

    private var poster: some View {
        Color.clear.aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                Thumbnail(path: film.thumbnail, art: film.art).opacity(0.9)
                    .grayscale(film.locked ? 0.6 : 0).colorMultiply(film.locked ? Color(white: 0.8) : .white)
            }
            .overlay { if hovered { Color.white.opacity(0.04) } }
            .overlay(alignment: .topLeading) { badge.padding(8) }
            .overlay(alignment: .bottomLeading) { if let d = film.duration { HUDTag(d).padding(8) } }
            .background(Gate.Surface.panel)
            .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 14, y: 14)
            .overlay { if selected { RoundedRectangle(cornerRadius: Gate.Radius.card + 2, style: .continuous).strokeBorder(Gate.Text.primary, lineWidth: 2).padding(-2) } }
            .animation(gateAnimation(Gate.Motion.snap), value: selected)
    }

    @ViewBuilder private var badge: some View {
        if let waiting = film.waiting {
            HStack(spacing: 5) { PinMark(size: 8); Text(waiting) }
                .font(Gate.Font.mono).foregroundStyle(Gate.Voice.director)
                .padding(.horizontal, 7).frame(height: Gate.Size.chip)
                .background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(Gate.Voice.directorInk.opacity(0.85)))
        } else if film.locked {
            HStack(spacing: 5) { Image(systemName: "lock.fill").font(.system(size: 9)); Text("Picture locked") }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.secondary)
                .padding(.horizontal, 7).frame(height: Gate.Size.chip)
                .background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(Color.black.opacity(0.6)))
        }
    }
}

/// First launch (01): the mark, one sentence on what Direction does, and how it goes.
private struct FilmsWelcome: View {
    var app: AppModel
    /// Snapshots pin the mark's light; the app lets it move.
    var markMoment: Double? = nil
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            EllipticalGradient(stops: [.init(color: Gate.Steel.ramp[3], location: 0), .init(color: Gate.Surface.canvas, location: 0.7)], center: UnitPoint(x: 0.5, y: 0.42), startRadiusFraction: 0, endRadiusFraction: 0.5)
                .scaleEffect(x: 1, y: 0.9, anchor: UnitPoint(x: 0.5, y: 0.42))
            VStack(spacing: 22) {
                if BrandAssets.mark != nil {
                    ChromeMark(size: 168, at: markMoment)
                        .shadow(color: .black.opacity(0.85), radius: 22, y: 34)
                        .opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 8)
                }
                VStack(spacing: 22) {
                    Text("Start a film").font(Gate.Font.brand(size: 56, width: 125, weight: 800)).tracking(-1.4).foregroundStyle(Gate.Text.primary)
                    Text("Tell the editor what you're making, bring your footage, and it will build a first cut for you to watch. You direct. It cuts.")
                        .font(.system(size: 15)).foregroundStyle(Gate.Text.secondary).multilineTextAlignment(.center).lineSpacing(4.5)
                        .frame(maxWidth: 490).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button { app.newFilm() } label: { Label("New film", systemImage: "plus") }
                            .buttonStyle(.gate(.steel, .large)).keyboardShortcut(.defaultAction)
                        Button { FilmsView.startFromFolder(app) } label: { Label("Start from a folder\u{2026}", systemImage: "folder") }
                            .buttonStyle(.gate(.normal, .large))
                    }
                    .padding(.top, 6)
                }
                .opacity(shown ? 1 : 0)
            }
            .offset(y: -20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            howItWorks.padding(.bottom, 44)
        }
        .onAppear {
            guard app.previewFilms == nil else { shown = true; return }
            withAnimation(gateAnimation(Gate.Motion.glide)) { shown = true }
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var howItWorks: some View {
        HStack(spacing: 1) {
            step(1, "Brief", "A few sentences on how it should feel.")
            step(2, "Footage", "The editor logs and transcribes every take.")
            step(3, "First look", "It assembles a cut. You see it before anyone.")
            step(4, "Notes", "Watch, mark, give notes. It recuts.")
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Gate.Line.subtle)
        .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Gate.Radius.panel, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How it works, 4 items")
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(n)).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            }
            Text(text).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(width: 220, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Gate.Surface.ground)
        .accessibilityElement(children: .combine)
    }
}
