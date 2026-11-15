import SwiftUI
import AppKit
import DirectionCore

// A voice-over written to the cut (specs/script.md › A voice-over): the director says what it should say, the
// editor watches the cut and writes the words to record, line by line, in the Script room.
extension FilmModel {
    /// A voice-over can be written once there's something to write it to: a cut, or footage.
    var canWriteVoiceOver: Bool { !cuts.isEmpty || hasFootage }

    /// Starts one: the ask, and the cut on screen when `watchCut`. A film with a script asks before it's replaced.
    func writeVoiceOver(ask: String, watchCut: Bool) {
        guard let store, VoiceOverAsk.validAsk(ask) else { return }
        let cut = watchCut ? (watchedCut ?? latestCut) : nil
        let asked = VoiceOverAsk(ask: ask, cutID: cut?.id, cutName: cut?.name, cutRevision: cut?.editRevision, cutSeconds: cut.flatMap { cutDuration($0) })
        var replace = false
        if let s = script, !s.rows.isEmpty {
            let alert = NSAlert()
            alert.messageText = s.isVoiceOver ? "Write the voice-over again?" : "Write a voice-over in place of the script?"
            alert.informativeText = s.isVoiceOver
                ? "The lines written so far and the notes on them go, and the editor starts again from what you asked."
                : "The film has one script at a time. The \(s.isStory ? "story" : "script") and its pictures go\(breakdown != nil ? ", with the breakdown" : ""), and the editor writes the voice-over instead."
            alert.addButton(withTitle: "Write the Voice-Over"); alert.addButton(withTitle: "Cancel")
            guard isPreview || alert.runModal() == .alertFirstButtonReturn else { return }
            replace = true
        }
        do { _ = try store.startVoiceOver(asked, replace: replace) } catch { self.error = error.localizedDescription; return }
        // Only once the new ask is in: whatever pass was on the old script or the old ask stops, so the next one
        // starts from this ask (a pass still watching, with no lines yet, would write to the old one).
        runs.stopPrep(.voiceOver, film: self); runs.stopPrep(.script, film: self); runs.stopPrep(.breakdown, film: self)
        go(.script, force: true)
        refresh(force: true)
        toast = Toast(title: "Writing a voice-over", detail: cut.map { "The editor watches \($0.name), then writes the words line by line." } ?? "The editor reads the footage, then writes the words line by line.", editor: true)
    }

    /// Copy for Recording: the lines with where each starts, to read from.
    func copyVoiceOverForRecording() {
        guard let s = script, s.isVoiceOver, !s.rows.isEmpty else { return }
        SystemSupport.copy(s.forRecording)
        toast = Toast(title: "Copied the voice-over", detail: "\(s.rows.count == 1 ? "1 line" : "\(s.rows.count) lines"), about \(Timecode.duration(s.seconds)) read aloud.")
    }
}

/// Write a Voice-Over…: what it should say, and whether the editor watches the cut first.
struct VoiceOverSheet: View {
    @Bindable var model: FilmModel
    @State private var ask: String
    @State private var watchCut = true
    /// Snapshots: the sheet with something asked.
    init(model: FilmModel, ask: String = "") { self.model = model; _ask = State(initialValue: ask) }

    private var cut: ReviewCut? { model.watchedCut ?? model.latestCut }
    private var ready: Bool { VoiceOverAsk.validAsk(ask) }
    /// "Cut 10 runs 0:40: about 80 words."
    private var fits: String? {
        guard watchCut, let cut, let seconds = model.cutDuration(cut), let words = VoiceOverAsk(ask: "", cutSeconds: seconds).wordsThatFit else { return nil }
        return "\(cut.name) runs \(Timecode.duration(seconds)): about \(words) words, with room for the picture to breathe."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Write a voice-over").font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
                Text("The editor writes the words for you to record later, line by line, each timed to the picture under it. You change any line, or leave notes, in the Script room.")
                    .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("What should it say?").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                    GateTextArea(text: $ask, placeholder: "Why these bodies look the way they do, for someone who\u{2019}s never been to the exhibit. Curious, a little funny, never gross.", minHeight: 84)
                    if ask.count > VoiceOverAsk.longest { Text("Up to 4,000 characters.").font(Gate.Font.caption).foregroundStyle(Gate.State.alert) }
                }
                if let cut {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Watch \(cut.name) first", isOn: $watchCut).toggleStyle(.checkbox).font(Gate.Font.small)
                        Text(fits ?? "Without it, the editor writes from your footage.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { model.sheet = nil }.buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button("Write It") {
                    let words = ask.trimmingCharacters(in: .whitespacesAndNewlines), watch = watchCut && cut != nil
                    model.sheet = nil
                    model.writeVoiceOver(ask: words, watchCut: watch)
                }
                .buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command).disabled(!ready)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { SystemHairline() }
        }
        .frame(width: 520)
        .background(Gate.Surface.ground)
        .preferredColorScheme(.dark)
    }
}
