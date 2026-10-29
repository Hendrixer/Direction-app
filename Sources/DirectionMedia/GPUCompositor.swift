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
    init(looks: LookContext?, fps: Double, size: CGSize) { self.looks = looks; self.fps = fps; self.size = size }
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
                    else if let id = layer.trackID, let frame = request.sourceFrame(byTrackID: id) { original = CIImage(cvPixelBuffer: frame) }
                    else { request.finish(with: DirectionError("missing_frame", "A source frame is unavailable for this edit.")); return }
                    track = ClipRendering.render(layer, source: original, t: t, frameIndex: frameIndex, bounds: bounds, scale: scale).composited(over: track)
                    if layer.clip.layer == 0 && layer.clip.range.contains(.init(seconds: t)) { story = layer.clip.assetID }
                }
                guard let top = group.last else { continue }
                if !top.trackEffects.isEmpty { track = ClipRendering.apply(top.trackEffects, to: track.cropped(to: bounds), at: t, frameIndex: frameIndex, bounds: bounds, scale: scale) }
                let mode = top.clip.layer == 0 ? "normal" : top.clip.blend ?? "normal"
                if top.aboveLook { above.append((track, mode)) } else { below = ClipRendering.blend(track, over: below, mode: mode).cropped(to: bounds) }
            }
            var output = LookPipeline.apply(below, context: settings.looks, storyAssetID: story, frameIndex: frameIndex).cropped(to: bounds)
            for (image, mode) in above { output = ClipRendering.blend(image, over: output, mode: mode).cropped(to: bounds) }
            context.render(output, to: buffer, bounds: bounds, colorSpace: outputSpace)
            if current != generation.withLock({ $0 }) { request.finishCancelledRequest() } else { request.finish(withComposedVideoFrame: buffer) }
        }
    }
    public func cancelAllPendingVideoCompositionRequests() { generation.withLock { $0 += 1 } }
}
