import SwiftUI
import DirectionCore

/// Frame 06: the editor builds the assembly from your circles and the brief.
/// Scenes fill in as it goes; its log says what it relied on. Nobody else sees the assembly first.
struct OnboardingAssemblyView: View {
    @Bindable var model: FilmModel
    @Environment(\.dailiesPreview) private var preview
    @State private var seen: [String] = []

    private var turnover: Turnover? { model.turnovers.last { $0.kind == "assembly" && $0.state != .cancelled } }

    var body: some View {
        ZStack {
            Gate.Surface.canvas
            EllipticalGradient(stops: [.init(color: Gate.Steel.ramp[2], location: 0), .init(color: Gate.Surface.canvas, location: 0.75)], center: UnitPoint(x: 0.5, y: 0.4), startRadiusFraction: 0, endRadiusFraction: 0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    // The promise sits with the title it explains, not off on its own below.
                    HStack(alignment: .top, spacing: 40) {
                        top.frame(maxWidth: .infinity, alignment: .leading)
                        promise.frame(width: 320)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    tiles
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(questions) { AssemblyQuestion(model: model, question: $0) }
                        logList
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(width: 980)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: 0)
                .containerRelativeFrame(.vertical, alignment: .center) { h, _ in h }
            }
            .scrollIndicators(.never)
        }
        .onAppear { remember(turnover?.message) }
        .onChange(of: turnover?.message) { _, m in remember(m) }
    }

    // MARK: Header

    private var top: some View {
        VStack(alignment: .leading, spacing: 12) {
            DailiesEditorLabel(text: failed ? "The editor stopped" : ready ? "Your first cut is ready" : "The editor is building your first cut")
            Text("Assembly").font(Gate.Font.brand(size: 48, width: 125, weight: 800)).foregroundStyle(Gate.Text.primary)
            Text(headline).font(.system(size: 15)).foregroundStyle(failed ? Gate.State.alert : Gate.Text.secondary)
            if ready {
                Button { model.go(.screening) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 11))
                        Text("Screen the assembly")
                        Text("\u{2318}\u{21A9}").font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.tertiary)
                    }
                }
                .buttonStyle(.gate(.normal, .large)).padding(.top, 8)
            }
        }
    }

    private var failed: Bool { turnover?.state == .failed }
    /// Delivered: the assembly is a cut now, waiting to be screened.
    private var ready: Bool { turnover?.state == .delivered && !model.cuts.isEmpty }

    private var headline: String {
        if failed { return turnover?.message?.split(separator: "\n").last.map(String.init) ?? "The assembly didn't finish." }
        if ready {
            let length = model.sequence.map { " It runs \(Timecode.duration($0.duration.seconds))." } ?? ""
            return "From your \(DailiesFormat.count(model.circledCount, "circled take")) and the brief.\(length) Watch it once all the way through."
        }
        var line = "From your \(DailiesFormat.count(model.circledCount, "circled take")) and the brief."
        if let t = turnover, let p = t.percent, p > 0.05, p < 1 {
            let minutes = Int(((Date().timeIntervalSince1970 - t.createdAt) * (1 - p) / p / 60).rounded())
            line += minutes <= 1 ? " Almost there." : " About \(minutes) minutes left."
        }
        return line
    }

    // MARK: Scenes

    private enum TileState { case done, live, pending }

    /// "Assembling 3 of 5" names the scene being cut; earlier ones are done. Without it, scenes with picture count as done.
    private var currentIndex: Int {
        if let phase = turnover?.phase, let m = phase.firstMatch(of: /(\d+) of (\d+)/), let n = Int(m.1) { return n - 1 }
        let placed = model.scenes.lastIndex { durationInCut($0) > 0 }
        return (placed ?? -1) + 1
    }

    private func state(_ i: Int) -> TileState {
        if ready { return durationInCut(model.scenes[i]) > 0 ? .done : .pending }
        return i < currentIndex ? .done : i == currentIndex && turnover?.state.isOpen == true ? .live : .pending
    }

    /// The scene's running time in the working sequence so far.
    private func durationInCut(_ scene: DailiesScene) -> Double {
        let seq = try? model.project?.sequence(turnover?.sequenceID)
        return (seq?.clips ?? []).filter { $0.kind == .video && $0.layer == 0 && model.dailies.takes[$0.assetID ?? ""]?.sceneID == scene.id }.reduce(0) { $0 + $1.duration.seconds }
    }

    private var tiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 5), alignment: .leading, spacing: 16) {
            ForEach(Array(model.scenes.enumerated()), id: \.element.id) { i, scene in tile(scene, state(i)) }
        }
    }

    private func tile(_ scene: DailiesScene, _ state: TileState) -> some View {
        let takes = model.dailiesTakes(inScene: scene.id)
        let still = takes.first(where: \.circled) ?? takes.first(where: { $0.suggestion != nil }) ?? takes.first
        let suggestionsOnly = !takes.contains(where: \.circled) && state != .pending
        return VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    if state != .pending, let still {
                        DailiesTakeThumb(asset: model.asset(still.assetID), art: preview.art[still.assetID] ?? FootageArt.forScene(scene.number), preview: model.isPreview)
                            .blur(radius: state == .live ? 10 : 0).drawingGroup().colorMultiply(state == .live ? Color(white: 0.6) : .white).opacity(state == .live ? 0.8 : 1)
                    } else { Gate.Surface.sunken }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if state == .live && failed { RoundedRectangle(cornerRadius: 6).strokeBorder(Gate.State.alert, lineWidth: 1) }
                    else if state == .live { AssemblyLiveEdge() }
                    else { RoundedRectangle(cornerRadius: 6).strokeBorder(Gate.Line.subtle, lineWidth: 1) }
                }
                .animation(gateAnimation(Gate.Motion.glide), value: state == .done)
            HStack(spacing: 6) {
                switch state {
                case .done: Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Gate.State.approve)
                case .live: if failed { Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(Gate.State.alert) } else { GateSpinner().frame(width: 11, height: 11) }
                case .pending: EmptyView()
                }
                if suggestionsOnly { GemMark(size: 6.4).help("Nothing circled here, so I used my suggestions") }
                Text(scene.label).lineLimit(1)
                Spacer(minLength: 4)
                if state == .done { Text(Timecode.duration(durationInCut(scene))).font(Gate.Font.mono).foregroundStyle(Gate.Text.disabled) }
                if state == .live && !failed { Text("\u{2026}").font(Gate.Font.mono).foregroundStyle(Gate.Text.disabled) }
            }
            .font(.system(size: 12))
            .foregroundStyle(state == .live ? Gate.Text.primary : state == .done ? Gate.Text.secondary : Gate.Text.disabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scene \(scene.number), \(scene.title), \(state == .done ? "done" : state == .live ? (failed ? "stopped" : "in progress") : "waiting")")
    }

    // MARK: Log and promise

    private var log: [String] { preview.assemblyLog.isEmpty ? seen : preview.assemblyLog }

    private func remember(_ message: String?) {
        for line in (message ?? "").split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty && !seen.contains(line) { seen.append(line) }
    }

    private var logList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if log.isEmpty { DailiesSayLine(text: ready ? "Done." : "Reading the brief and your circles.") }
            ForEach(Array(log.enumerated()), id: \.offset) { i, line in
                let now = i == log.count - 1 && !ready
                DailiesSayLine(text: line, color: now ? Gate.Text.primary : Gate.Text.secondary, steelDiamond: !now)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The editor's log")
    }

    private var questions: [EditorQuestion] { model.openQuestions.filter { $0.turnoverID == turnover?.id } }

    private var promise: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye").font(.system(size: 13))
                Text("First look is yours").font(Gate.Font.brand(size: 15, width: 112, weight: 700))
            }
            .foregroundStyle(Gate.Text.primary)
            Text("Nobody else can see the assembly until you've screened it. Share links stay off until then.")
            Text("It'll be rough on purpose. Watch it once all the way through before giving notes.")
        }
        .font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary).lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gatePanel(Gate.Radius.card, fill: Gate.Surface.ground)
        .accessibilityElement(children: .combine)
    }
}

/// The live tile's 1 pt prism border, sliding while the editor works. Static under Reduce Motion.
private struct AssemblyLiveEdge: View {
    var body: some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Gate.Voice.prism, lineWidth: 1)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Gate.Motion.shimmerPeriod) / Gate.Motion.shimmerPeriod
                RoundedRectangle(cornerRadius: 6).strokeBorder(AngularGradient(colors: Gate.Voice.prismStops + [Gate.Voice.prismStops[0]], center: .center, angle: .degrees(t * 360)), lineWidth: 1)
            }
        }
    }
}

/// A question the editor asks mid-assembly: the remaining scenes wait for it.
private struct AssemblyQuestion: View {
    var model: FilmModel
    var question: EditorQuestion
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DailiesSayLine(text: question.text, detail: question.detail)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(question.choices) { c in
                    Button { model.answer(question, choiceID: c.id, text: nil) } label: {
                        HStack(spacing: 10) {
                            if let id = c.assetID {
                                DailiesTakeThumb(asset: model.asset(id), art: model.dailiesArt(id), preview: model.isPreview).frame(width: 64, height: 36).clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Text(c.label).foregroundStyle(Gate.Text.primary)
                            if let d = c.detail { Text(d).foregroundStyle(Gate.Text.tertiary) }
                            Spacer(minLength: 0)
                            if c.recommended { Chip("I'd pick this", style: .agent, mono: false) }
                        }
                        .font(.system(size: 12.5)).padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Gate.Radius.control).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: Gate.Radius.control).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if question.allowsText {
                    TextField("", text: $text)
                        .gateField().startPlaceholder("Something else\u{2026}", shown: text.isEmpty).onSubmit { if !text.isEmpty { model.answer(question, choiceID: nil, text: text) } }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.card).fill(Gate.Surface.panel).overlay(RoundedRectangle(cornerRadius: Gate.Radius.card).strokeBorder(Gate.Voice.agent.opacity(0.35), lineWidth: 1)))
    }
}
