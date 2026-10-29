import Foundation
import CoreImage
import Metal
import QuartzCore
import Synchronization
import DirectionCore

/// The editor's own effects (agent-timeline.md › Custom effects): a Metal function in `Effects/<name>.metal`,
/// compiled at runtime with `makeLibrary(source:)` and run through a CIImageProcessorKernel. Before use it
/// renders 3 frames at 1080p and is refused if it's slower than 40 ms a frame or makes NaN.
public enum ShaderEffect {
    final class Compiled: @unchecked Sendable {
        let key: String
        let pipeline: MTLComputePipelineState
        let params: [ShaderParam]
        let usesSampler: Bool
        init(key: String, pipeline: MTLComputePipelineState, params: [ShaderParam], usesSampler: Bool) { self.key = key; self.pipeline = pipeline; self.params = params; self.usesSampler = usesSampler }
    }
    static let compiled = Mutex<[String: Compiled]>([:])
    static let device = MTLCreateSystemDefaultDevice()

    /// Core Image's kernel vocabulary, enough for color and sampler kernels written the CI way.
    /// `#line 1` makes compiler errors name the editor's own lines.
    static let prelude = """
    #include <metal_stdlib>
    using namespace metal;
    #define stitchable
    namespace coreimage {
        typedef half4 sample_h;
        typedef float4 sample_t;
        struct destination { float2 c; float2 coord() const { return c; } };
        struct sampler {
            texture2d<half, access::sample> tex; float4 geo; float2 here;
            float4 sample(float2 p) const { constexpr metal::sampler s(coord::pixel, filter::linear, address::clamp_to_edge); return float4(tex.sample(s, float2(p.x - geo.x, geo.y - p.y))); }
            float2 coord() const { return here; }
            float2 transform(float2 p) const { return p; }
            float4 extent() const { return float4(geo.x, geo.y - float(tex.get_height()), float(tex.get_width()), float(tex.get_height())); }
        };
        inline float4 premultiply(float4 c) { return float4(c.rgb * c.a, c.a); }
        inline float4 unpremultiply(float4 c) { return c.a > 0 ? float4(c.rgb / c.a, c.a) : c; }
    }
    #line 1

    """

    static func invalid(_ m: String) -> DirectionError { .init("shader_invalid", m) }

    /// The stitchable function and how to call it: what its first argument is and whether it takes the destination.
    static func signature(_ source: String, _ params: [ShaderParam]) throws -> (name: String, sampler: Bool, dest: Bool) {
        let pattern = #"\[\[\s*stitchable\s*\]\]\s*(half4|float4)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)"#
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let nameRange = Range(m.range(at: 2), in: source), let argRange = Range(m.range(at: 3), in: source) else { throw invalid("Write one `[[ stitchable ]] half4 effect(coreimage::sample_h s, …, coreimage::destination dest)` function.") }
        var args = source[argRange].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = args.first, first.contains("sample_h") || first.contains("sample_t") || first.contains("sampler") else { throw invalid("The function's first argument is coreimage::sample_h (one pixel) or coreimage::sampler.") }
        args.removeFirst()
        let dest = args.last?.contains("destination") ?? false
        if dest { args.removeLast() }
        guard args.count == params.count else { throw invalid("The function takes \(args.count) parameters after the pixel, but the header declares \(params.count). Declare each with `// direction: param`.") }
        for (a, p) in zip(args, params) {
            let isVector = a.contains("float3") || a.contains("half3")
            guard (p.kind == "color") == isVector, a.contains("float") || a.contains("half") else { throw invalid("\(p.name) is \(p.kind == "color" ? "a color: float3" : "a number: float") in the function's arguments, in the header's order.") }
        }
        return (String(source[nameRange]), first.contains("sampler"), dest)
    }

    static func compile(_ source: String) throws -> Compiled {
        let key = AudioProcessor.digest(Data(source.utf8))
        if let c = compiled.withLock({ $0[key] }) { return c }
        guard let device else { throw DirectionError("metal_unavailable", "Direction requires a Metal-capable Mac.") }
        guard source.utf8.count <= 64_000 else { throw invalid("Keep a shader under 64 KB.") }
        // Shaders see pixels and their parameters, nothing else.
        for (n, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#include") || t.hasPrefix("#import") || t.hasPrefix("#line") || t.hasPrefix("#pragma") { throw invalid("Line \(n + 1): shaders can't include files; metal_stdlib and Core Image's kernel types are already there.") }
        }
        let params = try ShaderHeader.params(source)
        let sig = try signature(source, params)
        var call: [String] = [sig.sampler ? "sm" : "s"], k = 0
        for p in params { if p.kind == "color" { call.append("float3(p[\(k)], p[\(k + 1)], p[\(k + 2)])"); k += 3 } else { call.append("p[\(k)]"); k += 1 } }
        if sig.dest { call.append("dest") }
        let kernel = """

        kernel void direction_effect_main(texture2d<half, access::sample> src [[texture(0)]], texture2d<half, access::write> dst [[texture(1)]], constant float *p [[buffer(0)]], constant float4 &geo [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
            float2 here = float2(geo.z + float(gid.x) + 0.5, geo.w - float(gid.y) - 0.5);
            coreimage::destination dest; dest.c = here;
            \(sig.sampler ? "coreimage::sampler sm = { src, geo, here };" : "half4 s = src.read(uint2(clamp(here.x - geo.x, 0.0, float(src.get_width() - 1)), clamp(geo.y - here.y, 0.0, float(src.get_height() - 1))));")
            dst.write(half4(\(sig.name)(\(call.joined(separator: ", ")))), gid);
        }
        """
        let library: MTLLibrary
        do { library = try device.makeLibrary(source: prelude + source + kernel, options: MTLCompileOptions()) }
        catch {
            let lines = String(describing: (error as NSError).localizedDescription).split(separator: "\n").filter { $0.contains("error:") }.prefix(8)
            throw invalid("The shader doesn't compile:\n" + lines.map { $0.replacingOccurrences(of: "program_source:", with: "line ") }.joined(separator: "\n"))
        }
        guard let function = library.makeFunction(name: "direction_effect_main") else { throw invalid("The shader doesn't compile.") }
        let pipeline: MTLComputePipelineState
        do { pipeline = try device.makeComputePipelineState(function: function) } catch { throw invalid("The shader doesn't build: \(error.localizedDescription)") }
        let c = Compiled(key: key, pipeline: pipeline, params: params, usesSampler: sig.sampler)
        compiled.withLock { $0[key] = c }
        return c
    }
    /// Compiles a shader and returns the parameters its header declares.
    public static func declared(source: String) throws -> [ShaderParam] { try compile(source).params }

    /// Runs a compiled shader over an image with its parameters at time `t` (source seconds for a clip's keys).
    static func apply(_ image: CIImage, effect: ClipEffect, at t: Double?) -> CIImage {
        guard let source = effect.source, let c = try? compile(source) else { return image }
        return apply(image, compiled: c, values: values(c.params, effect, at: t))
    }
    static func values(_ params: [ShaderParam], _ effect: ClipEffect, at t: Double?) -> [Float] {
        params.flatMap { p -> [Float] in
            if p.kind == "color" { let (r, g, b) = ShaderHeader.rgb(effect.params[p.name]?.string ?? p.defaultValue.string ?? "#FFFFFF") ?? (1, 1, 1); return [Float(r), Float(g), Float(b)] }
            return [Float(effect.number(p.name, at: t, default: p.defaultValue.double ?? 0))]
        }
    }
    static func apply(_ image: CIImage, compiled c: Compiled, values: [Float]) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.width < 20_000, extent.height < 20_000 else { return image }
        let data = values.isEmpty ? Data(count: 4) : values.withUnsafeBufferPointer { Data(buffer: $0) }
        return (try? ShaderKernel.apply(withExtent: extent, inputs: [image], arguments: ["key": c.key, "values": data, "sampler": c.usesSampler, "extent": CIVector(cgRect: extent)])) ?? image
    }

    /// Compiles and times a shader: 3 frames at 1080p after one warm-up of the test picture.
    /// Returns the declared parameters and the time per frame.
    public static func check(source: String, params: [String: JSONValue] = [:]) throws -> JSONValue {
        let c = try compile(source)
        guard let device, let queue = device.makeCommandQueue() else { throw DirectionError("metal_unavailable", "Direction requires a Metal-capable Mac.") }
        let size = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let gradient = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 1920, y: 1080), "inputColor0": CIColor(red: 0.9, green: 0.2, blue: 0.1), "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.9)])!.outputImage!
        let checks = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 40, "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.25), "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)])!.outputImage!
        let test = checks.composited(over: gradient).cropped(to: size)
        let context = CIContext(mtlDevice: device, options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1920, height: 1080, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]; descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw DirectionError("render_failed", "Can't allocate a test frame.") }
        let effect = ClipEffect(name: "shader", params: params, source: source)
        func render(_ image: CIImage) throws -> Double {
            guard let buffer = queue.makeCommandBuffer() else { throw DirectionError("render_failed", "Can't render a test frame.") }
            let started = CACurrentMediaTime()
            _ = try context.startTask(toRender: image, to: CIRenderDestination(mtlTexture: texture, commandBuffer: buffer))
            if !device.hasUnifiedMemory, let blit = buffer.makeBlitCommandEncoder() { blit.synchronize(resource: texture); blit.endEncoding() }
            buffer.commit(); buffer.waitUntilCompleted()
            return CACurrentMediaTime() - started
        }
        _ = try render(test)
        var times: [Double] = []
        for frame in 0..<3 { times.append(try render(apply(test, compiled: c, values: values(c.params, effect, at: Double(frame) / 24)))) }
        let ms = times.sorted()[1] * 1_000
        guard ms <= 40 else { throw DirectionError("shader_too_slow", "The shader takes \(Int(ms.rounded())) ms a frame at 1080p; it has to be under 40.") }
        // Any NaN or infinity in the last frame refuses it.
        var row = [UInt16](repeating: 0, count: 1920 * 4)
        for y in stride(from: 0, to: 1080, by: 1) {
            row.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 1920 * 8, from: MTLRegionMake2D(0, y, 1920, 1), mipmapLevel: 0) }
            if row.contains(where: { $0 & 0x7C00 == 0x7C00 }) { throw DirectionError("shader_invalid", "The shader makes NaN or infinite values (row \(y) of the test frame).") }
        }
        return .object(["msPerFrame": .number((ms * 10).rounded() / 10), "frames": .number(3), "size": .string("1920×1080"), "params": (try? .wrapping(c.params)) ?? .array([])])
    }
}

final class ShaderKernel: CIImageProcessorKernel {
    override class var outputFormat: CIFormat { .RGBAh }
    override class func formatForInput(at input: Int32) -> CIFormat { .RGBAh }
    override class func roi(forInput input: Int32, arguments: [String: Any]?, outputRect: CGRect) -> CGRect {
        if arguments?["sampler"] as? Bool == true, let e = arguments?["extent"] as? CIVector { return e.cgRectValue }
        return outputRect
    }
    override class func process(with inputs: [CIImageProcessorInput]?, arguments: [String: Any]?, output: CIImageProcessorOutput) throws {
        guard let input = inputs?.first, let source = input.metalTexture, let target = output.metalTexture, let buffer = output.metalCommandBuffer,
              let key = arguments?["key"] as? String, let c = ShaderEffect.compiled.withLock({ $0[key] }), let data = arguments?["values"] as? Data,
              let encoder = buffer.makeComputeCommandEncoder() else { throw DirectionError("render_failed", "The shader couldn't run.") }
        encoder.setComputePipelineState(c.pipeline)
        encoder.setTexture(source, index: 0); encoder.setTexture(target, index: 1)
        data.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: max(4, data.count), index: 0) }
        var geo = SIMD4<Float>(Float(input.region.minX), Float(input.region.maxY), Float(output.region.minX), Float(output.region.maxY))
        encoder.setBytes(&geo, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        let w = c.pipeline.threadExecutionWidth, h = max(1, c.pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1), threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        encoder.endEncoding()
    }
}
