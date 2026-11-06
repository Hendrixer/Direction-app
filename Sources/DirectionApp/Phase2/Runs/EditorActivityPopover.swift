import SwiftUI
import DirectionCore

/// Frame 57: what the editor is doing, newest first, what it has spent, Pause and Stop.
/// Shown from the pill while a run Direction started is working or paused.
struct EditorActivityPopover: View {
    @Bindable var model: FilmModel
    var run: EditorRun
    /// Snapshots fix the clock so "12 s" reads the same every time; otherwise it ticks every second, so a long
    /// step reads as still going rather than frozen.
    var now: Date? = nil
    private var runs: EditorRunsModel { model.runs }
    private var paused: Bool { run.state == .paused }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now ?? context.date)
        }
        .frame(width: 320)
        .background(Gate.Surface.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor")
    }

    // MARK: Head

    /// "Cutting Cut 4", "Building the assembly", "Logging footage", "Finishing Launch film".
    private var title: String {
        switch run.job {
        case .turnover: "Cutting \(model.nextCutName)"
        case .assemble: "Building the assembly"
        case .logFootage: "Logging footage"
        case .finish: "Finishing \(model.filmName)"
        case .style: "Making a style"
        case .technique: "Learning a technique"
        case .script: "Writing the picture"
        case .breakdown: "Breaking down the script"
        }
    }

    private func content(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            head(now)
            list(now)
            controls
            footer
        }
    }

    private func head(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                GemMark(size: 8, color: paused ? Gate.Text.disabled : nil)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).cssLineHeight(1.45, size: 13)
                Spacer(minLength: 8)
                if paused { Chip("Paused", icon: "pause.fill") }
            }
            Text(runs.programLine(run, now: now)).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.45, size: 11.5).padding(.leading, 19)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Activity

    private var rows: [EditorActivity] { runs.activity(of: run) }

    /// The step it's on now, while it works.
    private var working: Bool { !paused && run.state.isActive }

    @ViewBuilder private func list(_ now: Date) -> some View {
        let all = rows, shown = runs.showsAllActivity ? all : Array(all.prefix(6))
        VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty {
                Text(paused ? "Nothing yet. Resume to pick up where it stopped." : "Starting\u{2026}").font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary).frame(height: 30).padding(.horizontal, 8)
            } else if runs.showsAllActivity {
                ScrollView { rowStack(shown, now: now) }.frame(maxHeight: 300)
            } else {
                rowStack(shown, now: now)
            }
            // One step for a long time: say so, plainly, with what to do.
            if working, let current = all.first, now.timeIntervalSince1970 - current.at >= Self.longStep {
                Text("This step has taken \(Self.ago(current.at, now: now)). If nothing moves in a few minutes, Stop and turn over again.")
                    .font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).lineHeight(11.5, 1.45)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            }
            if all.count > 6 && !runs.showsAllActivity {
                Button("Show all") { runs.showsAllActivity = true }.buttonStyle(.gate(.ghost, .small)).padding(.leading, 2).padding(.top, 2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .overlay(alignment: .top) { SystemHairline() }
        .accessibilityElement(children: .contain).accessibilityLabel("What the editor did")
    }

    private func rowStack(_ shown: [EditorActivity], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in
                ActivityRow(activity: a, now: i == 0 && working, ago: Self.ago(a.at, now: now), suffix: suffix(a))
            }
        }
    }
    /// Ten minutes on one step is longer than any step should take.
    static let longStep: Double = 600

    /// "you said OK" after a read-back the director approved.
    private func suffix(_ a: EditorActivity) -> String? {
        guard a.verb == "Reading back", let t = model.turnovers.first(where: { $0.id == (a.turnoverID ?? run.turnoverID) }), t.readBackApproved else { return nil }
        return t.adjustments.isEmpty ? "you said OK" : "you adjusted \(t.adjustments.count)"
    }

    /// "now", "12 s", "1 min", "2 h".
    static func ago(_ t: Double, now: Date) -> String {
        let s = max(0, now.timeIntervalSince1970 - t)
        if s < 5 { return "now" }
        if s < 60 { return "\(Int(s)) s" }
        if s < 3600 { return "\(Int(s / 60)) min" }
        return "\(Int(s / 3600)) h"
    }

    // MARK: Spend and control

    private var controls: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Plan sign-ins often report no cost: then nothing is shown (open-questions.md).
            if let spend = run.spend, spend > 0 {
                HStack {
                    Text("Spent so far").font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary)
                    Spacer()
                    Text(String(format: "$%.2f", spend)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.Text.primary)
                }
                .frame(height: 22)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 6) {
                Spacer()
                if paused {
                    Button { model.setEditorPaused(false) } label: { Label("Resume", systemImage: "play.fill") }.buttonStyle(.gate)
                } else {
                    Button { model.setEditorPaused(true) } label: { Label("Pause", systemImage: "pause.fill") }.buttonStyle(.gate)
                }
                Button { model.showEditorPopover = false; runs.confirmStop(model) } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.gate(.ghostDanger))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .overlay(alignment: .top) { SystemHairline() }
    }

    private var footer: some View {
        HStack {
            OpenSettingsButton(tab: .engines) { Label("Editor settings\u{2026}", systemImage: "gearshape") }
                .buttonStyle(.gate(.ghost, .small))
                .simultaneousGesture(TapGesture().onEnded { model.showEditorPopover = false })
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .overlay(alignment: .top) { SystemHairline() }
    }
}

/// One row: time-ago in SF Mono 11 text-4, the verb in text-1, the object in text-2. The row the
/// editor is on now has a 1 pt prism edge that shimmers like the pill.
struct ActivityRow: View {
    var activity: EditorActivity
    var now: Bool
    var ago: String
    var suffix: String?
    @Environment(\.motionHeld) private var held

    var body: some View {
        let a = activity
        let verb = now ? a.verb : EditorActivityWords.past(a.verb)
        let rest = [a.detail, suffix].compactMap { $0 }
        HStack(spacing: 8) {
            // The step it's on: a spinner, and how long it's been on it once that's a while.
            Group {
                if now { HStack(spacing: 4) { GateSpinner().scaleEffect(0.75).frame(width: 11, height: 11); if ago != "now" { Text(ago) } } }
                else { Text(ago) }
            }
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled).frame(width: 52, alignment: .leading)
            let tail = rest.isEmpty ? "" : " \u{00B7} " + rest.joined(separator: " \u{00B7} ")
            Text("\(Text(verb).foregroundColor(Gate.Text.primary).fontWeight(.medium)) \(Text(a.object).font(a.mono ? .system(size: 11.5, design: .monospaced) : .system(size: 12.5)))\(Text(tail))")
                .font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, now ? 7 : 8).frame(height: 30)
        .background {
            if now {
                RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.panel)
                    .overlay(RowShimmer(held: held))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(now ? (ago == "now" ? "Now" : "Now, for \(ago)") : ago + " ago"): \(verb) \(a.object)\(rest.isEmpty ? "" : ", " + rest.joined(separator: ", "))")
    }
}

/// The now row's 1 pt prism edge. Static under Reduce Motion and during playback.
private struct RowShimmer: View {
    var held: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        if held || SettingsKey.reducesMotion { shape.strokeBorder(Gate.Voice.prism, lineWidth: 1) }
        else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Gate.Motion.shimmerPeriod) / Gate.Motion.shimmerPeriod
                shape.strokeBorder(AngularGradient(colors: Gate.Voice.prismStops + [Gate.Voice.prismStops[0]], center: .center, angle: .degrees(t * 360)), lineWidth: 1)
            }
        }
    }
}

/// Finished acts read in the past tense ("Reframed", "Read back"); looking and listening stay as they are.
enum EditorActivityWords {
    static let past: [String: String] = [
        "Adding": "Added", "Placing": "Placed", "Trimming": "Trimmed", "Removing": "Removed", "Moving": "Moved", "Splitting": "Split", "Rolling": "Rolled",
        "Slipping": "Slipped", "Sliding": "Slid", "Overlapping": "Overlapped", "Swapping": "Swapped", "Cutting": "Cut", "Tightening": "Tightened",
        "Retiming": "Retimed", "Holding": "Held", "Reframing": "Reframed", "Balancing": "Balanced", "Matching": "Matched", "Adjusting": "Adjusted",
        "Mixing": "Mixed", "Fading": "Faded", "Ducking": "Ducked", "Changing": "Changed", "Copying": "Copied", "Titling": "Titled", "Renaming": "Renamed",
        "Making": "Made", "Drawing": "Drew", "Asking": "Asked", "Delivering": "Delivered", "Logging": "Logged", "Finishing": "Finished",
        "Bringing": "Brought", "Exporting": "Exported", "Saving": "Saved", "Restoring": "Restored", "Answering": "Answered", "Writing": "Wrote",
        "Running": "Ran", "Inserting": "Inserted", "Editing": "Edited",
    ]
    static func past(_ verb: String) -> String {
        if verb == "Reading back" { return "Read back" }
        guard let first = verb.split(separator: " ").first.map(String.init), let p = past[first] else { return verb }
        return p + verb.dropFirst(first.count)
    }
}
