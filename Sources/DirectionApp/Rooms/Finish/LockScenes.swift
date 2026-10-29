import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent. Locking scenes (34): the picture with large scene tiles under it.
// Locked scenes are grayscale, hatched and carry a lock glyph; the editor can't touch them.

struct LockStage: View {
    @Bindable var model: FilmModel

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { g in
                let avail = CGSize(width: max(1, (g.size.width - 56) * 0.88), height: max(1, g.size.height - 32))
                let size = avail.width / avail.height > model.aspect ? CGSize(width: avail.height * model.aspect, height: avail.height) : CGSize(width: avail.width, height: avail.width / model.aspect)
                PictureView(player: model.isPreview ? nil : model.player, still: model.isPreview ? model.stripScene(at: model.position)?.art ?? .dusk : nil, aspect: model.aspect)
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .bottomLeading) { HUDTag("\(model.reviewCut?.name ?? "Cut") \u{00B7} \(Timecode.format(model.position, fps: model.fps))").padding(12) }
                    .overlay { if model.isPreparing { HStack(spacing: 8) { GateSpinner(); Text("Preparing picture").font(Gate.Font.small) }.padding(12).gateGlass(10) } }
                    .position(x: g.size.width / 2, y: 28 + avail.height / 2)
                    .onTapGesture { model.togglePlayback() }
            }
            HStack(spacing: 10) {
                Text("Scenes").font(Gate.Font.brandS).foregroundStyle(Gate.Text.primary)
                Text(help).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
            LockBar(model: model).padding(.horizontal, 24).padding(.bottom, 24)
        }
        .background(Gate.Surface.canvas)
    }

    private var help: String {
        let scenes = model.scenes
        let locked = scenes.filter(\.locked).count
        return "\(locked) of \(scenes.count) locked. Lock a scene when you\u{2019}re happy with it; the editor won\u{2019}t touch it again."
    }
}

/// One tile per scene, sized by its length in the cut. Click selects, ⇧-click locks a run, ⌘L toggles.
struct LockBar: View {
    @Bindable var model: FilmModel
    @State private var hovered: String?
    private var state: ChangesState { model.changes }

    var body: some View {
        let scenes = model.stripScenes
        GeometryReader { g in
            let total = max(0.001, scenes.map(\.duration).reduce(0, +))
            let usable = max(1, g.size.width - CGFloat(max(0, scenes.count - 1)) * 3)
            HStack(spacing: 3) {
                ForEach(scenes) { s in
                    tile(s).frame(width: max(24, usable * s.duration / total))
                }
            }
        }
        .frame(height: 84)
        .alert(unlockTitle, isPresented: Binding(get: { state.unlockSceneID != nil }, set: { if !$0 { state.unlockSceneID = nil } })) {
            Button("Unlock") { if let id = state.unlockSceneID { setLock(id, false) }; state.unlockSceneID = nil }
            Button("Cancel", role: .cancel) { state.unlockSceneID = nil }
        } message: { Text("The editor can change it again in the next cut.") }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scenes")
    }

    private var unlockTitle: String {
        let s = state.unlockSceneID.flatMap { id in model.dailies.scenes.first { $0.id == id } }
        return "Unlock \(s?.label ?? "this scene")?"
    }

    private func isLocked(_ s: StripScene) -> Bool { model.dailies.scenes.first { $0.id == s.id }?.locked ?? s.locked }

    private func tile(_ s: StripScene) -> some View {
        let locked = isLocked(s), active = hovered == s.id || state.lockSceneID == s.id
        return ZStack(alignment: .topLeading) {
            Gate.Surface.panel
            Thumbnail(path: s.thumbnail, art: s.art).opacity(locked ? 0.28 : 0.6).grayscale(locked ? 1 : 0)
            if locked { Hatching() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    if locked { Image(systemName: "lock.fill").font(.system(size: 8, weight: .semibold)) }
                    Text(s.label).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.primary).shadow(color: .black, radius: 1.5, y: 1)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(ChangesFormat.shortRange(s.start, s.end)).lineLimit(1)
                    Spacer(minLength: 0)
                    if active && !model.isPictureLocked {
                        Button { locked ? (state.unlockSceneID = s.id) : setLock(s.id, true) } label: {
                            SmallIconLabel(locked ? "Unlock" : "Lock", icon: locked ? "lock.open" : "lock.fill", size: 9)
                        }
                        .buttonStyle(.gate(.normal, .small))
                        .help(locked ? "Unlock \(s.label)" : "Lock \(s.label) (⌘L)")
                    } else if locked {
                        Image(systemName: "lock.fill").font(.system(size: 8, weight: .semibold))
                    }
                }
                .font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.secondary).shadow(color: .black, radius: 1.5, y: 1)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(active ? Gate.Text.primary : locked ? Gate.Line.strong : Gate.Line.subtle, lineWidth: active ? 1.5 : 1))
        .animation(gateAnimation(Gate.Motion.settle), value: locked)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? s.id : (hovered == s.id ? nil : hovered) }
        .onTapGesture { select(s) }
        .contextMenu { SceneContextMenu(model: model, scene: s) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scene \(s.number), \(s.title), \(ChangesFormat.mmss(s.start)) to \(ChangesFormat.mmss(s.end)), \(locked ? "locked" : "not locked")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: locked ? "Unlock" : "Lock") { locked ? (state.unlockSceneID = s.id) : setLock(s.id, true) }
    }

    private func select(_ s: StripScene) {
        let shift = NSEvent.modifierFlags.contains(.shift)
        if shift, let anchor = state.lockAnchorID, !model.isPictureLocked {
            let scenes = model.stripScenes
            if let a = scenes.firstIndex(where: { $0.id == anchor }), let b = scenes.firstIndex(where: { $0.id == s.id }) {
                for scene in scenes[min(a, b)...max(a, b)] where !isLocked(scene) { setLock(scene.id, true) }
            }
        } else {
            state.lockAnchorID = s.id
        }
        state.lockSceneID = s.id
        model.pause(); model.seek(s.start)
    }

    private func setLock(_ id: String, _ on: Bool) {
        if model.isPreview {
            if let i = model.dailies.scenes.firstIndex(where: { $0.id == id }) { model.dailies.scenes[i].locked = on }
        } else {
            model.lockScene(id, on)
        }
        if let s = model.dailies.scenes.first(where: { $0.id == id }) {
            AccessibilityNotification.Announcement("\(s.title) \(on ? "locked" : "unlocked")").post()
        }
    }
}
