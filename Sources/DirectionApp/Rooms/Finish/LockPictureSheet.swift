import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent. Lock picture (35): a checklist of what's still open, then the lock.

struct LockCheck: Identifiable {
    enum Status { case ok, fail, info }
    var id: String
    var status: Status
    var icon: String? = nil
    var title: String
    var detail: String?
    var fix: (title: String, action: () -> Void)? = nil
}

extension FilmModel {
    /// Notes the editor has seen that aren't accepted or dropped yet.
    var openNotes: [ReviewComment] { notes.filter { $0.visibleToEditor && ![.accepted, .dropped].contains($0.lifecycle) && !$0.inInbox } }

    /// Every blocker and warning before picture lock, in the sheet's order.
    var lockChecks: [LockCheck] {
        var out: [LockCheck] = []
        let considered = notes.filter { $0.visibleToEditor && !$0.inInbox && $0.lifecycle != .dropped && !$0.isUnasked }
        let open = openNotes
        if open.isEmpty {
            let numbers = considered.compactMap(\.number).sorted()
            var detail: String?
            if let first = numbers.first, let last = numbers.last, let cut = latestCut {
                let raised = cutName(considered.first?.cutID)
                detail = "Notes \(first == last ? "\(first)" : "\(first)\u{2013}\(last)") on \(raised) are answered in \(cut.name)"
            }
            out.append(.init(id: "notes", status: .ok, title: "\(considered.filter { $0.lifecycle == .accepted }.count) of \(considered.count) notes accepted", detail: considered.isEmpty ? nil : detail))
        } else {
            let unreviewed = toReview.count
            out.append(.init(id: "notes", status: .fail, title: open.count == 1 ? "1 note still open" : "\(open.count) notes still open",
                             detail: "Notes \(open.compactMap(\.number).sorted().map(String.init).joined(separator: ", "))",
                             fix: unreviewed > 0 ? ("Review \(unreviewed) answer\(unreviewed == 1 ? "" : "s")", { self.sheet = nil; self.go(.changes); self.changes.chosenTab = .review }) : ("Open Notes", { self.sheet = nil; self.go(.notes) })))
        }
        let questions = openQuestions.count
        out.append(questions == 0 ? .init(id: "questions", status: .ok, title: "No open questions")
                   : .init(id: "questions", status: .fail, title: questions == 1 ? "1 question waiting" : "\(questions) questions waiting", fix: ("Answer in Notes", { self.sheet = nil; self.notesTab = .questions; self.go(.notes) })))
        let outside = notes.filter(\.isOutside)
        if inbox.isEmpty {
            let names = Array(Set(outside.compactMap { $0.person?.name.split(separator: " ").first.map(String.init) })).sorted()
            let who = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names.first
            out.append(.init(id: "outside", status: .ok, title: "No outside notes waiting", detail: who.map { "\($0)\u{2019}s notes were accepted or declined" }))
        } else {
            out.append(.init(id: "outside", status: .fail, title: inbox.count == 1 ? "1 outside note waiting" : "\(inbox.count) outside notes waiting", fix: ("Open Outside", { self.sheet = nil; self.notesTab = .outside; self.go(.notes) })))
        }
        let length = cutDuration(latestCut) ?? duration
        if length > 0, let lo = brief.lengthMin, let hi = brief.lengthMax {
            let range = "\(Timecode.duration(lo))\u{2013}\(Timecode.duration(hi))"
            if length < lo || length > hi {
                out.append(.init(id: "length", status: .info, icon: "info", title: "\(Timecode.duration(length)) is \(length > hi ? "longer" : "shorter") than your brief (\(range))", detail: "A warning, not a blocker"))
            } else if length > hi - (hi - lo) * 0.05 {
                out.append(.init(id: "length", status: .info, icon: "info", title: "\(Timecode.duration(length)) is near the top of your brief (\(range))"))
            } else {
                out.append(.init(id: "length", status: .ok, title: "\(Timecode.duration(length)), inside your brief", detail: "Brief asks for \(range)"))
            }
        }
        let openScenes = scenes.filter { !$0.locked }
        if openScenes.isEmpty {
            out.append(.init(id: "scenes", status: .ok, title: "Every scene is locked"))
        } else {
            let labels = openScenes.map(\.label)
            let list = labels.count > 1 ? labels.dropLast().joined(separator: ", ") + " and " + labels.last! : labels[0]
            out.append(.init(id: "scenes", status: .info, icon: "lock.fill", title: openScenes.count == 1 ? "1 scene still open" : "\(openScenes.count) scenes still open", detail: "\(list) will lock with the picture"))
        }
        return out
    }

    /// Locks every scene, then the picture, and opens Finish.
    func confirmLockPicture() {
        guard picturelockBlockers.isEmpty else { return }
        if isPreview { directing.pictureLocked = true; sheet = nil; return }
        perform { store in for s in self.dailies.scenes where !s.locked { try store.lockScene(id: s.id, locked: true) } }
        lockPicture()
    }
}

struct LockPictureSheet: View {
    @Bindable var model: FilmModel

    var body: some View {
        let checks = model.lockChecks
        let blocked = checks.contains { $0.status == .fail }
        AttachedSheet(width: 540, onDismiss: { model.sheet = nil }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lock picture on \(model.latestCut?.name ?? "this cut")?").font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary)
                Text("The edit becomes final, and every scene locks with it. The editor starts finishing right away: color, sound, captions and delivery. It can\u{2019}t move a frame.")
                    .font(.system(size: 13)).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(checks.enumerated()), id: \.element.id) { i, c in
                        CheckLine(check: c).hairlineBorder(i == 0 ? [] : .top)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .gateWell()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Before you lock")
                Text("You can unlock later from Finish or Film \u{203A} Unlock Picture. It\u{2019}s recorded in the history.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)

            SheetFooter { EmptyView() } trailing: {
                Button { model.sheet = nil } label: { HStack(spacing: 6) { Text("Cancel"); KeyHint("esc") } }
                    .buttonStyle(.gate(.normal)).keyboardShortcut(.cancelAction)
                Button { model.confirmLockPicture() } label: { Label("Lock picture", systemImage: "lock.fill") }
                    .buttonStyle(.steel).keyboardShortcut(.defaultAction)
                    .disabled(blocked)
                    .help(blocked ? model.picturelockBlockers.joined(separator: ", ") : "Lock picture (↩)")
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Lock picture on \(model.latestCut?.name ?? "this cut")?")
    }
}

/// One check: an 18 pt status circle, the title, a sub line and, when it fails, a way to fix it.
struct CheckLine: View {
    var check: LockCheck
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(fill)
                Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
            }
            .frame(width: 18, height: 18)
            .padding(.top, 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                if let d = check.detail, !d.isEmpty { Text(d).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary) }
            }
            Spacer(minLength: 8)
            if let fix = check.fix { Button(fix.title, action: fix.action).buttonStyle(.gate(.normal, .small)) }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusWord): \(check.title)")
    }
    private var symbol: String {
        switch check.status { case .ok: "checkmark"; case .fail: "xmark"; case .info: check.icon == "lock.fill" ? "lock.fill" : "info" }
    }
    private var fill: Color { switch check.status { case .ok: Gate.State.approveWash; case .fail: Gate.State.alertWash; case .info: Gate.Surface.raised } }
    private var tint: Color { switch check.status { case .ok: Gate.State.approve; case .fail: Gate.State.alert; case .info: Gate.Text.secondary } }
    private var statusWord: String { switch check.status { case .ok: "Done"; case .fail: "Open"; case .info: "Note" } }
}
