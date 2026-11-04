import SwiftUI
import DirectionCore

/// Dailies: every take by scene and setup. The director circles; the editor only suggests.
/// Sidebar of scenes and bins, then the scene's takes, Unsorted, Not usable, or one take open.
struct DailiesRoom: View {
    @Bindable var model: FilmModel
    @Environment(\.dailiesPreview) private var preview
    var body: some View {
        HStack(spacing: 0) {
            // Search results aren't a scene: no row is current while they show (frame 60).
            DailiesSidebar(model: model, current: model.index.searching && model.openTakeID == nil ? nil : currentBin).frame(width: Gate.Size.sidebar)
            VStack(spacing: 0) {
                AssemblyQuestions(model: model)
                main.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Gate.Surface.ground)
        .overlay(alignment: .topLeading) {
            // A drag in flight, as frame 09 draws it (snapshots only; the system draws the real one).
            if let target = preview.dropSceneID, let i = model.scenes.firstIndex(where: { $0.id == target }) {
                DailiesDragGhost(model: model, takeID: preview.draggingTakeID, scene: model.scenes[i]).offset(x: 8, y: 50 + CGFloat(i) * 31)
            }
        }
        .background {
            // ⇧⌘1 jumps to Unsorted from anywhere in the room.
            Button("Unsorted") { model.openTakeID = nil; model.selectedSceneID = DailiesBin.unsorted }
                .keyboardShortcut("1", modifiers: [.command, .shift]).hidden()
        }
        .modifier(DailiesFindKey(model: model))
    }

    /// The sidebar row on show: the chosen scene or bin, else the first scene.
    private var currentBin: String? {
        if let id = model.selectedSceneID, id == DailiesBin.unsorted || id == DailiesBin.unusable || model.scene(id) != nil { return id }
        return model.scenes.first?.id ?? (model.dailiesUnsorted.isEmpty ? nil : DailiesBin.unsorted)
    }

    @ViewBuilder private var main: some View {
        if let id = model.openTakeID, model.dailies.takes[id] != nil {
            DailiesTakeViewer(model: model, takeID: id, bin: currentBin)
        } else if model.index.searching {
            // Frame 60: results replace the take grid until esc.
            DailiesSearchView(model: model)
        } else {
            switch currentBin {
            case DailiesBin.unsorted?: DailiesUnsortedView(model: model)
            case DailiesBin.unusable?: DailiesUnusableView(model: model)
            case let id?: DailiesSceneView(model: model, sceneID: id).id(id)
            case nil:
                EmptyStateView(art: nil, title: "No scenes yet", message: model.isLogging ? "The editor is still logging. Takes appear here as it places them in scenes." : "Bring footage and the editor will log it into scenes.") {
                    Button { model.chooseFootage() } label: { Label("Bring Footage\u{2026}", systemImage: "folder") }.buttonStyle(.gate)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The editor's questions while it builds the assembly, above the takes they're about. Notes opens
/// with the first cut, so until then they wait here; the pill's Answer brings you to them (start.md › 06).
struct AssemblyQuestions: View {
    @Bindable var model: FilmModel

    private var questions: [EditorQuestion] {
        guard model.cuts.isEmpty, let t = model.openTurnover, t.kind == "assembly" else { return [] }
        return model.openQuestions.filter { $0.turnoverID == t.id }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(questions) { q in
                    if q.kind == "cant" { CantNotice(model: model, question: q, inset: false) }
                    else { QuestionCard(model: model, question: q, primary: false, steel: false) }
                }
                .transition(.noticeArrival)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 4)
        }
    }
}

// MARK: Sidebar

/// Scenes with their circle counts, then Unsorted and Not usable. Rows take dropped takes.
struct DailiesSidebar: View {
    @Bindable var model: FilmModel
    var current: String?
    @Environment(\.dailiesPreview) private var preview
    @State private var dropTarget: String?
    @State private var renaming: String?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @State private var deleting: DailiesScene?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel("Scenes")
                Spacer(minLength: 0)
                Button { if let id = model.addScene() { model.selectedSceneID = id; startRename(id, "New scene") } } label: { Image(systemName: "plus") }
                    .buttonStyle(.gate(.ghost, .small, icon: true)).disabled(model.isPreview)
                    .help("New scene")
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.scenes) { scene in sceneRow(scene) }
                    SectionLabel("Not in a scene").frame(height: 11).padding(.horizontal, 9).padding(.top, 14).padding(.bottom, 6)
                    binRow(DailiesBin.unsorted, icon: "folder", title: "Unsorted", count: model.dailiesUnsorted.count)
                    binRow(DailiesBin.unusable, icon: "trash", title: "Not usable", count: model.dailiesUnusable.count)
                    DailiesMadeGroup(model: model)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            footer
        }
        .background(Gate.Surface.ground)
        .hairlineBorder(.trailing)
        .onChange(of: renameFocused) { _, focused in if !focused { commitRename() } }
        .alert(deleting.map { "Delete scene \($0.number), \($0.title)?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Scene", role: .destructive) { if let s = deleting { model.deleteScene(s.id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            let n = deleting.map { model.dailiesTakes(inScene: $0.id).count } ?? 0
            Text(n == 0 ? "You can undo this." : "Its \(n == 1 ? "take goes" : "\(n) takes go") back to Unsorted, circles and all. Nothing on disk changes, and you can undo it.")
        }
    }

    private func startRename(_ id: String, _ text: String) {
        renameText = text; renaming = id
        DispatchQueue.main.async { renameFocused = true }
    }
    private func commitRename() {
        guard let id = renaming else { return }
        let text = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, text != model.scene(id)?.title { model.renameScene(id, to: text) }
        renaming = nil
    }

    private func sceneRow(_ scene: DailiesScene) -> some View {
        let circles = model.dailiesCircles(inScene: scene.id)
        return row(id: scene.id, accessibility: "Scene \(scene.number), \(scene.title). \(circles) circled\(scene.locked ? ". Locked" : "")") {
            Text(String(scene.number)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled).frame(width: 12, alignment: .leading)
            if renaming == scene.id {
                TextField("Scene name", text: $renameText).textFieldStyle(.plain).font(.system(size: 13)).focused($renameFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { renaming = nil; renameFocused = false }
            } else {
                Text(scene.title).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            }
            if scene.locked { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Gate.Text.tertiary) }
            if circles > 0 {
                HStack(spacing: 4) { Text(String(circles)); Circle().strokeBorder(Gate.Voice.director, lineWidth: 1.25).frame(width: 7, height: 7) }
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Voice.director)
            } else {
                Text("0").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
            }
        }
        .contextMenu {
            Button("Open") { open(scene.id) }
            Button("Rename\u{2026}") { startRename(scene.id, scene.title) }
            Button(scene.locked ? "Unlock Scene" : "Lock Scene") { model.lockScene(scene.id, !scene.locked) }
            Divider()
            Button("Circle Suggestions in This Scene") { model.toggleCircles(model.dailiesTakes(inScene: scene.id).filter { $0.suggestion != nil && !$0.circled }.map(\.assetID)) }
                .disabled(!model.dailiesTakes(inScene: scene.id).contains { $0.suggestion != nil && !$0.circled })
            Divider()
            Button("Delete Scene\u{2026}", role: .destructive) { deleting = scene }
                .disabled(scene.locked || model.isPreview)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { if renaming != scene.id { startRename(scene.id, scene.title) } })
        .help("Double-click to rename")
    }

    private func binRow(_ id: String, icon: String, title: String, count: Int) -> some View {
        row(id: id, accessibility: "\(title), \(count) takes") {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Gate.Text.tertiary).frame(width: 15)
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(String(count)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
        }
    }

    private func row<Content: View>(id: String, accessibility: String, @ViewBuilder content: () -> Content) -> some View {
        let on = current == id
        let target = dropTarget == id || preview.dropSceneID == id
        return Button { open(id) } label: {
            HStack(spacing: 9) { content() }
                .font(.system(size: 13)).foregroundStyle(on || target ? Gate.Text.primary : Gate.Text.secondary)
                .padding(.horizontal, 9).frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7).fill(on || target ? Gate.Surface.raised : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(target ? Gate.Text.primary : on ? Gate.Line.subtle : .clear, lineWidth: target ? 1.5 : 1))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
                .dropDestination(for: String.self) { items, _ in drop(items, on: id) } isTargeted: { over in
            if over { dropTarget = id } else if dropTarget == id { dropTarget = nil }
        }
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func open(_ id: String) {
        if renaming != nil && renaming != id { commitRename() }
        model.openTakeID = nil
        model.selectedSceneID = id
    }

    /// Takes dropped from a grid: onto a scene moves them there, onto Unsorted takes them out, onto Not usable sets them aside.
    private func drop(_ items: [String], on id: String) -> Bool {
        let ids = items.flatMap { $0.split(separator: "\n").map(String.init) }.filter { model.dailies.takes[$0] != nil }
        guard !ids.isEmpty else { return false }
        switch id {
        case DailiesBin.unusable: model.toggleUnusable(ids.filter { model.dailies.takes[$0]?.unusable == false })
        case DailiesBin.unsorted: model.moveTakes(ids, to: nil)
        default: model.moveTakes(ids, to: id)
        }
        dropTarget = nil
        return true
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let c = model.copyingFootage {
                HStack(spacing: 8) {
                    Text("Copying \(min(c.total, c.done + 1)) of \(c.total)").lineLimit(1).fixedSize()
                    GateProgress(value: c.fraction).frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Copying \(min(c.total, c.done + 1)) of \(c.total) into the film, \(Int(c.fraction * 100)) percent")
            }
            HStack(spacing: 8) {
                Image(systemName: "film").font(.system(size: 10.5)).frame(width: 12)
                Text("\(DailiesFormat.count(model.footage.count, "take")) \u{00B7} \(DailiesFormat.hoursMinutes(model.dailiesTotalSeconds))")
            }
            HStack(spacing: 8) {
                RingMark(size: 8)
                Text("\(model.circledCount) circled \u{00B7}")
                GemMark(size: 6.4).padding(.leading, -2)
                Text("\(model.suggestedCount) suggested")
            }
        }
        .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        .hairlineBorder(.top)
        .accessibilityElement(children: .combine)
    }
}

/// The drawn drag in flight (frame 09): a tilted thumbnail and a "Move to" tip beside the target row.
private struct DailiesDragGhost: View {
    var model: FilmModel
    var takeID: String?
    var scene: DailiesScene
    @Environment(\.dailiesPreview) private var preview
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let id = takeID {
                DailiesTakeThumb(asset: model.asset(id), art: preview.art[id] ?? model.dailiesArt(id), preview: model.isPreview)
                    .frame(width: 168, height: 94.5).clipShape(RoundedRectangle(cornerRadius: 7))
                    .rotationEffect(.degrees(-3)).opacity(0.92).shadow(color: .black.opacity(0.9), radius: 30, y: 30)
                    .offset(x: 140, y: -3)
            }
            Text("Move to \(scene.label)").font(.system(size: 12)).foregroundStyle(Gate.Text.primary)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Gate.Steel.ramp[5]).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.strong, lineWidth: 1)).shadow(color: .black.opacity(0.8), radius: 10, y: 8))
                .fixedSize().offset(x: 164, y: 101)
        }
        .frame(width: 0, height: 0, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

extension FilmModel {
    /// Before the first cut: build the assembly from the circles. After: hand new circles to the next turnover as a note.
    var dailiesPrimary: PrimaryAction? {
        if cuts.isEmpty {
            let building = openTurnover?.kind == "assembly"
            // Nothing circled: the editor picks the takes, the ones it suggested while logging. Circles are the
            // director's say, never a gate.
            let picks = circledCount == 0
            let help = building ? "The editor is building the assembly" : openTurnover != nil ? "The editor is still working" : picks && isLogging ? "The editor is still logging the takes" : picks ? "The editor picks the takes. Circle any you want first (C) (\u{2318}\u{21A9})" : "Build the first cut from your circles (\u{2318}\u{21A9})"
            return PrimaryAction(title: building ? "Assembling\u{2026}" : picks ? "Assemble" : "Assemble from circles", count: picks ? nil : String(circledCount), enabled: openTurnover == nil && !(picks && isLogging), help: help) {
                self.assembleFromCircles()
            }
        }
        let since = lastTurnover?.createdAt ?? 0
        let fresh = dailiesLogged.filter { $0.circled && ($0.circledAt ?? 0) > since }
        return PrimaryAction(title: "Use circles in next cut", count: String(fresh.count), enabled: !fresh.isEmpty, help: fresh.isEmpty ? "Circle a take since the last turnover first" : "Add a note asking for your new circles (\u{2318}\u{21A9})") {
            let numbers = Array(Set(fresh.compactMap { self.scene($0.sceneID)?.number })).sorted().map(String.init)
            let scenes = numbers.isEmpty ? "" : numbers.count == 1 ? " in scene \(numbers[0])" : " in scenes \(numbers.dropLast().joined(separator: ", ")) and \(numbers.last!)"
            self.addNote(text: "Use my new circles\(scenes).", kind: .story)
            self.notesTab = .sheet
            self.go(.cut)
        }
    }
}
