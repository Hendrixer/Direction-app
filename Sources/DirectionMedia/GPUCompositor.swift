import Foundation
@preconcurrency import AVFoundation
import CoreImage
import Metal
import Synchronization
import DirectionCore

public struct RenderLayer: @unchecked Sendable {
    public let trackID: CMPersistentTrackID?
    public let image: CIImage?
    public let transform: CGAffineTransform
    public let grade: ColorGrade
    public let framing: Framing
    let clip: Clip
    /// When it shows, in cut seconds: its own range plus any dissolve handles.
    let start: Double
    let end: Double
    /// The transition into the next clip on its track, which this clip's tail plays into.
    let outgoing: ClipTransition?
    let trackEffects: [ClipEffect]
    let aboveLook: Bool
    let lut: CameraLUTFile?
}

/// What every frame of one compiled cut shares: the director's look, the rate and the cut's own size.
public final class RenderSettings: @unchecked Sendable {
    let looks: LookContext?
    let fps: Double
    let size: CGSize
    /// Stands in for LookPipeline.apply, so tests can see what lands under the look and what over it.
    let look: (@Sendable (CIImage, String?, Int) -> CIImage)?
    init(looks: LookContext?, fps: Double, size: CGSize, look: (@Sendable (CIImage, String?, Int) -> CIImage)? = nil) { self.looks = looks; self.fps = fps; self.size = size; self.look = look }
}

public final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = true
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    public let requiredSourceTrackIDs: [NSValue]?
    public let layers: [RenderLayer]
    let settings: RenderSettings
    init(range: CMTimeRange, layers: [RenderLayer], timingTrackID: CMPersistentTrackID? = nil, settings: RenderSettings) {
        timeRange = range; self.layers = layers; self.settings = settings
        requiredSourceTrackIDs = (layers.compactMap(\.trackID) + (timingTrackID.map { [$0] } ?? [])).map { NSNumber(value: $0) }
        super.init()
    }
}

/// Composites one frame (agent-timeline.md › What Direction renders): each clip's effects, its track's
/// effects, layers bottom to top with their blend modes, the director's look, then whatever sits above it.
public final class GPUCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    public static var deviceName: String? { MTLCreateSystemDefaultDevice()?.name }
    private let queue = DispatchQueue(label: "dev.direction.gpu", qos: .userInteractive)
    private let context: CIContext
    private let renderState = Mutex<AVVideoCompositionRenderContext?>(nil)
    private let generation = Mutex(0)
    /// Each track's last frame and when it showed. A sub-frame gap at a cut (speed changes, a held edge) can leave a
    /// moment with no source frame; the track holds its last one there instead of failing the whole export
    /// (DIRECTION-B). A frame missing longer than `holdLimit`, or mid-shot with nothing to hold, still fails: that's a
    /// take that can't decode there, not a sliver.
    private static let holdLimit = 0.5
    private let lastFrames = Mutex<[CMPersistentTrackID: HeldFrame]>([:])
    /// A source frame kept for its track; only the render queue reads it.
    private final class HeldFrame: @unchecked Sendable { let buffer: CVPixelBuffer, time: Double; init(_ b: CVPixelBuffer, at t: Double) { buffer = b; time = t } }
    private let outputSpace = CGColorSpace(name: CGColorSpace.itur_709)!
    public override init() {
        if let device = MTLCreateSystemDefaultDevice() { context = CIContext(mtlDevice: device, options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false]) }
        else { context = CIContext(options: [.useSoftwareRenderer: false]) }
        super.init()
    }
    public var sourcePixelBufferAttributes: [String: any Sendable]? { [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA], kCVPixelBufferMetalCompatibilityKey as String: true] }
    public var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true] }
    public var supportsWideColorSourceFrames: Bool { false }
    public var supportsHDRSourceFrames: Bool { false }
    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) { renderState.withLock { $0 = newRenderContext } }
    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let current = generation.withLock { $0 }
        queue.async { [self] in
            guard current == generation.withLock({ $0 }) else { request.finishCancelledRequest(); return }
            guard let instruction = request.videoCompositionInstruction as? RenderInstruction, let renderContext = renderState.withLock({ $0 }), let buffer = renderContext.newPixelBuffer() else { request.finish(with: DirectionError("render_failed", "Cannot allocate a video render buffer.")); return }
            let bounds = CGRect(origin: .zero, size: renderContext.size)
            let settings = instruction.settings
            let t = request.compositionTime.seconds
            let frameIndex = Int((t * settings.fps + 1e-4).rounded(.down))
            let scale = bounds.width / max(1, settings.size.width)
            var below = CIImage(color: .black).cropped(to: bounds), above: [(CIImage, String)] = [], story: String?
            // Each track composites on its own (a dissolve is two clips on one track), then blends onto what's under it.
            var groups: [[RenderLayer]] = []
            for layer in instruction.layers where t >= layer.start - 1e-6 && t < layer.end - 1e-6 {
                if let last = groups.last?.last, last.clip.layer == layer.clip.layer, last.aboveLook == layer.aboveLook { groups[groups.count - 1].append(layer) } else { groups.append([layer]) }
            }
            for group in groups {
                var track = CIImage.empty()
                for layer in group {
                    let original: CIImage
                    if let image = layer.image { original = image }
                    else if let id = layer.trackID, let frame = request.sourceFrame(byTrackID: id) {
                        let held = HeldFrame(frame, at: t); lastFrames.withLock { $0[id] = held }
                        original = CIImage(cvPixelBuffer: frame)
                    } else if let id = layer.trackID, let held = lastFrames.withLock({ $0[id] }), abs(t - held.time) <= Self.holdLimit {
                        original = CIImage(cvPixelBuffer: held.buffer)
                    } else if layer.trackID != nil, min(t - layer.start, layer.end - t) <= 1 / max(1, settings.fps) + 1e-4 {
                        continue  // A sliver at the shot's edge with nothing yet to hold: what's under it shows.
                    } else { request.finish(with: DirectionError("missing_frame", "A source frame is unavailable for this edit.")); return }
                    let picture = ClipRendering.render(layer, source: original, t: t, frameIndex: frameIndex, bounds: bounds, scale: scale)
                    // A push, a wipe or the editor's own transition draws the two shots together.
                    if let tr = layer.clip.transition, let progress = ClipRendering.progress(tr, cut: layer.clip.start.seconds, t: t) {
                        track = TransitionShader.apply(from: track, to: picture, progress: progress, transition: tr, bounds: bounds)
                    } else if let tr = layer.clip.transition, ClipRendering.dissolved(tr, cut: layer.clip.start.seconds, t: t) != nil {
                        // A dissolve adds the two shots at their shares, so where one has no picture the other still fades.
                        track = picture.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: track])
                    } else { track = picture.composited(over: track) }
                    if layer.clip.layer == 0 && layer.clip.range.contains(.init(seconds: t)) { story = layer.clip.assetID }
                }
                guard let top = group.last else { continue }
                if !top.trackEffects.isEmpty { track = ClipRendering.apply(top.trackEffects, to: track.cropped(to: bounds), at: t, frameIndex: frameIndex, bounds: bounds, scale: scale) }
                let mode = top.clip.layer == 0 ? "normal" : top.clip.blend ?? "normal"
                if top.aboveLook { above.append((track, mode)) } else { below = ClipRendering.blend(track, over: below, mode: mode).cropped(to: bounds) }
            }
            var output = (settings.look?(below, story, frameIndex) ?? LookPipeline.apply(below, context: settings.looks, storyAssetID: story, frameIndex: frameIndex)).cropped(to: bounds)
            for (image, mode) in above { output = ClipRendering.blend(image, over: output, mode: mode).cropped(to: bounds) }
            context.render(output, to: buffer, bounds: bounds, colorSpace: outputSpace)
            if current != generation.withLock({ $0 }) { request.finishCancelledRequest() } else { request.finish(withComposedVideoFrame: buffer) }
        }
    }
    public func cancelAllPendingVideoCompositionRequests() { generation.withLock { $0 += 1 } }
}
