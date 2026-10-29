import SwiftUI
import DirectionCore

/// The 52 pt titlebar: crumb (film ▾ / cut ▾), rooms centered, editor pill, share and the one steel button.
struct Titlebar: View {
    @Bindable var model: FilmModel
    var app: AppModel?
    var overPicture = false
    var body: some View {
        ZStack {
            TitlebarDragArea()
            HStack(spacing: 10) {
                Color.clear.frame(width: 62, height: 1) // system traffic lights
                crumb
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button { model.showEditorPopover.toggle() } label: { EditorPill(state: model.pill) }
                        .buttonStyle(.plain)
                        .popover(isPresented: $model.showEditorPopover, arrowEdge: .bottom) { EditorPopover(model: model) }
                        .help("The editor")
                    if model.onboardingStep == nil {
                        Button { model.sheet = .share } label: { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.gate(.ghost, icon: true)).help("Share a screening link (⇧⌘S)")
                    }
                    primaryButton
                }
            }
            .padding(.leading, 20).padding(.trailing, 12)
            center
        }
        .frame(height: Gate.Size.titlebar)
        .background { if overPicture { LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false) } else { Gate.Surface.ground } }
        .overlay(alignment: .bottom) { if !overPicture { Hairline() } }
    }

    @ViewBuilder private var center: some View {
        if let step = model.onboardingStep { OnboardingStepper(step: step) }
        else { RoomSwitcher(model: model) }
    }

    private var crumb: some View {
        HStack(spacing: 2) {
            Menu {
                if let app {
                    Button("Films…") { app.closeFilm() }
                    Divider()
                    ForEach(app.films.prefix(8)) { f in Button(f.name) { app.open(URL(fileURLWithPath: f.path)) } }
                }
                Divider()
                Button("Edit the Brief…") { model.sheet = .brief }
            } label: { crumbLabel(model.filmName, bold: true) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            if model.onboardingStep == nil {
                Text("/").foregroundStyle(Gate.Text.disabled).padding(.horizontal, 2)
                Menu {
                    ForEach(model.cuts.reversed()) { cut in
                        Button { model.watch(cut) } label: { Text(cut.id == model.latestCut?.id ? "\(cut.name) (latest)" : cut.name) }
                    }
                } label: { crumbLabel(model.watchedCut?.name ?? "No cuts yet", bold: false) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().disabled(model.cuts.isEmpty)
                if model.isPictureLocked { Chip("Picture locked", icon: "lock.fill", mono: false).padding(.leading, 6) }
            }
        }
        .font(.system(size: 13))
    }

    private func crumbLabel(_ text: String, bold: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).fontWeight(bold ? .semibold : .medium).foregroundStyle(bold ? Gate.Text.primary : Gate.Text.secondary)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Gate.Text.disabled)
        }.padding(.horizontal, 7).frame(height: 26).contentShape(Rectangle())
    }

    @ViewBuilder private var primaryButton: some View {
        if let p = model.primaryAction {
            Button(action: p.action) {
                HStack(spacing: 6) {
                    if let icon = p.icon { Image(systemName: icon) }
                    Text(p.title)
                    if let count = p.count { CountTag(count, onSteel: model.sheet == nil) }
                }
            }
            .buttonStyle(.gate(model.sheet == nil ? .steel : .normal))
            .disabled(!p.enabled || model.sheet != nil)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

/// Dailies · Script · Screening · Notes · Changes · Finish. ⌘1–⌘6.
struct RoomSwitcher: View {
    @Bindable var model: FilmModel
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Room.allCases) { room in
                let on = model.room == room, enabled = model.isEnabled(room)
                Button { model.go(room) } label: {
                    HStack(spacing: 6) {
                        Text(room.title)
                        if let (text, director) = model.badge(for: room) {
                            Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(director ? Gate.Voice.directorInk : Gate.Component.Button.steelInk)
                                .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15).background(Capsule().fill(director ? Gate.Voice.director : Gate.Voice.agent))
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(on ? Gate.Text.primary : enabled ? Gate.Text.tertiary : Gate.Text.disabled)
                    .padding(.horizontal, 11).frame(height: 24)
                    .background { if on { RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.subtle, lineWidth: 1)).shadow(color: .black.opacity(0.5), radius: 1, y: 1) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(enabled ? "\(room.title) (⌘\(Room.allCases.firstIndex(of: room)! + 1))" : room == .finish ? "Lock picture first" : "Nothing to watch yet")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Gate.Surface.canvas).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
    }
}
