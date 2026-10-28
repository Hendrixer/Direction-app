import SwiftUI
import AppKit
import AVKit
import DirectionCore

struct EditorView: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            header
            DirectionDivider()
            if model.project == nil { welcome }
            else {
                HStack(spacing: 0) {
                    reviewStage
                    DirectionDivider(vertical: true)
                    InspectorView(model: model).frame(width: Metrics.sidebar)
                }
            }
        }
        .background(Palette.background).foregroundStyle(Palette.text).tint(Palette.accent)
        .frame(minWidth: 980, minHeight: 660)
        .sheet(isPresented: $model.showTools) { AgentToolsSheet(model: model) }
        .sheet(isPresented: $model.showExport) { ExportSheet(model: model) }
        .sheet(isPresented: $model.showActivity) { ActivitySheet(model: model) }
        .overlay(alignment: .bottom) {
            if let error = model.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.marker)
                    Text(error).textSelection(.enabled).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    IconButton(symbol: "xmark", label: "Dismiss error") { model.error = nil }
                }.padding(14).directionSurface(elevated: true).shadow(color: .black.opacity(0.4), radius: 16, y: 8).padding(22)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                BrandIcon(size: 30)
                Text("Direction").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
            }.padding(.leading, 76)
            if model.project != nil {
                projectMenu
                if (model.project?.sequences.count ?? 0) > 1 {
                    Menu {
                        ForEach(model.project?.sequences ?? []) { sequence in Button(sequence.name) { model.selectSequence(sequence.id) } }
                    } label: {
                        Text(model.sequence?.name ?? "Edit").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                if !model.isWorkingCut {
                    Button("Back to latest") { model.followWorkingCut() }.buttonStyle(QuietButton())
                }
            }
            Spacer(minLength: 8)
            if let job = model.activeJobs.first {
                ProgressView().controlSize(.small)
                Text(job.phase).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            } else if model.busyCount > 0 { ProgressView().controlSize(.small) }
            if model.project != nil {
                Button(action: model.chooseMedia) { Label("Add media", systemImage: "plus") }.buttonStyle(QuietButton())
                Menu {
                    Button("Agent tools…") { model.showTools = true }
                    Button("Activity…") { model.showActivity = true }
                    Divider()
                    Button("Save cut", action: model.saveCut).disabled(model.duration == 0)
                    if model.pinnedRevision != nil { Button("Restore this edit", action: model.restoreDisplayed) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 28, height: 34)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Project actions").accessibilityLabel("Project actions")
                Button { model.showExport = true } label: {
                    Label("Export", systemImage: "arrow.up.right")
                }.buttonStyle(QuietButton(prominent: true)).disabled(model.duration == 0)
            } else {
                Button("Open project", action: model.chooseProject).buttonStyle(QuietButton())
            }
        }.padding(.trailing, 24).frame(height: 56)
            .background(Palette.background)
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
            Text(model.project?.name ?? "Direction").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
        }.menuStyle(.borderlessButton).frame(maxWidth: 220, alignment: .leading).fixedSize(horizontal: true, vertical: false)
    }

    private var reviewStage: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(model.cutLabel).font(.system(size: 12, weight: .medium))
                Text("·").foregroundStyle(Palette.faint)
                Text("Revision \(model.displayedProject?.editRevision ?? 0)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                if let sequence = model.sequence {
                    Text("\(sequence.width) × \(sequence.height)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                IconButton(symbol: "viewfinder", label: "Mark a frame region", selected: model.annotating) {
                    model.annotating.toggle()
                    model.panel = .feedback
                    model.player.pause(); model.playing = false
                }.disabled(model.duration == 0)
            }.frame(height: 28).padding(.horizontal, 4)
            VideoReviewView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            ReviewTimeline(model: model)
        }.padding(24).frame(minWidth: 450)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            BrandIcon(size: 140).shadow(color: .black.opacity(0.6), radius: 25, y: 14)
            Text("Your next cut.").font(.system(size: 38, weight: .light)).tracking(-1.6).foregroundStyle(Palette.silver).padding(.top, 20)
            Text("Start a project. Bring it into focus.").font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.top, 10)
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
            .background {
                ZStack {
                    Palette.background
                    RadialGradient(colors: [Color(white: 0.10), Palette.background], center: .init(x: 0.5, y: 0.38), startRadius: 0, endRadius: 500)
                }
            }
    }
}

struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { let view = AVPlayerView(); view.player = player; view.controlsStyle = .none; view.videoGravity = .resizeAspect; view.allowsVideoFrameAnalysis = false; return view }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
}

struct VideoReviewView: View {
    @Bindable var model: EditorModel
    var body: some View {
        ZStack {
            Color.black
            if model.duration > 0 {
                ZStack {
                    NativePlayerView(player: model.player).allowsHitTesting(false)
                    GeometryReader { proxy in
                        if let region = model.commentRegion {
                            RoundedRectangle(cornerRadius: 3).stroke(Palette.accent, lineWidth: 2).background(Palette.accent.opacity(0.06)).frame(width: proxy.size.width * region.width, height: proxy.size.height * region.height).position(x: proxy.size.width * (region.x + region.width / 2), y: proxy.size.height * (region.y + region.height / 2)).allowsHitTesting(false)
                        }
                        if model.annotating {
                            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 1).onChanged { value in
                                let a = value.startLocation, b = value.location, size = proxy.size
                                let x = max(0, min(1, min(a.x,b.x) / size.width)), y = max(0, min(1, min(a.y,b.y) / size.height))
                                model.commentRegion = .init(x: x, y: y, width: min(1-x, abs(a.x-b.x) / size.width), height: min(1-y, abs(a.y-b.y) / size.height))
                            })
                        }
                    }
                }.aspectRatio(CGFloat(model.sequence?.width ?? 1920) / CGFloat(model.sequence?.height ?? 1080), contentMode: .fit).padding(16)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Palette.silver)
                    Text("Bring your footage into the frame").font(.system(size: 15, weight: .medium))
                    Text("Import video, audio, or stills to start this cut.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Button(action: model.chooseMedia) { Label("Add media", systemImage: "plus") }
                        .buttonStyle(QuietButton()).padding(.top, 4).accessibilityLabel("Add media to empty project")
                }
            }
            if model.isPreparing {
                VStack(spacing: 8) { ProgressView().controlSize(.small); Text("Preparing preview").font(.system(size: 11)) }
                    .padding(16).directionSurface(elevated: true)
            }
        }.overlay(alignment: .topLeading) {
            if model.pendingUpdate { Button("Updated edit available") { model.followWorkingCut() }.buttonStyle(QuietButton(prominent: true)).padding(20) }
            else if model.annotating { Text("Drag over the frame to mark your feedback").font(.system(size: 11)).padding(10).directionSurface(elevated: true).padding(20) }
        }
    }
}
