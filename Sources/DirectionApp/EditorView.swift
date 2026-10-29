import SwiftUI
import AppKit
import AVKit
import DirectionCore

struct EditorView: View {
    @Bindable var model: EditorModel
    @State private var screening = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            header
            DirectionDivider()
            if model.project == nil { welcome }
            else {
                if screening { screeningStage }
                else {
                    HStack(spacing: 0) {
                        reviewStage
                        DirectionDivider(vertical: true)
                        InspectorView(model: model).frame(width: Metrics.sidebar)
                    }
                }
            }
        }
        .background { Gate.Surface.ground.overlay { GrainOverlay() } }
        .foregroundStyle(Gate.Text.primary).tint(Gate.Text.primary)
        .onChange(of: model.commentFocusRequest) { _, _ in screening = false }
        .onChange(of: model.notesNavigationRequest) { _, _ in screening = false }
        .onChange(of: model.selectedCommentID) { _, id in if id != nil { screening = false } }
        .onChange(of: model.projectURL) { _, _ in screening = false }
        .onExitCommand { screening = false }
        .frame(minWidth: 980, minHeight: 660)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $model.showTools) { AgentToolsSheet(model: model) }
        .sheet(isPresented: $model.showExport) { ExportSheet(model: model) }
        .sheet(isPresented: $model.showActivity) { ActivitySheet(model: model) }
        .overlay(alignment: .bottomTrailing) {
            if let error = model.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Gate.State.alert)
                    Text(error).textSelection(.enabled).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    IconButton(symbol: "xmark", label: "Dismiss error") { model.error = nil }
                }.padding(16).background { GateGlassSurface() }.frame(maxWidth: 480).padding(24)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            projectMenu.padding(.leading, 76)
            if model.project != nil {
                Text("/").foregroundStyle(Gate.Text.disabled)
                Text(model.cutLabel).font(Gate.Font.caption).foregroundStyle(Gate.Text.secondary).lineLimit(1)
                Spacer(minLength: 12)
                roomSwitcher
                Spacer(minLength: 12)
                if let job = model.activeJobs.first {
                    HStack(spacing: 6) {
                        Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundStyle(Gate.Voice.agent)
                        Text(job.phase).font(Gate.Font.caption).lineLimit(1)
                    }.foregroundStyle(Gate.Voice.agent)
                } else if model.busyCount > 0 { ProgressView().controlSize(.small) }
                else if model.pendingUpdate {
                    Button("Cut ready", action: model.followWorkingCut).buttonStyle(GhostButton())
                        .foregroundStyle(Gate.Voice.director)
                }
                if !model.isWorkingCut {
                    Button("Latest cut", action: model.followWorkingCut).buttonStyle(GhostButton())
                }
                Menu {
                    Button("Bring footage…", action: model.chooseMedia)
                    Button("Transcript") { screening = false; model.panel = .transcript }
                    if (model.project?.sequences.count ?? 0) > 1 {
                        Menu("Sequences") {
                            ForEach(model.project?.sequences ?? []) { sequence in
                                Button(sequence.name) { model.selectSequence(sequence.id) }
                            }
                        }
                    }
                    Divider()
                    Button("Agent tools…") { model.showTools = true }
                    Button("Activity…") { model.showActivity = true }
                    Divider()
                    Button("Save cut", action: model.saveCut).disabled(model.duration == 0)
                    if model.pinnedRevision != nil { Button("Restore this cut", action: model.restoreDisplayed) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 28, height: 30)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Project actions").accessibilityLabel("Project actions")
                Button { model.showExport = true } label: {
                    Label("Export", systemImage: "arrow.up.right")
                }.buttonStyle(QuietButton()).disabled(model.duration == 0)
            } else {
                Spacer()
                Button("Open project", action: model.chooseProject).buttonStyle(GhostButton())
            }
        }.padding(.trailing, 16).frame(height: 48)
            .background { Gate.Surface.ground.overlay { GrainOverlay() } }
    }

    private var roomSwitcher: some View {
        HStack(spacing: 2) {
            roomButton("Dailies", selected: !screening && model.panel == .media) {
                screening = false; model.panel = .media
            }
            roomButton("Screening", selected: screening) {
                screening = true; model.annotating = false
            }
            roomButton("Notes", selected: !screening && model.panel != .media) {
                screening = false; model.panel = .feedback
            }
        }.padding(2).background(Gate.Surface.canvas, in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Gate.Line.subtle, lineWidth: 1) }
            .accessibilityElement(children: .contain).accessibilityLabel("Room")
    }

    private func roomButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : Gate.Motion.glide) { action() }
        } label: {
            Text(title).font(Gate.Font.control).foregroundStyle(selected ? Gate.Text.primary : Gate.Text.tertiary)
                .padding(.horizontal, 10).frame(height: 26)
                .background(selected ? Gate.Surface.raised : .clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay { if selected { RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.subtle, lineWidth: 1) } }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var projectMenu: some View {
        Menu {
            Button("New Project…", action: model.createProject)
            Button("Open Project…", action: model.chooseProject)
            if !model.recentProjects.isEmpty {
                Divider()
                ForEach(model.recentProjects.filter(\.available)) { entry in
                    Button(entry.name) { model.open(URL(fileURLWithPath: entry.path)) }
                }
            }
            if let url = model.projectURL { Divider(); Button("Reveal Project") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
        } label: {
            Text(model.project?.name ?? "Direction").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
        }.menuStyle(.borderlessButton).frame(maxWidth: 200, alignment: .leading).fixedSize(horizontal: true, vertical: false)
    }

    private var reviewStage: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(model.sequence?.name ?? model.cutLabel).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                Spacer()
                if let sequence = model.sequence {
                    Text("\(sequence.width) × \(sequence.height)").font(Gate.Font.caption).foregroundStyle(Gate.Text.disabled)
                }
                IconButton(symbol: "viewfinder", label: "Mark a frame region", selected: model.annotating) {
                    model.toggleRegionAnnotation()
                }.disabled(model.duration == 0)
            }.frame(height: 24)
            VideoReviewView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.frame))
            ReviewTimeline(model: model)
        }.padding(Gate.Space.s6).frame(minWidth: 450)
            .background(Gate.Surface.canvas)
    }

    private var screeningStage: some View {
        ZStack(alignment: .bottom) {
            VideoReviewView(model: model, showsAnnotations: false)
                .padding(.top, Gate.Space.s14).padding(.bottom, 148)
            ReviewTimeline(model: model, steelPlayback: true)
                .background { GateGlassSurface(cornerRadius: 14) }
                .frame(maxWidth: 880).padding(.horizontal, 32).padding(.bottom, 20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Gate.Surface.canvas)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            BrandIcon(size: 140).shadow(color: .black.opacity(0.6), radius: 25, y: 14)
            Text("What are we making?").font(Gate.Font.room).foregroundStyle(Gate.Text.primary).padding(.top, 20)
            Text("Start a project, then bring the footage.").font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.top, 10)
            HStack(spacing: 10) {
                Button(action: model.createProject) { Label("New project", systemImage: "plus") }.buttonStyle(QuietButton(prominent: true))
                Button("Open project", action: model.chooseProject).buttonStyle(QuietButton())
            }.padding(.top, 26)
            if !model.recentProjects.filter(\.available).isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Recent projects").padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(model.recentProjects.filter(\.available).prefix(3))) { entry in
                            Button { model.open(URL(fileURLWithPath: entry.path)) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "film.stack").foregroundStyle(Palette.muted)
                                    Text(entry.name).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Palette.faint)
                                }.font(.system(size: 12)).padding(14).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if entry.id != model.recentProjects.filter(\.available).prefix(3).last?.id { DirectionDivider().padding(.horizontal, 14) }
                        }
                    }.directionSurface()
                }.frame(width: 380).padding(.top, 36)
            }
            Spacer(minLength: 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Gate.Surface.ground.overlay { GrainOverlay() } }
    }
}

struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { let view = AVPlayerView(); view.player = player; view.controlsStyle = .none; view.videoGravity = .resizeAspect; view.allowsVideoFrameAnalysis = false; return view }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
}

struct VideoReviewView: View {
    @Bindable var model: EditorModel
    var showsAnnotations = true
    var body: some View {
        ZStack {
            Color.black
            if model.duration > 0 {
                ZStack {
                    NativePlayerView(player: model.player).allowsHitTesting(false)
                    GeometryReader { proxy in
                        if showsAnnotations, let region = model.commentRegion {
                            RoundedRectangle(cornerRadius: Gate.Radius.frame).stroke(Gate.Voice.director, lineWidth: 2).frame(width: proxy.size.width * region.width, height: proxy.size.height * region.height).position(x: proxy.size.width * (region.x + region.width / 2), y: proxy.size.height * (region.y + region.height / 2)).allowsHitTesting(false)
                        }
                        if showsAnnotations, model.annotating {
                            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 1).onChanged { value in
                                let a = value.startLocation, b = value.location, size = proxy.size
                                let x = max(0, min(1, min(a.x,b.x) / size.width)), y = max(0, min(1, min(a.y,b.y) / size.height))
                                model.commentRegion = .init(x: x, y: y, width: min(1-x, abs(a.x-b.x) / size.width), height: min(1-y, abs(a.y-b.y) / size.height))
                            })
                        }
                    }
                }.aspectRatio(CGFloat(model.sequence?.width ?? 1920) / CGFloat(model.sequence?.height ?? 1080), contentMode: .fit)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Palette.silver)
                    Text("Bring the footage").font(Gate.Font.room)
                    Text("Your originals stay where they are.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Button(action: model.chooseMedia) { Label("Add media", systemImage: "plus") }
                        .buttonStyle(QuietButton()).padding(.top, 4).accessibilityLabel("Add media to empty project")
                }
            }
            if model.isPreparing {
                VStack(spacing: 8) { ProgressView().controlSize(.small); Text("Preparing preview").font(.system(size: 11)) }
                    .padding(16).directionSurface(elevated: true)
            }
        }.overlay(alignment: .topLeading) {
            if showsAnnotations, model.annotating { Text("Drag over the frame to place your note").font(Gate.Font.caption).padding(10).background { GateGlassSurface(cornerRadius: 8) }.padding(20) }
        }
    }
}
