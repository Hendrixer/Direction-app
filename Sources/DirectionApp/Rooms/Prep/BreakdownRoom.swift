import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DirectionCore

// The Breakdown room (specs/breakdown.md): the OK'd script as shots by setup, each with its source. Before the
// shoot it's the plan; after, the checklist: what came in, what's missing, what to make or pick up.

enum BreakdownOrder: String { case setup, script }

struct BreakdownRoom: View {
    @Bindable var model: FilmModel
    @Environment(\.prepPreview) private var preview
    var body: some View {
        if let b = model.breakdown, !b.shots.isEmpty { BreakdownPage(model: model, breakdown: b, preview: preview) }
        else {
            EmptyStateView(art: nil, title: model.breakingDown ? "Breaking down the script" : "No breakdown yet",
                           message: model.breakingDown ? "The editor is turning every moment of the script into shots, grouped by where and in what light you\u{2019}ll shoot them. They show here as each page of the script is done." : "OK the script and the editor breaks it down into shots by setup.") {
                if model.breakingDown { GateProgress(value: nil, agent: true).frame(width: 160) }
                else { Button("Open Script") { model.go(.script) }.buttonStyle(.gate(.normal, .large)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Gate.Surface.ground)
        }
    }
}

private struct BreakdownPage: View {
    @Bindable var model: FilmModel
    var breakdown: Breakdown
    @State private var selected: String?
    @State private var order: BreakdownOrder = .setup
    @State private var jump: String?
    /// The scroll area's width: a wide window reads bigger (PrepMeasure).
    @State private var available: CGFloat = 0
    private var measure: PrepMeasure { PrepMeasure(available: available) }

    /// Worked out once a draw: every row and shot reads them.
    private let coverage: [String: ShotCoverage]
    private let script: AVScript
    private let rowNumber: [String: Int]
    private let plays: PlaysAt
    private let shotsIn: [String: [BreakdownShot]]

    init(model: FilmModel, breakdown: Breakdown, preview: PrepPreview?) {
        self.model = model; self.breakdown = breakdown
        coverage = ProjectStore.coverage(breakdown, dailies: model.dailies)
        script = model.script ?? AVScript()
        rowNumber = Dictionary(script.rows.enumerated().map { ($0.element.id, $0.offset + 1) }, uniquingKeysWith: { a, _ in a })
        plays = PlaysAt(script)
        shotsIn = Dictionary(grouping: breakdown.shots, by: \.setupID).mapValues { $0.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending } }
        _selected = State(initialValue: preview?.shot.flatMap { code in breakdown.shot(code: code)?.id } ?? breakdown.shots.first?.id)
    }

    private var setups: [BreakdownSetup] { breakdown.setups.sorted { $0.number < $1.number } }

    var body: some View {
        HStack(spacing: 0) {
            nav.frame(width: 240)
            ScrollViewReader { proxy in
                // Centered and kept to a width you can read across; a wide page reads a step bigger (PrepMeasure).
                ScrollView { main.frame(maxWidth: PrepMeasure.cap).padding(.horizontal, PrepMeasure.margin).padding(.vertical, 22).frame(maxWidth: .infinity) }
                    .measuringWidth($available)
                    .onChange(of: jump) { _, id in if let id { withAnimation(gateAnimation(Gate.Motion.glide)) { proxy.scrollTo(id, anchor: .top) }; jump = nil } }
            }
            .frame(maxWidth: .infinity).background(Gate.Surface.ground)
            if let shot = selected.flatMap({ breakdown.shot($0) }) {
                ShotInspector(model: model, breakdown: breakdown, shot: shot, coverage: coverage[shot.id] ?? .planned, rowNumber: rowNumber, plays: plays).frame(width: 360).id(shot.id)
            }
        }
    }

    // MARK: Setups

    private var nav: some View {
        VStack(alignment: .leading, spacing: 1) {
            GateSegmented(options: [(BreakdownOrder.setup, "By setup"), (.script, "Script order")], selection: $order).padding(.horizontal, 9).padding(.bottom, 12)
            let camera = setups.filter { $0.noCamera != true }, none = setups.filter { $0.noCamera == true }
            if !camera.isEmpty { SectionLabel("To shoot").padding(.horizontal, 9).padding(.bottom, 8) }
            ForEach(camera) { s in setupRow(s) }
            if !none.isEmpty { SectionLabel("No camera").padding(.horizontal, 9).padding(.top, 20).padding(.bottom, 8) }
            ForEach(none) { s in setupRow(s) }
            let pickups = breakdown.shots.filter { $0.missing == .pickup }
            if breakdown.isOK && model.hasFootage {
                SectionLabel("Next shoot").padding(.horizontal, 9).padding(.top, 20).padding(.bottom, 8)
                OutlineRow(title: "Pickups", icon: "film", count: "\(pickups.count)") { if let p = pickups.first { selected = p.id; jump = p.id } }
            }
            VStack(alignment: .leading, spacing: 8) {
                if breakdown.isOK { Button { model.printShootList() } label: { Label("Print shoot list\u{2026}", systemImage: "printer") }.buttonStyle(.gate(.ghost, .small)) }
                Text(breakdown.isOK ? (model.hasFootage ? "Bring footage after each day of shooting. Each shot fills in as its takes arrive." : "Shot numbers are your slates. Say \u{201C}2C, take one\u{201D} at the head of each take.") : "Grouped by place and light, so you set each one up once.")
                    .font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 9).padding(.top, 18)
            Spacer()
        }
        .padding(.vertical, 14).padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .hairlineBorder(.trailing)
    }

    private func setupRow(_ s: BreakdownSetup) -> some View {
        let shots = shotsIn[s.id] ?? []
        let shotIn = shots.filter { coverage[$0.id]?.isIn == true }.count
        let shotCount = model.hasFootage && breakdown.isOK ? "\(shotIn) of \(shots.count)" : "\(shots.count)"
        return OutlineRow(title: "\(s.number)  \(s.name)", count: shotCount, on: breakdown.shot(selected ?? "")?.setupID == s.id) {
            order = .setup; if let first = shots.first { selected = first.id; jump = s.id }
        }
    }

    // MARK: Shots

    /// Lazy: a breakdown runs to hundreds of shots, and only the ones on screen are built.
    private var main: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                head
                if script.revision > (breakdown.scriptRevision ?? 0), !model.breakingDown {
                    Banner(icon: "doc.text", title: "The script changed after this breakdown was made.", detail: breakdown.isOK ? "Shot numbers and your edits stay." : "The editor brings the shots up to date.") {
                        Button("Update the breakdown") { model.updateBreakdownFromScript() }.buttonStyle(.gate(.normal, .small))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Gate.Line.subtle))
                }
                if let say = editorSays {
                    HStack(alignment: .top, spacing: 9) { GemMark().padding(.top, 5); Text(say).font(.system(size: 13)).foregroundStyle(Gate.Text.primary).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .padding(.bottom, 20)
            switch order {
            case .setup:
                ForEach(setups) { s in
                    Section { ForEach(shotsIn[s.id] ?? []) { shot in shotRow(shot) } } header: { groupHead(s).padding(.top, s.id == setups.first?.id ? 0 : 20) }
                }
            case .script:
                ForEach(inScriptOrder) { shot in shotRow(shot) }
            }
        }
    }

    private var inScriptOrder: [BreakdownShot] {
        breakdown.shots.map { ($0.rowIDs.compactMap { rowNumber[$0] }.min() ?? .max, $0) }.sorted { ($0.0, $0.1.code) < ($1.0, $1.1.code) }.map(\.1)
    }

    /// What the editor said when it last finished the breakdown, or how the shoot stands.
    private var editorSays: String? {
        if model.breakingDown {
            let covered = Set(breakdown.shots.flatMap(\.rowIDs)).count
            return "Breaking down the script: \(covered) of its \(script.rows.count) moments have a shot so far."
        }
        let missing = breakdown.shots.filter { coverage[$0.id] == .missing }
        if breakdown.isOK, model.hasFootage, !missing.isEmpty {
            return "\(missing.count == 1 ? "\(missing[0].code) didn\u{2019}t come in" : "\(missing.map(\.code).joined(separator: ", ")) didn\u{2019}t come in"). Choose what to do with each: make it, pick it up on the next shoot, or do without."
        }
        return model.runs.runs.last { $0.job == .breakdown && $0.state == .done }?.summary
    }

    private var head: some View {
        let counts = Dictionary(grouping: breakdown.shots, by: \.source).mapValues(\.count)
        let shotIn = breakdown.shots.filter { coverage[$0.id]?.isIn == true }.count
        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Breakdown").font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary)
                Text(subtitle).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            }
            Spacer()
            // The editor's open questions, counted up here (a click goes to the first); each shows on its shot.
            let asking = breakdown.shots.filter { $0.question?.isOpen == true }
            if let first = asking.first {
                Button { selected = first.id; jump = first.id } label: { Chip(asking.count == 1 ? "1 question" : "\(asking.count) questions", style: .agent, icon: "diamond", mono: false) }
                    .buttonStyle(.plain).help("Go to the first shot the editor is asking about")
            }
            if breakdown.isOK && model.hasFootage {
                VStack(alignment: .trailing, spacing: 7) {
                    Text("\(shotIn) of \(breakdown.shots.count) in").font(Gate.Font.timecode).foregroundStyle(Gate.Text.primary)
                    GateProgress(value: Double(shotIn) / Double(max(1, breakdown.shots.count))).frame(width: 200)
                }
            } else {
                HStack(spacing: 6) {
                    ForEach([ShotSource.shoot, .screen, .sound, .make, .have], id: \.self) { src in
                        if let n = counts[src] {
                            Chip(src == .make && breakdown.estimate > 0 ? "Make \(n) \u{00B7} about \(PrepDollars.text(breakdown.estimate))" : "\(src.label) \(n)", style: src == .make ? .agent : src == .have ? .ok : .plain, mono: false)
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let n = breakdown.shots.count
        if breakdown.isOK { return model.hasFootage ? "\(n) shots \u{00B7} \(model.footage.count) takes in" : "\(n) shots \u{00B7} nothing shot yet" }
        return "\(n) shots from the script you OK\u{2019}d \u{00B7} OK it and the numbers become slates"
    }

    private func groupHead(_ s: BreakdownSetup) -> some View {
        let shots = shotsIn[s.id] ?? []
        // What the setup needs is the plan for the day, so it reads whole, under the name.
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("\(s.number)").font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.primary)
                    .frame(minWidth: 22, minHeight: 22).background(RoundedRectangle(cornerRadius: 6).fill(Gate.Surface.raised)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Gate.Line.subtle))
                Text(s.name).font(.system(size: measure.text(13), weight: .semibold))
                Spacer()
                Text(model.hasFootage && breakdown.isOK ? "\(shots.filter { coverage[$0.id]?.isIn == true }.count) of \(shots.count)" : shots.count == 1 ? "1 shot" : "\(shots.count) shots").font(Gate.Font.mono).foregroundStyle(Gate.Text.disabled)
            }
            if let needs = s.needs {
                Text(needs).font(.system(size: measure.caption(12.5))).foregroundStyle(Gate.Text.secondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 980, alignment: .leading).padding(.leading, 32)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Gate.Line.strong).frame(height: 1) }
        .id(s.id)
    }

    private func shotRow(_ shot: BreakdownShot) -> some View {
        let c = coverage[shot.id] ?? .planned
        let isSel = selected == shot.id
        let covering = breakdown.isOK && model.hasFootage
        return Button { selected = shot.id } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        if shot.addedAfterOK == true || (breakdown.pass > 1 && shot.pass == breakdown.pass) { GemMark(size: 7, solid: true) }
                        Text(shot.code).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.primary)
                    }.frame(width: 34, alignment: .leading)
                    ShotPicture(model: model, shot: shot, coverage: c).frame(width: measure.shot, height: measure.shot * 9 / 16)
                    VStack(alignment: .leading, spacing: 3 + measure.step) {
                        Text(shot.what).font(.system(size: measure.text(13))).foregroundStyle(Gate.Text.primary).lineLimit(measure.step > 0 ? 3 : 2)
                        // How to get it on the day, under what we see; all of it is in the shot's panel.
                        if let how = shot.how, !covering { Text(how).font(.system(size: measure.text(12))).foregroundStyle(Gate.Text.secondary).lineLimit(2) }
                        Text(caption(shot, c)).font(.system(size: measure.caption(11))).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if covering { takes(c).frame(width: 164, alignment: .leading) }
                    else { playsUnder(shot).frame(width: 210 + 45 * measure.step, alignment: .leading) }
                    if !covering { Text(Timecode.duration(shot.seconds)).font(Gate.Font.mono).foregroundStyle(Gate.Text.secondary).frame(width: 40, alignment: .trailing) }
                    status(shot, c).frame(width: covering ? 110 : 86, alignment: .trailing)
                }
                // The editor's question on the shot, one line; its choices are in the inspector.
                if let q = shot.question, q.isOpen {
                    HStack(spacing: 9) {
                        GemMark()
                        Text(q.text).font(.system(size: measure.text(12.5))).foregroundStyle(Gate.Text.secondary).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text("Answer\u{2026}").font(.system(size: 12, weight: .medium)).foregroundStyle(Gate.Text.secondary)
                    }
                    // Under the words: past the code and the picture.
                    .padding(.leading, 34 + 14 + measure.shot + 14)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, measure.rowPadding)
            .background(isSel ? RoundedRectangle(cornerRadius: 8).fill(Gate.Surface.panel) : nil)
            .overlay(isSel ? RoundedRectangle(cornerRadius: 8).strokeBorder(Gate.Line.subtle) : nil)
            .overlay(alignment: .bottom) { if !isSel { Rectangle().fill(Gate.Line.subtle).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(shot.id)
    }

    private func caption(_ shot: BreakdownShot, _ c: ShotCoverage) -> String {
        if case .got(let ids) = c, breakdown.isOK {
            let circled = ids.first { model.dailies.takes[$0]?.circled == true }.flatMap { model.dailies.takes[$0]?.code }
            return [ids.count == 1 ? "1 take" : "\(ids.count) takes", circled.map { "\($0) circled" }].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
        if c == .needsFootage { return "Not added yet" }
        if shot.source == .make { return shot.estimate.map { "Made shot \u{00B7} about \(PrepDollars.text($0))" } ?? "Made in Direction \u{00B7} free" }
        return [shot.source == .sound ? "Sound only" : nil, shot.size?.label, shot.move?.label].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// Where in the film it plays: the moments by name, then their times. Not row numbers, which only the
    /// Script shows.
    private func playsUnder(_ shot: BreakdownShot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name = plays.name(shot.rowIDs) { Text(name).font(.system(size: measure.caption(11.5))).foregroundStyle(Gate.Text.secondary).lineLimit(2) }
            Text(plays.times(shot.rowIDs)).font(.system(size: measure.caption(10.5), weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
        }
    }

    private func takes(_ c: ShotCoverage) -> some View {
        HStack(spacing: 4) {
            if case .got(let ids) = c {
                ForEach(Array(ids.prefix(3)).sorted { (model.dailies.takes[$0]?.code ?? "").localizedStandardCompare(model.dailies.takes[$1]?.code ?? "") == .orderedAscending }, id: \.self) { id in
                    let t = model.dailies.takes[id]
                    ZStack(alignment: .topLeading) {
                        Thumbnail(path: model.asset(id)?.thumbnailPath, art: model.dailiesArt(id)).frame(width: 42, height: 24).clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(t?.code ?? "").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.primary).shadow(color: .black, radius: 1).padding(.leading, 3).padding(.top, 2)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(t?.circled == true ? Gate.Voice.director : Gate.Line.subtle, lineWidth: t?.circled == true ? 1.5 : 1))
                }
                if ids.count > 3 { Text("+\(ids.count - 3)").font(Gate.Font.mono).foregroundStyle(Gate.Text.tertiary).fixedSize() }
            } else { Text("\u{2014}").font(Gate.Font.small).foregroundStyle(Gate.Text.disabled) }
        }
    }

    @ViewBuilder private func status(_ shot: BreakdownShot, _ c: ShotCoverage) -> some View {
        switch c {
        case .got: if breakdown.isOK && model.hasFootage || shot.source == .have { Chip(shot.source == .have ? "Have it" : "Got it", style: .ok, icon: "checkmark", mono: false) } else { Chip(shot.source.label, mono: false) }
        case .missing:
            switch shot.missing {
            case .pickup: Chip("Pick up", mono: false)
            case .make: Chip("Make", style: .agent, mono: false)
            case .without: Chip("Without", style: .label, mono: false)
            case nil: Chip("Missing", style: .bad, icon: "exclamationmark.triangle", mono: false)
            }
        case .needsFootage: Chip("Add footage", mono: false)
        case .toMake: Chip("Make", style: .agent, mono: false)
        case .planned: Chip(shot.source.label, mono: false)
        }
    }
}

/// A shot's picture in a row: its circled take once one is in, else its board.
struct ShotPicture: View {
    @Bindable var model: FilmModel
    var shot: BreakdownShot
    var coverage: ShotCoverage
    var label: String? = nil
    var body: some View {
        Group {
            if case .got(let ids) = coverage, let id = ids.first {
                Thumbnail(path: model.asset(id)?.thumbnailPath, art: model.dailiesArt(id))
                    .clipShape(RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle))
            } else if shot.source == .sound {
                RoundedRectangle(cornerRadius: 4).fill(Gate.Surface.sunken).overlay(Image(systemName: "waveform").font(.system(size: 16)).foregroundStyle(Gate.Text.tertiary)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle))
            } else if coverage == .needsFootage {
                RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Gate.Line.strong)
                    .overlay(Text("Drop here").font(.system(size: 10)).foregroundStyle(Gate.Text.disabled))
            } else {
                BoardView(kind: shot.board ?? (shot.source == .screen ? .screen : shot.source == .make ? .made : .medium), move: shot.move, label: label)
            }
        }
    }
}

/// Where a shot plays, for a director who doesn't think in script rows: the moments it plays under, by a story
/// beat's title or the words we hear there, and their times in the film. "Hold", "0:29–0:38".
struct PlaysAt {
    private let rows: [String: (index: Int, row: AVRow, start: Double)]

    init(_ script: AVScript) {
        var t = 0.0, out: [String: (Int, AVRow, Double)] = [:]
        for (i, r) in script.rows.enumerated() { out[r.id] = (i, r, t); t += r.seconds }
        rows = out
    }

    /// A story's beat by its title (or its words, when it has none); a script's line by what we hear, quoted.
    static func name(_ r: AVRow) -> String? {
        if let story = r.story { let lead = ScriptImport.beatLead(story); return (lead.title ?? lead.body).nilIfBlank }
        return r.sound.text.nilIfBlank.map { "\u{201C}\($0)\u{201D}" } ?? r.sound.kind.label
    }

    /// "Hold"; "Assembly, Tighter"; "Tighter to Hold" past two. A script's lines: the first one's words.
    func name(_ rowIDs: [String]) -> String? {
        let found = rowIDs.compactMap { rows[$0] }.sorted { $0.index < $1.index }
        guard found.first?.row.story != nil else { return found.first.flatMap { Self.name($0.row) } }
        var names: [String] = []
        for f in found { if let n = Self.name(f.row), names.last != n { names.append(n) } }
        switch names.count {
        case 0: return nil
        case 1, 2: return names.joined(separator: ", ")
        default: return "\(names[0]) to \(names[names.count - 1])"
        }
    }

    /// "0:29–0:38", or "0:05–0:13 and 0:29–0:38" when they aren't together.
    func times(_ rowIDs: [String]) -> String {
        let found = rowIDs.compactMap { rows[$0] }.sorted { $0.index < $1.index }
        var runs: [(Double, Double)] = [], last = -2
        for f in found {
            if f.index == last + 1, let r = runs.popLast() { runs.append((r.0, f.start + f.row.seconds)) } else { runs.append((f.start, f.start + f.row.seconds)) }
            last = f.index
        }
        let text = runs.map { "\(Timecode.duration($0.0))\u{2013}\(Timecode.duration($0.1))" }
        return text.count > 1 ? text.dropLast().joined(separator: ", ") + " and " + text.last! : text.first ?? ""
    }
}
