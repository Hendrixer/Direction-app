import SwiftUI
import AppKit
import DirectionCore

// Styles (specs/styles.md): the brief's Style question, asking the editor to make one, and
// Settings › Styles, where each style's name, sentence and guide can be written by hand.

/// Two sample styles for snapshots and previews, so nothing reads the director's own folder there.
enum StyleSamples {
    static let folder = URL(fileURLWithPath: "/tmp/direction-sample-styles", isDirectory: true)
    static var styles: [Style] {
        var a = StyleContents(); a.graphics = ["captions", "lower-third", "title"]; a.transitions = ["push.metal"]; a.sounds = ["pop.wav", "whoosh.wav"]; a.look = true
        var b = StyleContents(); b.graphics = ["chapter-card"]; b.music = ["bed.m4a"]
        return [
            Style(id: "desk-talk", url: folder.appendingPathComponent("desk-talk"), name: "Desk Talk", summary: "Quick explainers: 3-second shots, punch-ins, bold captions.", updatedAt: 0, tokens: .object([:]), contents: a),
            Style(id: "long-walk", url: folder.appendingPathComponent("long-walk"), name: "Long Walk", summary: "Slow and wide. Shots hold; music carries it.", updatedAt: 0, tokens: .object([:]), contents: b),
        ]
    }
}

/// The brief's Style question: None, or one of your styles. Picking one gives the film its own copy
/// when the brief is saved.
struct BriefStylePicker: View {
    var model: FilmModel
    @Binding var style: String?
    @State private var styles: [Style] = []
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BriefFlow(spacing: 8) {
                card(nil)
                ForEach(styles) { card($0) }
            }
            if styles.isEmpty {
                Text("No styles yet. A style keeps your videos looking like yours from one to the next: the pace, titles, captions, transitions and sound.")
                    .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Make one with the editor\u{2026}") { asking = true }.buttonStyle(.gate(.ghost, .small))
                    .popover(isPresented: $asking, arrowEdge: .bottom) { MakeStylePopover(model: model) { asking = false } }
                OpenSettingsButton(tab: .styles) { Text("Your styles\u{2026}") }.buttonStyle(.gate(.ghost, .small))
            }
        }
        .task { load() }
        .onChange(of: model.runs.runs.filter { $0.job == .style }.map(\.state)) { _, _ in load() }
    }

    private func load() { styles = model.isPreview ? StyleSamples.styles : StyleLibrary.list(in: SharedSettings.stylesFolder) }

    private func card(_ s: Style?) -> some View {
        let chosen = style == s?.id
        return Button { style = s?.id } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(s?.name ?? "None").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).lineLimit(1)
                Text(s?.summary ?? "Just the brief and your notes.").font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let line = s?.contents.line, !line.isEmpty { Text(line).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(1).minimumScaleFactor(0.85) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(width: s == nil ? 126 : 248, height: 86, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).fill(chosen ? Gate.Voice.directorWash : Gate.Surface.panel))
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).strokeBorder(chosen ? Gate.Voice.director : Gate.Line.subtle, lineWidth: chosen ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.map { "Style: \($0.name). \($0.summary)" } ?? "No style")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// "Make one with the editor": what it should be like, in your words, and whether to learn from this film.
struct MakeStylePopover: View {
    var model: FilmModel
    var done: () -> Void
    @State private var request = ""
    @State private var fromFilm = true
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make a style").font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
            Text("Say how your videos should look, sound and move. Name channels or videos you like and what you like about them.")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
            GateTextArea(text: $request, placeholder: "Fast and friendly, like a good tech explainer. Bold yellow captions, a whoosh on every cut to the screen.", minHeight: 92)
            if !model.cuts.isEmpty {
                Toggle("Learn from how \(model.latestCut?.name ?? "this film") is cut", isOn: $fromFilm).toggleStyle(.checkbox).font(Gate.Font.small)
            }
            if failed {
                Text("Direction doesn\u{2019}t start the editor here. Ask your own session: \u{201C}Make me a style\u{201D} (the make-style skill).")
                    .font(Gate.Font.small).foregroundStyle(Gate.State.alert).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("It goes in your styles when it\u{2019}s done.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                Spacer()
                Button("Cancel", action: done).buttonStyle(.gate(.normal, .small)).keyboardShortcut(.cancelAction)
                Button("Make it") {
                    if model.runs.makeStyle(model, request: request.trimmingCharacters(in: .whitespacesAndNewlines), fromFilm: fromFilm && !model.cuts.isEmpty) { done() } else { failed = true }
                }
                .buttonStyle(.gate(.steel, .small)).disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.cuts.isEmpty)
            }
        }
        .padding(16).frame(width: 380)
    }
}

// MARK: Settings › Styles

struct StylesPane: View {
    var app: AppModel?
    var preview = false
    @AppStorage(SharedSettings.stylesFolderKey, store: SharedSettings.defaults) private var folder = SharedSettings.defaultStylesFolder
    @State private var styles: [Style] = []
    @State private var editing: StyleDraft?

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Your styles", note: AnyView(SettingsNote("A style is how your videos look, sound and move: exact values, a guide in words, and the parts the editor reuses, like titles, captions, transitions and sounds. Pick one in a film\u{2019}s brief. Make one with the editor from the brief, or write one here."))) {
                if styles.isEmpty {
                    SettingsRow(label: "No styles yet", detail: "Make one with the editor from a film\u{2019}s brief, or start one here.", first: true) {
                        Button("New Style\u{2026}") { editing = .new }.buttonStyle(.gate)
                    }
                }
                ForEach(Array(styles.enumerated()), id: \.element.id) { i, s in
                    SettingsRow(label: s.name, detail: [s.summary, s.contents.line].filter { !$0.isEmpty }.joined(separator: "\n"), first: i == 0, minHeight: 56) {
                        Button("Edit\u{2026}") { editing = .init(s) }.buttonStyle(.gate)
                        Button { reveal(s.url) } label: { Image(systemName: "folder") }.buttonStyle(.gate(.normal, .regular, icon: true)).help("Show in Finder")
                    }
                }
            }
            if !styles.isEmpty {
                HStack { Spacer(); Button("New Style\u{2026}") { editing = .new }.buttonStyle(.gate) }.padding(.top, 2)
            }
            SettingsGroup(label: "Where they live") {
                SettingsRow(label: "Styles folder", detail: "One folder for each style. Copy one to share it; drop one in to use it.", first: true) {
                    Text(displayPath).font(.system(size: 12)).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 10).frame(width: 230, height: Gate.Size.control, alignment: .leading).background(GateFieldBackground()).help(expanded)
                    Button("Change\u{2026}") { choose() }.buttonStyle(.gate)
                    Button("Show in Finder") { revealFolder() }.buttonStyle(.gate)
                }
            }
        }
        .task(id: folder) { load() }
        .sheet(item: $editing, onDismiss: load) { StyleEditSheet(draft: $0, folder: stylesURL) { editing = nil } }
    }

    private var expanded: String { NSString(string: folder.isEmpty ? SharedSettings.defaultStylesFolder : folder).expandingTildeInPath }
    private var displayPath: String { preview ? "~/Movies/Direction/Styles" : (expanded as NSString).abbreviatingWithTildeInPath }
    private var stylesURL: URL { preview ? StyleSamples.folder : SharedSettings.stylesFolder }
    private func load() { styles = preview ? StyleSamples.styles : StyleLibrary.list(in: SharedSettings.stylesFolder) }

    private func choose() {
        guard !preview else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a styles folder"; panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: expanded)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
    }
    private func revealFolder() {
        guard !preview else { return }
        let url = SharedSettings.stylesFolder
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    private func reveal(_ url: URL) { if !preview { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
}

/// A style being written in Settings: a new one, or one of yours.
struct StyleDraft: Identifiable {
    var id: String
    var style: Style?
    var name = "", summary = "", guide = ""
    static var new: StyleDraft { .init(id: "new-" + UUID().uuidString, style: nil, guide: StyleLibrary.template(name: "New style", summary: "")) }
    init(id: String, style: Style?, name: String = "", summary: String = "", guide: String = "") { self.id = id; self.style = style; self.name = name; self.summary = summary; self.guide = guide }
    init(_ s: Style) { self.init(id: s.id, style: s, name: s.name, summary: s.summary, guide: s.guide) }
}

/// Name, one sentence and the guide; the parts are files, so they're shown and opened in Finder.
struct StyleEditSheet: View {
    @State var draft: StyleDraft
    var folder: URL
    var close: () -> Void
    @State private var error: String?
    @State private var confirmingTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(draft.style == nil ? "New style" : draft.style!.name).font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
                field("Name") { TextField("", text: $draft.name).gateField(focused: false).startPlaceholder("Desk Talk", shown: draft.name.isEmpty) }
                field("In a sentence") { TextField("", text: $draft.summary).gateField(focused: false).startPlaceholder("Quick explainers: 3-second shots, punch-ins, bold captions.", shown: draft.summary.isEmpty) }
                field("The guide", detail: "How to cut in this style, in words: one section for each thing an editor decides.") {
                    TextEditor(text: $draft.guide)
                        .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Gate.Text.primary).scrollContentBackground(.hidden)
                        .padding(8).frame(height: 300).background(GateFieldBackground())
                }
                if let s = draft.style {
                    Text(s.contents.line.isEmpty ? "Words only. Graphics, transitions, sounds, fonts and a look go in its folder." : s.contents.line)
                        .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                }
                if let error { Text(error).font(Gate.Font.small).foregroundStyle(Gate.State.alert) }
            }
            .padding(20)
            HStack(spacing: 8) {
                if let s = draft.style {
                    Button("Move to Trash\u{2026}") { confirmingTrash = true }.buttonStyle(.gate(.ghostDanger))
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([s.url]) }.buttonStyle(.gate(.ghost))
                }
                Spacer()
                Button("Cancel", action: close).buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button(draft.style == nil ? "Make Style" : "Save", action: save).buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { SystemHairline() }
        }
        .frame(width: 620)
        .background(Gate.Surface.ground)
        .preferredColorScheme(.dark)
        .confirmationDialog("Move \u{201C}\(draft.name)\u{201D} to the Trash?", isPresented: $confirmingTrash) {
            Button("Move to Trash", role: .destructive, action: trash)
        } message: { Text("Films that use it keep their own copy.") }
    }

    private func field<Content: View>(_ label: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                if let detail { Text(detail).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary) }
            }
            content()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // A new style's guide starts under a placeholder heading; it takes the style's name.
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            let guide = draft.style == nil && draft.guide.hasPrefix("# New style\n") ? "# \(name)\n" + draft.guide.dropFirst("# New style\n".count) : draft.guide
            _ = try StyleLibrary.save(id: draft.style?.id, name: name, summary: draft.summary, tokens: nil, guide: guide, in: folder)
            close()
        } catch let e as DirectionError { error = e.message } catch { self.error = error.localizedDescription }
    }

    private func trash() {
        guard let s = draft.style else { return }
        do { try FileManager.default.trashItem(at: s.url, resultingItemURL: nil); close() } catch { self.error = "Couldn\u{2019}t move it to the Trash: \(error.localizedDescription)" }
    }
}
