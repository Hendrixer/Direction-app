import SwiftUI
import AVKit
import DirectionCore
import DirectionMedia

// Owner: Changes and Finish agent. Two pictures side by side on one playhead (30), used for an
// answer's options A and B and for comparing whole cuts (33).

/// Two players driven by one playhead. Each side compiles its own pinned revision.
@MainActor @Observable
final class ABPlayback {
    struct Side { var revision: Int?; var sequenceID: String? }
    @ObservationIgnored let players = [AVPlayer(), AVPlayer()]
    var ready = [false, false]
    var missing = [false, false]
    var position = 0.0
    var playing = false
    /// The side whose sound plays. Click a card or press 1 or 2.
    var audible = 0
    /// Off: the transport drives only the audible side, so the two can sit at different moments.
    var synced = true
    @ObservationIgnored private var observers: [(AVPlayer, Any)] = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    func load(model: FilmModel, sides: [Side], start: Double) {
        position = start
        guard !model.isPreview, let runtime = model.runtime else { return }
        model.pause()
        for (i, side) in sides.prefix(2).enumerated() {
            guard let revision = side.revision, let project = CutProjects.project(model, revision: revision) else { missing[i] = true; continue }
            let player = players[i]
            player.automaticallyWaitsToMinimizeStalling = false
            tasks.append(Task { [weak self] in
                do {
                    let compiled = try await SequenceRenderer.compile(project: project, sequenceID: side.sequenceID, cacheDirectory: runtime.cacheDirectory, previewMaxDimension: 1280)
                    try Task.checkCancellation()
                    guard let self else { return }
                    player.replaceCurrentItem(with: compiled.playerItem())
                    await player.seek(to: CMTime(seconds: self.position, preferredTimescale: 600_000), toleranceBefore: .zero, toleranceAfter: .zero)
                    self.ready[i] = true
                    self.applyMute()
                } catch { if !Task.isCancelled { self?.missing[i] = true } }
            })
            let token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1 / 24, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, self.lead == i, time.seconds.isFinite else { return }
                    self.position = time.seconds
                    self.playing = player.rate != 0
                }
            }
            observers.append((player, token))
        }
        applyMute()
    }

    /// The side the playhead follows.
    private var lead: Int { synced ? (ready[0] ? 0 : 1) : audible }
    private var active: [Int] { (synced ? [0, 1] : [audible]).filter { ready[$0] } }

    func toggle() { playing ? pause() : play() }
    func play() {
        let items = active
        guard !items.isEmpty else { return }
        let time = CMTime(seconds: position, preferredTimescale: 600_000)
        // Start both on the same host-clock instant so they stay frame-locked.
        let host = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(value: 1, timescale: 10))
        for i in items {
            let p = players[i]
            if p.currentItem?.status == .readyToPlay { p.setRate(1, time: time, atHostTime: host) } else { p.play() }
        }
        playing = true
    }
    func pause() { players.forEach { $0.pause() }; playing = false }
    func seek(_ t: Double) {
        position = max(0, t)
        for i in active { players[i].seek(to: CMTime(seconds: position, preferredTimescale: 600_000), toleranceBefore: .zero, toleranceAfter: .zero) }
    }
    func setAudible(_ i: Int) {
        audible = i
        applyMute()
        if !synced && playing { pause() }
    }
    func toggleSync() {
        pause()
        synced.toggle()
        if synced { seek(position) }
    }
    private func applyMute() { for (i, p) in players.enumerated() { p.isMuted = i != audible } }

    func tearDown() {
        tasks.forEach { $0.cancel() }; tasks = []
        pause()
        for (p, token) in observers { p.removeTimeObserver(token) }
        observers = []
        players.forEach { $0.replaceCurrentItem(with: nil) }
    }
}

/// One side of an A/B comparison.
struct ABSide {
    var letter: String
    var title: String
    var detail: String
    var delta: String?
    var preferred = false
    var using = false
    var art: FootageArt
    var revision: Int?
    var sequenceID: String?
    var unavailable: String?
    /// The made clip this side uses, for its Made chip.
    var made: MadeRecord? = nil
}

/// The two cards, the foot and the shared transport.
struct ABStage<Foot: View>: View {
    @Bindable var model: FilmModel
    var sides: [ABSide]
    var start: Double
    var groupLabel: String
    @ViewBuilder var foot: (ABPlayback) -> Foot
    @State private var ab = ABPlayback()
    /// The card the director clicked. The editor's preference is never preselected.
    private var focusedSide: Int? { model.changes.optionFocus }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 14) { card(0); card(1) }
                    .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(groupLabel)
                Spacer(minLength: 0)
                foot(ab).padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 6)
            }
            transport
        }
        .background(Gate.Surface.canvas)
        .onAppear {
            model.changes.ab = ab
            ab.load(model: model, sides: sides.map { .init(revision: $0.revision, sequenceID: $0.sequenceID) }, start: start)
            if model.isPreview { ab.position = model.position }
            if let f = model.changes.optionFocus { ab.setAudible(f) }
        }
        .onDisappear { ab.tearDown(); model.changes.optionFocus = nil; if model.changes.ab === ab { model.changes.ab = nil } }
    }

    private func card(_ i: Int) -> some View {
        let side = sides[i], on = focusedSide == i
        return VStack(alignment: .leading, spacing: 10) {
            picture(i, side)
            HStack(spacing: 8) {
                Text("\(side.title)").font(Gate.Font.brand(size: 14, width: 116, weight: 800)).foregroundStyle(Gate.Text.primary)
                Text(side.detail).font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary).lineLimit(1)
                if side.preferred { Chip("I\u{2019}d pick this", style: .agent, mono: false).accessibilityLabel("Editor recommends \(side.letter)") }
                if side.using { Chip("Using \(side.letter)", style: .ok, mono: false) }
                Spacer(minLength: 4)
                if let d = side.delta { Text(d).font(Gate.Font.mono).foregroundStyle(Gate.Text.tertiary) }
                if let made = side.made { MadeChip(film: model, record: made, place: "option") }
            }
            .padding(.horizontal, 4).padding(.bottom, 4)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.card).fill(on ? Gate.Surface.raised : Gate.Steel.ramp[1]))
        .overlay(RoundedRectangle(cornerRadius: Gate.Radius.card).strokeBorder(Gate.Line.subtle, lineWidth: 1))
        .overlay { if on { RoundedRectangle(cornerRadius: Gate.Radius.card + 2).strokeBorder(Gate.Text.primary, lineWidth: 2).padding(-2) } }
        .opacity(model.changes.optionChosen.map { $0 == side.letter ? 1 : 0.4 } ?? 1)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(gateAnimation(Gate.Motion.snap)) { model.changes.optionFocus = i }; ab.setAudible(i) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Plays this side's sound")
    }

    private func picture(_ i: Int, _ side: ABSide) -> some View {
        ZStack {
            Gate.Surface.canvas
            if model.isPreview {
                FootageArtView(art: side.art).saturation(i == 1 ? 0.7 : 1).brightness(i == 1 ? -0.06 : 0)
            } else if let why = side.unavailable ?? (ab.missing[i] ? "This version isn\u{2019}t on disk." : nil) {
                Text(why).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).multilineTextAlignment(.center).padding(20)
            } else if ab.ready[i] {
                PlayerSurface(player: ab.players[i]).allowsHitTesting(false)
            } else {
                HStack(spacing: 8) { GateSpinner(); Text("Preparing picture").font(Gate.Font.small).foregroundStyle(Gate.Text.secondary) }
            }
        }
        .aspectRatio(model.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.frame))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text(side.letter)
                if ab.audible == i && (focusedSide != nil || !model.isPreview) { Image(systemName: "speaker.wave.2.fill").font(.system(size: 9)) }
            }
            .font(Gate.Font.timecodeSmall).foregroundStyle(Gate.Text.primary)
            .padding(.horizontal, 8).padding(.vertical, 6).gateGlass(6).padding(8)
        }
    }

    private var transport: some View {
        let t = model.isPreview ? model.position : ab.position
        return HStack(spacing: 12) {
            Button { ab.toggle(); if model.isPreview { model.playing.toggle() } } label: { Image(systemName: ab.playing || model.playing ? "pause.fill" : "play.fill") }
                .buttonStyle(.gate(.normal, icon: true)).help(ab.playing ? "Pause both (Space)" : "Play both (Space)")
            TimecodeLabel(time: t, total: model.duration, fps: model.fps)
            SceneStrip(scenes: model.stripScenes, duration: model.duration, playhead: t, marks: model.answerMarks, onSeek: { ab.seek($0); if model.isPreview { model.position = $0 } })
            Button { ab.toggleSync() } label: {
                HStack(spacing: 6) { Image(systemName: ab.synced ? "link" : "personalhotspot.slash").font(.system(size: 10, weight: .medium)); Text(ab.synced ? "Synced" : "Unlinked") }
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.tertiary).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(ab.synced ? "Both pictures follow one playhead. Click to scrub the sound side alone." : "Only the side with sound plays. Click to link them again.")
        }
        .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 16)
    }
}

/// An answer's two options (30).
struct OptionsStage: View {
    @Bindable var model: FilmModel
    let note: ReviewComment
    @State private var changing = false

    private var answer: NoteAnswer? { model.answer(note, in: model.reviewCut) }
    private var options: [NoteOption] { Array((answer?.options ?? []).prefix(2)) }
    private var picked: String? { model.status(note) == .accepted ? answer?.pick : nil }

    var body: some View {
        ABStage(model: model, sides: sides, start: max(0, (model.answerRange(note)?.lowerBound ?? model.position) - model.handleSeconds), groupLabel: "Options for note \(note.number.map(String.init) ?? "")") { _ in foot }
            .id(note.id)
    }

    private var sides: [ABSide] {
        let art = model.answerScene(note)?.art ?? .room
        let inCut = answer?.pick ?? answer?.preferred
        return options.map { o in
            // An option without its own revision is the version that went into the cut.
            let revision = o.revision ?? (o.label == inCut ? answer?.revision : nil)
            return ABSide(letter: o.label, title: "Option \(o.label)", detail: o.summary, delta: o.delta, preferred: answer?.preferred == o.label, using: picked == o.label, art: art,
                          revision: revision, sequenceID: model.reviewCut?.sequenceID, unavailable: revision == nil ? "The editor didn\u{2019}t keep a separate version of option \(o.label)." : nil,
                          made: answer.flatMap { model.made.record(for: note, option: o, answer: $0, film: model) })
        }
    }

    private var foot: some View {
        HStack(spacing: 12) {
            Text(quote).font(.system(size: 13)).lineSpacing(3).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if picked != nil && !changing {
                Button("Change pick") { changing = true }.buttonStyle(.gate(.normal))
            } else {
                ForEach(options, id: \.label) { o in
                    Button("Use \(o.label)") { changing = false; model.chooseOption(note.id, o.label) }
                        .buttonStyle(.gate(.normal)).help("Use option \(o.label) (\(o.label))")
                        .accessibilityLabel("Use option \(o.label), \(o.summary)")
                }
            }
            Button("Neither, reply") { model.replyToAnswer(note.id) }.buttonStyle(.gate(.ghost)).help("Reply (⌘R)")
        }
    }

    private var quote: AttributedString {
        var head = AttributedString("Note \(note.number.map(String.init) ?? "") \u{00B7} \(model.kindLabel(note)).")
        head.foregroundColor = Gate.Text.primary; head.font = .system(size: 13, weight: .medium)
        var body = AttributedString(" \u{201C}\(note.text)\u{201D} \(answer?.summary ?? "")")
        body.foregroundColor = Gate.Text.secondary
        return head + body
    }
}

/// Compare whole cuts: the cut before and the selected cut, synced.
struct CompareCutsStage: View {
    @Bindable var model: FilmModel
    var body: some View {
        let after = model.historyCut, before = model.cutBefore(after)
        ABStage(model: model, sides: [side("A", before), side("B", after)], start: 0, groupLabel: "Compare \(before?.name ?? "") and \(after?.name ?? "")") { _ in
            HStack(spacing: 12) {
                Text("Comparing \(before?.name ?? "the cut before") and \(after?.name ?? "this cut"). One playhead drives both; press 1 or 2 to switch the sound.")
                    .font(.system(size: 13)).foregroundStyle(Gate.Text.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Button("Done") { model.changes.comparingCuts = false }.buttonStyle(.gate(.normal)).keyboardShortcut(.cancelAction)
            }
        }
        .id("\(before?.id ?? "")-\(after?.id ?? "")")
    }
    private func side(_ letter: String, _ cut: ReviewCut?) -> ABSide {
        ABSide(letter: letter, title: cut?.name ?? "\u{2013}", detail: model.cutDuration(cut).map(Timecode.duration) ?? "", art: model.stripScene(at: model.position)?.art ?? .room,
               revision: cut?.editRevision, sequenceID: cut?.sequenceID, unavailable: cut == nil ? "There\u{2019}s no cut before this one." : nil)
    }
}
