import SwiftUI
import AppKit
import DirectionCore

// Owner: Changes and Finish agent. Frames 34–38. After picture lock: the finishing checklist (36),
// delivery progress, and the delivered files (38). Nothing in Finish can move a frame.

struct FinishRoom: View {
    @Bindable var model: FilmModel
    @State private var selectedItem: String?
    @FocusState private var focused: Bool

    private var showsDelivered: Bool { !model.deliveredFiles.isEmpty && !model.delivery.showChecklist && !model.delivery.isRunning }

    var body: some View {
        HStack(spacing: 0) {
            FilmStage(model: model, marks: [], showsMarkButton: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Group {
                if showsDelivered { DeliveredPanel(model: model) }
                else { FinishingPanel(model: model, selected: $selectedItem) }
            }
            .frame(width: 560)
            .frame(maxHeight: .infinity)
            .background(Gate.Surface.ground)
            .hairlineBorder(.leading)
        }
        .background {
            Button("Deliver") { if !model.delivery.isRunning { model.sheet = .deliver } }
                .keyboardShortcut("d", modifiers: .command)
                .buttonStyle(.plain).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.space) { guard !TextInput.hasFocus else { return .ignored }; model.togglePlayback(); return .handled }
        .onAppear { focused = true }
    }
}

extension FilmModel {
    /// Deliver… on the checklist; Show in Finder once the files exist.
    var finishPrimary: PrimaryAction? {
        let d = delivery
        if !deliveredFiles.isEmpty && !d.showChecklist && !d.isRunning {
            return PrimaryAction(title: "Show in Finder", icon: "folder") { self.revealDelivered() }
        }
        return PrimaryAction(title: d.isRunning ? "Delivering\u{2026}" : "Deliver\u{2026}", icon: "square.and.arrow.up", enabled: !d.isRunning) { self.sheet = .deliver }
    }
    func revealDelivered() {
        let urls = deliveredFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty, let folder = deliveredFiles.first?.deletingLastPathComponent() { NSWorkspace.shared.open(folder) }
        else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
    var finishingItems: [FinishingItem] { directing.finishing ?? FinishingItem.defaults }
    /// Director-owned items are signed off here; the editor's own items only report.
    func updateFinishingItem(_ item: FinishingItem) {
        if isPreview {
            var items = finishingItems
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
            directing.finishing = items
            return
        }
        perform { _ = try $0.updateFinishing([item]) }
    }
}

// MARK: Checklist (36)

struct FinishingPanel: View {
    @Bindable var model: FilmModel
    @Binding var selected: String?

    private var items: [FinishingItem] { model.finishingItems }
    private var done: Int { items.filter { $0.state == "done" }.count }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Finishing \(model.cutName(model.directing.pictureLockedCutID ?? model.latestCut?.id))").font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary)
                    Spacer()
                    Text("\(done) of \(items.count) done").font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.Text.tertiary)
                }
                GateProgress(value: items.isEmpty ? 0 : Double(done) / Double(items.count)).padding(.top, 2)
                    .animation(gateAnimation(Gate.Motion.settle), value: done)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            .hairlineBorder(.bottom)
            ScrollView {
                VStack(spacing: 0) {
                    if !model.delivery.items.isEmpty && (model.delivery.isRunning || !model.delivery.failed.isEmpty) { DeliveryProgress(model: model) }
                    ForEach(items) { item in
                        FinishRow(model: model, item: item, selected: selected == item.id)
                            .onTapGesture { selected = item.id }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Finishing, \(done) of \(items.count) done")
            Text("The edit is locked. Finishing never moves a frame.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14).frame(minHeight: 44)
                .hairlineBorder(.top)
        }
    }
}

struct FinishRow: View {
    @Bindable var model: FilmModel
    let item: FinishingItem
    var selected: Bool
    @State private var acting = false

    private var editor: Bool { item.by.contains("editor") }
    private var director: Bool { item.by.contains("you") }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.secondary)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
                    .frame(width: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                        if editor { who("Editor", agent: true) }
                        if director { who("You", agent: false) }
                    }
                    .fixedSize()
                    .frame(minHeight: 20)
                    // The title sits at the top of the icon's 32 pt row; the description starts under it.
                    .frame(height: 32, alignment: .top)
                    Text(item.detail).font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary).lineSpacing(3).padding(.bottom, 3).fixedSize(horizontal: false, vertical: true)
                    if item.state == "working", let p = item.progress {
                        HStack(spacing: 10) {
                            GateProgress(value: p, agent: editor).frame(maxWidth: 220)
                            Text("Working").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                        }
                        .padding(.top, 4)
                        .animation(gateAnimation(Gate.Motion.settle), value: p)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            right.fixedSize()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(selected ? Gate.Surface.panel : .clear)
        .hairlineBorder(.bottom)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title), \([editor ? "editor" : nil, director ? "you" : nil].compactMap { $0 }.joined(separator: " and ")), \(stateWord): \(item.detail)")
    }

    private var icon: String {
        switch item.id {
        case "color": "circle.lefthalf.filled"
        case "sound": "speaker.wave.2"
        case "captions": "captions.bubble"
        case "titles": "textformat"
        case "licenses": "waveform"
        case "deliver": "square.and.arrow.up.on.square"
        default: "checklist"
        }
    }

    private func who(_ text: String, agent: Bool) -> some View {
        HStack(spacing: 6) {
            if agent { GemMark(size: 5) } else { PinMark(size: 7) }
            Text(text.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(0.7)
        }
        .foregroundStyle(agent ? Gate.Voice.agent : Gate.Voice.director)
    }

    private var stateWord: String {
        switch item.state { case "done": "done"; case "working": "editor working"; case "needsYou": "needs you"; case "blocked": "problem"; default: "to do" }
    }

    @ViewBuilder private var right: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if item.id == "deliver" {
                deliverStatus
            } else {
                switch item.state {
                case "done":
                    Label("Done", systemImage: "checkmark").labelStyle(StatusOKLabelStyle())
                    if editor && !director { Button("Review") { model.seek(0); if !model.playing { model.togglePlayback() } }.buttonStyle(.gate(.normal, .small)).help("Watch the film with \(item.title.lowercased()) applied") }
                case "working":
                    Text(item.progress.map { "\(Int(($0 * 100).rounded()))%" } ?? "Working").font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.Text.tertiary)
                case "needsYou":
                    Chip("Needs you", mono: false)
                    action
                case "blocked":
                    Chip(item.id == "licenses" ? "Missing" : "Problem", style: .bad)
                    action
                default:
                    action
                }
            }
        }
    }

    @ViewBuilder private var deliverStatus: some View {
        let d = model.delivery
        if d.isRunning {
            HStack(spacing: 6) { GateSpinner(); Text("Delivering \(min(d.items.count, d.doneCount + 1)) of \(d.items.count)") }.font(Gate.Font.small).foregroundStyle(Gate.Text.secondary)
        } else if item.state == "done" || !model.deliveredFiles.isEmpty {
            Label("Done", systemImage: "checkmark").labelStyle(StatusOKLabelStyle())
            Button("Show files") { model.delivery.showChecklist = false }.buttonStyle(.gate(.normal, .small))
        } else {
            let n = DeliveryOutput.all.filter(\.defaultOn).count
            Text("\(n) outputs").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
        }
    }

    @ViewBuilder private var action: some View {
        if director {
            Button { acting = true } label: {
                switch item.id {
                case "titles": SmallIconLabel("Write credits", icon: "plus")
                case "licenses": Text("Add license\u{2026}")
                case "captions": Text("Check names")
                default: Text("Sign off\u{2026}")
                }
            }
            .buttonStyle(.gate(.normal, .small))
            .popover(isPresented: $acting, arrowEdge: .bottom) { FinishItemPopover(model: model, item: item) { acting = false } }
        }
    }
}

/// The director's side of a finishing item: write, attach, or sign off. Never touches timing.
struct FinishItemPopover: View {
    var model: FilmModel
    let item: FinishingItem
    var close: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            Text(item.detail).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            if item.id == "titles" {
                GateTextArea(text: $text, placeholder: "Credits, one per line", minHeight: 96)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: close).buttonStyle(.gate(.ghost)).keyboardShortcut(.cancelAction)
                switch item.id {
                case "licenses":
                    Button("Choose License\u{2026}") { chooseLicense() }.buttonStyle(.gate(.normal)).keyboardShortcut(.defaultAction)
                case "titles":
                    Button("Save Credits") { save(detail: "Credits written: " + text.split(separator: "\n").map(String.init).joined(separator: " \u{00B7} ")) }
                        .buttonStyle(.gate(.normal)).keyboardShortcut(.defaultAction).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                case "captions":
                    Button("Names Are Right") { save(detail: item.detail + " Names checked.") }.buttonStyle(.gate(.normal)).keyboardShortcut(.defaultAction)
                default:
                    Button("Mark Done") { save(detail: item.detail) }.buttonStyle(.gate(.normal)).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func save(detail: String) {
        var updated = item
        updated.state = "done"; updated.detail = detail; updated.progress = nil
        model.updateFinishingItem(updated)
        close()
    }
    private func chooseLicense() {
        let panel = NSOpenPanel(); panel.title = "Add a license"; panel.prompt = "Add"; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(detail: item.detail + " License on file: \(url.lastPathComponent).")
    }
}

/// Per-file progress while a delivery runs in the background, and anything that failed.
struct DeliveryProgress: View {
    @Bindable var model: FilmModel
    var body: some View {
        let d = model.delivery
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(d.isRunning ? "Delivering \(min(d.items.count, d.doneCount + 1)) of \(d.items.count)" : "\(d.doneCount) of \(d.items.count) delivered")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                Spacer()
                if d.isRunning { Button("Stop") { d.cancel() }.buttonStyle(.gate(.ghost, .small)).help("Stop after the current file") }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
            ForEach(d.items) { item in
                HStack(spacing: 10) {
                    Group {
                        switch item.state {
                        case .queued: Image(systemName: "circle.dashed").foregroundStyle(Gate.Text.disabled)
                        case .writing: GateSpinner()
                        case .done: Image(systemName: "checkmark").foregroundStyle(Gate.State.approve)
                        case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(Gate.State.alert)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold)).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.url.lastPathComponent).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                        if case .failed(let why) = item.state { Text(why).font(Gate.Font.small).foregroundStyle(Gate.State.alert).lineLimit(2) }
                        else { Text(item.state == .writing ? "Writing\u{2026}" : item.state == .done ? "Written" : "Waiting").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary) }
                    }
                    Spacer()
                    if case .failed = item.state, !d.isRunning { Button("Retry") { d.retry(model: model, item.id) }.buttonStyle(.gate(.normal, .small)) }
                }
                .padding(.horizontal, 18).padding(.vertical, 6)
            }
        }
        .padding(.bottom, 8)
        .background(Gate.Surface.panel)
        .hairlineBorder(.bottom)
        .accessibilityElement(children: .contain)
    }
}

// MARK: Delivered (38)

struct DeliveredPanel: View {
    @Bindable var model: FilmModel
    @State private var appeared = false

    private var files: [URL] { model.deliveredFiles }
    private var failed: [Delivery.Item] { model.delivery.failed }
    private var openItems: [FinishingItem] { model.finishingItems.filter { $0.id != "deliver" && $0.state != "done" } }

    var body: some View {
        VStack(spacing: 0) {
            hero
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element) { i, url in FileRow(model: model, url: url, index: i) }
                    ForEach(failed) { item in failedRow(item) }
                    if !openItems.isEmpty { openNotice.padding(.horizontal, 18).padding(.vertical, 16) }
                }
                .hairlineBorder(.top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Text("Delivered files live in \(files.first.map { DeliveryFormat.folderLabel($0.deletingLastPathComponent()) } ?? "the delivery folder").")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14).frame(minHeight: 44)
                .hairlineBorder(.top)
        }
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("Back to the Checklist") { model.delivery.showChecklist = true }
                Button("Deliver Again\u{2026}") { model.sheet = .deliver }
            } label: { Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.secondary).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("More").padding(12)
        }
        .onAppear {
            withAnimation(gateAnimation(Gate.Motion.settle)) { appeared = true }
            AccessibilityNotification.Announcement("\(title), \(files.count) files").post()
        }
    }

    private var title: String { failed.isEmpty ? "\(model.filmName) is delivered" : "\(files.count) of \(files.count + failed.count) delivered" }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Gate.State.approve)
                .frame(width: 48, height: 48).background(Circle().fill(Gate.State.approveWash))
                .scaleEffect(appeared || model.isPreview ? 1 : 0.9).opacity(appeared || model.isPreview ? 1 : 0)
            Text(title).font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary).multilineTextAlignment(.center)
            Text(meta).font(.system(size: 13)).foregroundStyle(Gate.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 26)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        let cut = model.cuts.first { $0.id == model.directing.pictureLockedCutID } ?? model.latestCut
        var parts = [cut?.name ?? "", model.cutDuration(cut).map(Timecode.duration) ?? Timecode.duration(model.duration), files.count == 1 ? "1 file" : "\(files.count) files"]
        if let at = model.directing.deliveredAt { parts.append(ChangesFormat.dayAndTime(at)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private func failedRow(_ item: Delivery.Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.State.alert).frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 7).fill(Gate.State.alertWash))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).lineLimit(1)
                if case .failed(let why) = item.state { Text(why).font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.State.alert).lineLimit(1) }
            }
            Spacer()
            Button("Retry") { model.delivery.retry(model: model, item.id) }.buttonStyle(.gate(.normal, .small))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .hairlineBorder(.top)
    }

    private var openNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.State.alert)
            Text("Still open: \(openItems.map { $0.title.lowercased() }.joined(separator: ", ")).").font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.card).fill(Gate.Surface.panel).overlay(RoundedRectangle(cornerRadius: Gate.Radius.card).strokeBorder(Gate.State.alert.opacity(0.45), lineWidth: 1)))
        .accessibilityElement(children: .combine)
    }
}

/// One delivered file: thumbnail, name, what it is and its real size. Drag it out; ⌘C copies its path.
struct FileRow: View {
    var model: FilmModel
    let url: URL
    let index: Int
    var body: some View {
        let output = DeliveryOutput.matching(url)
        HStack(spacing: 12) {
            Thumbnail(path: model.stripScenes.last?.thumbnail, art: output?.art ?? [.day, .room, .dusk, .night][index % 4])
                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.subtle, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                Text(sub(output)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.Text.tertiary).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { SmallIconLabel("Show", icon: "folder") }
                .buttonStyle(.gate(.ghost, .small)).help("Show in Finder").disabled(!exists)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .hairlineBorder(index == 0 ? [] : .top)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
        }
        .accessibilityElement(children: .combine)
    }
    private var exists: Bool { model.isPreview || FileManager.default.fileExists(atPath: url.path) }
    private func sub(_ o: DeliveryOutput?) -> String {
        let kind = o.map { $0.codec } ?? url.pathExtension.uppercased()
        if model.isPreview, let size = DeliveredPreview.sizes[url.lastPathComponent] { return "\(kind) \u{00B7} \(DeliveryFormat.bytes(size))" }
        guard let size = DeliveryFormat.fileSize(url) else { return "\(kind) \u{00B7} missing" }
        return "\(kind) \u{00B7} \(DeliveryFormat.bytes(size))"
    }
}

/// Snapshots can't write files; fixtures give the delivered files their sizes here.
@MainActor enum DeliveredPreview {
    static var sizes: [String: Int64] = [:]
}
