import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DirectionCore

/// The director's prep actions (specs/script.md, specs/breakdown.md). Every write goes through the store, so
/// the editor sees exactly what the director did.
extension FilmModel {
    static let scriptTypes: [UTType] = ["md", "markdown", "txt", "fountain", "fdx", "pdf"].compactMap { UTType(filenameExtension: $0) } + [.plainText, .pdf]

    func chooseScript() {
        let panel = NSOpenPanel(); panel.title = script == nil ? "Bring in a script" : "Bring in a new draft"; panel.allowedContentTypes = Self.scriptTypes; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bringScript(url)
    }

    /// A script file: the first one starts the A/V script, a later one is a new draft of it.
    func bringScript(_ url: URL) {
        guard let store else { return }
        let draft = script != nil
        do { _ = try store.importScript(try ScriptFile.text(url), fileName: url.lastPathComponent, path: url.path) }
        catch { self.error = error.localizedDescription; return }
        refresh(force: true)
        go(.script)
        toast = Toast(title: draft ? "New draft brought in" : "Script brought in", detail: draft ? "Rows whose words didn\u{2019}t change keep their picture." : "The editor writes what we see under every line.", editor: !draft)
    }

    // MARK: Script

    func editPicture(_ rowID: String, _ text: String) { perform { _ = try $0.editRow(rowID, picture: text) } }
    func editSound(_ rowID: String, _ text: String) { perform { _ = try $0.editRow(rowID, sound: text) } }
    func setPictureSize(_ rowID: String, _ size: ShotSize?) { perform { _ = try $0.editRow(rowID, size: .some(size)) } }
    func addRow(after rowID: String?) { perform { _ = try $0.addRow(after: rowID) } }
    func removeRow(_ rowID: String) { perform { _ = try $0.removeRow(rowID) } }
    /// ⌥↑ and ⌥↓: one row up or down.
    func moveRow(_ rowID: String, by step: Int) {
        guard let rows = script?.rows, let i = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let to = i + step
        guard rows.indices.contains(to) else { return }
        perform { _ = try $0.moveRow(rowID, before: step < 0 ? rows[to].id : (to + 1 < rows.count ? rows[to + 1].id : nil)) }
    }
    func addScriptNote(rows: [String], kind: NoteKind?, text: String) { perform { _ = try $0.addScriptNote(rowIDs: rows, kind: kind, text: text) } }
    func dropScriptNote(_ id: String) { perform { _ = try $0.editScriptNote(id, text: nil, drop: true) } }
    func answerRow(_ rowID: String, choice: String?, text: String? = nil) { perform { _ = try $0.answerRowQuestion(rowID, choiceID: choice, text: text) } }
    func turnOverScriptNotes() { perform { _ = try $0.turnOverScriptNotes() } }
    func okScript() { perform { _ = try $0.okScript() } }

    /// The film's style by name, for the Script room's outline.
    var styleName: String? { brief.style.flatMap { id in StyleNames.name(id) } }

    /// The editor is writing the picture now.
    var writingPicture: Bool { runs.active?.job == .script }
    /// A picture pass is waiting for the director's Start (Start work: Ask me first).
    var pictureHeld: Bool { runs.held?.job == .script }
    var breakingDown: Bool { runs.active?.job == .breakdown }

    var scriptPrimary: PrimaryAction? {
        guard let s = script else { return PrimaryAction(title: "Bring in a script\u{2026}", icon: "doc.text", help: "Choose the script to start from (\u{2318}\u{21A9})") { self.chooseScript() } }
        let written = s.openNotes.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if written > 0 { return PrimaryAction(title: "Turn over", icon: "arrow.right", count: "\(written)", help: "Send your notes on the script to the editor (\u{2318}\u{21A9})") { self.turnOverScriptNotes() } }
        if s.isOK { return PrimaryAction(title: "Open Breakdown", icon: "list.bullet.rectangle", help: "The breakdown of the script you OK\u{2019}d (\u{2318}\u{21A9})") { self.go(.breakdown) } }
        let empty = s.rows.filter { $0.picture.isEmpty }.count
        return PrimaryAction(title: "OK script", icon: "checkmark", enabled: empty == 0 && s.openQuestions.isEmpty && !writingPicture && !pictureHeld,
                             help: empty > 0 ? "\(empty == 1 ? "1 row has" : "\(empty) rows have") no picture yet" : !s.openQuestions.isEmpty ? "The editor has a question" : "Ready to break down (\u{2318}\u{21A9})") { self.okScript() }
    }

    // MARK: Breakdown

    var shotCoverage: [String: ShotCoverage] { breakdown.map { ProjectStore.coverage($0, dailies: dailies) } ?? [:] }

    func editShot(_ id: String, what: String? = nil, size: ShotSize?? = nil, move: ShotMove?? = nil, source: ShotSource? = nil) { perform { _ = try $0.editShot(id, what: what, size: size, move: move, source: source) } }
    func decideMissing(_ shotID: String, _ choice: MissingChoice?) { perform { _ = try $0.decideMissing(shotID: shotID, choice) } }
    func addShotNote(shots: [String], kind: NoteKind?, text: String) { perform { _ = try $0.addBreakdownNote(shotIDs: shots, kind: kind, text: text) } }
    func dropShotNote(_ id: String) { perform { _ = try $0.editBreakdownNote(id, text: nil, drop: true) } }
    func answerShot(_ shotID: String, choice: String?, text: String? = nil) { perform { _ = try $0.answerShotQuestion(shotID, choiceID: choice, text: text) } }
    func turnOverBreakdownNotes() { perform { _ = try $0.turnOverBreakdownNotes() } }
    func okBreakdown() { perform { _ = try $0.okBreakdown() } }

    /// Have it: footage the director already has, brought into the film and played as this shot.
    func attachFootage(_ shotID: String, url: URL) {
        Task { @MainActor in
            guard let store else { return }
            do {
                let before = Set((try store.read()).assets.map(\.id))
                importFootage([url], places: [:])
                // The file comes in as footage first; its asset is the new one with this path.
                for _ in 0..<40 {
                    if let asset = try store.read().assets.first(where: { !before.contains($0.id) && URL(fileURLWithPath: $0.path).standardizedFileURL == url.standardizedFileURL }) {
                        _ = try store.attachFootage(shotID: shotID, assetID: asset.id); refresh(force: true); return
                    }
                    try await Task.sleep(for: .milliseconds(250))
                }
                error = "Direction couldn\u{2019}t bring in \(url.lastPathComponent)."
            } catch { self.error = error.localizedDescription }
        }
    }
    func attachTake(_ shotID: String, assetID: String) { perform { _ = try $0.attachFootage(shotID: shotID, assetID: assetID) } }
    func chooseFootage(for shotID: String) {
        let panel = NSOpenPanel(); panel.title = "Choose the footage"; panel.allowedContentTypes = [.movie, .image, .audio]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attachFootage(shotID, url: url)
    }

    /// Update the breakdown after the script changed since it was made.
    func updateBreakdownFromScript() {
        if !runs.updateBreakdown(self) { toast = Toast(title: "The editor isn\u{2019}t set up", detail: "Choose who edits in Settings \u{203A} Engines, then try again.") }
    }

    var breakdownPrimary: PrimaryAction? {
        guard let b = breakdown else { return nil }
        let written = b.openNotes.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if written > 0 { return PrimaryAction(title: "Turn over", icon: "arrow.right", count: "\(written)", help: "Send your notes on the breakdown to the editor (\u{2318}\u{21A9})") { self.turnOverBreakdownNotes() } }
        if !b.isOK { return PrimaryAction(title: "OK breakdown", icon: "checkmark", enabled: !b.shots.isEmpty && !breakingDown, help: "Shot numbers become slates (\u{2318}\u{21A9})") { self.okBreakdown() } }
        let coverage = shotCoverage
        guard coverage.values.contains(where: \.isIn) else { return PrimaryAction(title: "Bring footage", icon: "square.and.arrow.down", help: "Bring footage after each day of shooting (\u{2318}\u{21A9})") { self.chooseFootage() } }
        if cuts.isEmpty { return PrimaryAction(title: "Assemble from circles", icon: "square.grid.2x2", enabled: circledCount > 0 && openTurnover == nil, help: circledCount == 0 ? "Circle takes in Dailies first" : "Build the assembly from your circled takes (\u{2318}\u{21A9})") { self.assembleFromCircles() } }
        return PrimaryAction(title: "Open Dailies", icon: "square.grid.2x2", help: "Your takes (\u{2318}\u{21A9})") { self.go(.dailies) }
    }

    // MARK: Shoot list

    /// The breakdown by setup, for the shoot (specs/breakdown.md › Shoot list).
    var shootList: String {
        guard let b = breakdown else { return "" }
        let coverage = shotCoverage
        var out = ["\(filmName) \u{00B7} Shoot list", ""]
        for setup in b.setups.sorted(by: { $0.number < $1.number }) {
            let shots = b.shots(in: setup.id).filter { ![.make, .have].contains($0.source) }
            guard !shots.isEmpty else { continue }
            out.append("\(setup.number)  \(setup.name.uppercased())\(setup.needs.map { "  \u{2014}  \($0)" } ?? "")")
            for s in shots {
                let done = coverage[s.id]?.isIn == true ? "\u{2713}" : "\u{2610}"
                let how = [s.size?.label, s.move?.label].compactMap { $0 }.joined(separator: " \u{00B7} ")
                out.append("  \(done) \(s.code)  \(s.what)\(how.isEmpty ? "" : "  (\(how))")  \(Timecode.duration(s.seconds))")
            }
            out.append("")
        }
        out.append("Say the shot and take at the head of each take: \u{201C}2C, take one.\u{201D}")
        return out.joined(separator: "\n")
    }

    func printShootList() {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 720))
        view.string = shootList
        view.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit; info.isVerticallyCentered = false
        NSPrintOperation(view: view, printInfo: info).run()
    }
}

/// Text from a script file of any kind Direction reads: Markdown, plain text, Fountain, Final Draft, PDF.
enum ScriptFile {
    static func text(_ url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let s = PDFText.string(url), !s.isEmpty else { throw DirectionError("script_unreadable", "\(url.lastPathComponent) has no text Direction can read.") }
            return s
        case "fdx":
            return try FinalDraft.fountain(Data(contentsOf: url))
        default:
            guard let s = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { throw DirectionError("script_unreadable", "Direction can\u{2019}t read \(url.lastPathComponent).") }
            return s
        }
    }
}

/// Style names by id, read from the Styles folder once.
@MainActor enum StyleNames {
    private static var names: [String: String] = [:]
    static func name(_ id: String) -> String? {
        if names[id] == nil { for s in StyleLibrary.list(in: SharedSettings.stylesFolder) { names[s.id] = s.name } }
        return names[id] ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
