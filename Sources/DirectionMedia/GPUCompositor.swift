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
}

public final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = true
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    public let requiredSourceTrackIDs: [NSValue]?
    public let layers: [RenderLayer]
    public init(range: CMTimeRange, layers: [RenderLayer], timingTrackID: CMPersistentTrackID? = nil) {
        timeRange = range; self.layers = layers
        requiredSourceTrackIDs = (layers.compactMap(\.trackID) + (timingTrackID.map { [$0] } ?? [])).map { NSNumber(value: $0) }
        super.init()
    }
}

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
            var output = CIImage(color: .black).cropped(to: bounds)
            for layer in instruction.layers {
                let original: CIImage
                if let image = layer.image { original = image }
                else if let track = layer.trackID, let frame = request.sourceFrame(byTrackID: track) { original = CIImage(cvPixelBuffer: frame) }
                else { request.finish(with: DirectionError("missing_frame", "A source frame is unavailable for this edit.")); return }
                var image = original.transformed(by: layer.transform)
                let extent = image.extent
                guard extent.width > 0, extent.height > 0 else { continue }
                image = image.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
                let ratio = (layer.framing.fit ? min(bounds.width / extent.width, bounds.height / extent.height) : max(bounds.width / extent.width, bounds.height / extent.height)) * layer.framing.scale
                image = image.transformed(by: .init(scaleX: ratio, y: ratio))
                image = image.transformed(by: .init(translationX: (bounds.width - extent.width * ratio) / 2 + layer.framing.offsetX * bounds.width, y: (bounds.height - extent.height * ratio) / 2 - layer.framing.offsetY * bounds.height))
                let g = layer.grade
                if g.exposure != 0 { image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": g.exposure]) }
                if g.temperature != 0 || g.tint != 0 { image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + g.temperature, y: g.tint)]) }
                if g.contrast != 1 || g.saturation != 1 { image = image.applyingFilter("CIColorControls", parameters: ["inputContrast": g.contrast, "inputSaturation": g.saturation]) }
                if layer.framing.opacity < 1 { image = image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.framing.opacity)]) }
                output = image.cropped(to: bounds).composited(over: output)
            }
            context.render(output, to: buffer, bounds: bounds, colorSpace: outputSpace)
            if current != generation.withLock({ $0 }) { request.finishCancelledRequest() } else { request.finish(withComposedVideoFrame: buffer) }
        }
    }
    public func cancelAllPendingVideoCompositionRequests() { generation.withLock { $0 += 1 } }
}
