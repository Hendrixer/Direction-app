import Foundation
import CoreImage
import Metal
import QuartzCore
import Synchronization
import DirectionCore

/// Transitions drawn from both shots at once (agent-timeline.md › Transitions): Direction's own (push,
/// slide, whip, zoom, wipe, iris) and the editor's, from `Transitions/<name>.metal`. Each is one Metal
/// function of the outgoing and incoming pictures and how far through it is:
///
///     // direction: param softness 0 0.5 0.1
///     [[ stitchable ]] float4 wipe(coreimage::sampler from, coreimage::sampler to, float progress, float softness, coreimage::destination dest) { … }
///
/// `direction::uv`, `direction::at` and `direction::ratio` count the way GLSL transitions do (0–1 from the
/// bottom left), so those port line for line. Like an effect, it's compiled at runtime and refused if it
/// makes NaN or takes longer than 40 ms a frame at 1080p.
public enum TransitionShader {
    static let compiled = Mutex<[String: ShaderEffect.Compiled]>([:])

    /// Direction's own, by type.
    public static func builtIn(_ type: String) -> String? { sources[type] }

    static func invalid(_ m: String) -> DirectionError { .init("shader_invalid", m) }

    /// The stitchable function and whether it takes the destination.
    static func signature(_ source: String, _ params: [ShaderParam]) throws -> (name: String, dest: Bool) {
        let pattern = #"\[\[\s*stitchable\s*\]\]\s*(half4|float4)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)"#
        let usage = "Write one `[[ stitchable ]] float4 transition(coreimage::sampler from, coreimage::sampler to, float progress, …, coreimage::destination dest)` function."
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let nameRange = Range(m.range(at: 2), in: source), let argRange = Range(m.range(at: 3), in: source) else { throw invalid(usage) }
        var args = source[argRange].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard args.count >= 3, args[0].contains("sampler"), args[1].contains("sampler"), args[2].contains("float") else { throw invalid(usage) }
        args.removeFirst(3)
        let dest = args.last?.contains("destination") ?? false
        if dest { args.removeLast() }
        guard args.count == params.count else { throw invalid("The function takes \(args.count) parameters after progress, but the header declares \(params.count). Declare each with `// direction: param`.") }
        for (a, p) in zip(args, params) {
            let isVector = a.contains("float3") || a.contains("half3")
            guard (p.kind == "color") == isVector, a.contains("float") || a.contains("half") else { throw invalid("\(p.name) is \(p.kind == "color" ? "a color: float3" : "a number: float") in the function's arguments, in the header's order.") }
        }
        return (String(source[nameRange]), dest)
    }

    static func compile(_ source: String) throws -> ShaderEffect.Compiled {
        let key = "transition:" + AudioProcessor.digest(Data(source.utf8))
        if let c = compiled.withLock({ $0[key] }) { return c }
        guard let device = ShaderEffect.device else { throw DirectionError("metal_unavailable", "Direction requires a Metal-capable Mac.") }
        guard source.utf8.count <= 64_000 else { throw invalid("Keep a transition under 64 KB.") }
        for (n, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#include") || t.hasPrefix("#import") || t.hasPrefix("#line") || t.hasPrefix("#pragma") { throw invalid("Line \(n + 1): transitions can't include files; metal_stdlib, Core Image's kernel types and direction:: are already there.") }
        }
        let params = try ShaderHeader.params(source)
        let sig = try signature(source, params)
        var call = ["fa", "fb", "p[0]"], k = 1
        for p in params { if p.kind == "color" { call.append("float3(p[\(k)], p[\(k + 1)], p[\(k + 2)])"); k += 3 } else { call.append("p[\(k)]"); k += 1 } }
        if sig.dest { call.append("dest") }
        let kernel = """

        kernel void direction_transition_main(texture2d<half, access::sample> a [[texture(0)]], texture2d<half, access::sample> b [[texture(1)]], texture2d<half, access::write> dst [[texture(2)]], constant float *p [[buffer(0)]], constant float4 &geo [[buffer(1)]], constant float2 &out [[buffer(2)]], uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
            float2 here = float2(out.x + float(gid.x) + 0.5, out.y - float(gid.y) - 0.5);
            coreimage::destination dest; dest.c = here;
            coreimage::sampler fa = { a, float4(geo.x, geo.y, 0, 0), here };
            coreimage::sampler fb = { b, float4(geo.z, geo.w, 0, 0), here };
            dst.write(half4(\(sig.name)(\(call.joined(separator: ", ")))), gid);
        }
        """
        let library: MTLLibrary
        do { library = try device.makeLibrary(source: ShaderEffect.prelude + source + kernel, options: MTLCompileOptions()) }
        catch {
            let lines = String(describing: (error as NSError).localizedDescription).split(separator: "\n").filter { $0.contains("error:") }.prefix(8)
            throw invalid("The transition doesn't compile:\n" + lines.map { $0.replacingOccurrences(of: "program_source:", with: "line ") }.joined(separator: "\n"))
        }
        guard let function = library.makeFunction(name: "direction_transition_main") else { throw invalid("The transition doesn't compile.") }
        let pipeline: MTLComputePipelineState
        do { pipeline = try device.makeComputePipelineState(function: function) } catch { throw invalid("The transition doesn't build: \(error.localizedDescription)") }
        let c = ShaderEffect.Compiled(key: key, pipeline: pipeline, params: params, usesSampler: true)
        compiled.withLock { $0[key] = c }
        return c
    }
    /// Compiles a transition and returns the parameters its header declares.
    public static func declared(source: String) throws -> [ShaderParam] { try compile(source).params }

    static func values(_ params: [ShaderParam], _ given: [String: JSONValue]?, progress: Double) -> [Float] {
        [Float(progress)] + params.flatMap { p -> [Float] in
            if p.kind == "color" { let (r, g, b) = ShaderHeader.rgb(given?[p.name]?.string ?? p.defaultValue.string ?? "#FFFFFF") ?? (1, 1, 1); return [Float(r), Float(g), Float(b)] }
            return [Float(given?[p.name]?.double ?? p.defaultValue.double ?? 0)]
        }
    }

    /// The two shots drawn together, `progress` of the way through.
    static func apply(from: CIImage, to: CIImage, progress: Double, transition t: ClipTransition, bounds: CGRect) -> CIImage {
        guard let source = t.source, let c = try? compile(source) else { return to.composited(over: from) }
        return apply(from: from, to: to, compiled: c, values: values(c.params, t.params, progress: progress), bounds: bounds)
    }
    static func apply(from: CIImage, to: CIImage, compiled c: ShaderEffect.Compiled, values: [Float], bounds: CGRect) -> CIImage {
        guard bounds.width > 0, bounds.height > 0, bounds.width < 20_000, bounds.height < 20_000 else { return to.composited(over: from) }
        // Both fill the frame, transparent where a shot doesn't reach, so their pixels line up.
        let clear = CIImage(color: .clear).cropped(to: bounds)
        let a = from.composited(over: clear).cropped(to: bounds), b = to.composited(over: clear).cropped(to: bounds)
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return (try? TransitionKernel.apply(withExtent: bounds, inputs: [a, b], arguments: ["key": c.key, "values": data, "extent": CIVector(cgRect: bounds)])) ?? to.composited(over: from)
    }

    /// Compiles and times a transition: 3 frames at 1080p, a quarter, half and three quarters through.
    public static func check(source: String, params: [String: JSONValue] = [:]) throws -> JSONValue {
        let c = try compile(source)
        guard let device = ShaderEffect.device, let queue = device.makeCommandQueue() else { throw DirectionError("metal_unavailable", "Direction requires a Metal-capable Mac.") }
        let size = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        func gradient(_ a: CIColor, _ b: CIColor) -> CIImage { CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 1920, y: 1080), "inputColor0": a, "inputColor1": b])!.outputImage!.cropped(to: size) }
        let checks = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 40, "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.25), "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)])!.outputImage!
        let from = checks.composited(over: gradient(CIColor(red: 0.9, green: 0.2, blue: 0.1), CIColor(red: 0.1, green: 0.3, blue: 0.9))).cropped(to: size)
        let to = gradient(CIColor(red: 0.1, green: 0.8, blue: 0.4), CIColor(red: 0.9, green: 0.9, blue: 0.2))
        let context = CIContext(mtlDevice: device, options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1920, height: 1080, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]; descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw DirectionError("render_failed", "Can't allocate a test frame.") }
        func render(_ image: CIImage) throws -> Double {
            guard let buffer = queue.makeCommandBuffer() else { throw DirectionError("render_failed", "Can't render a test frame.") }
            let started = CACurrentMediaTime()
            _ = try context.startTask(toRender: image, to: CIRenderDestination(mtlTexture: texture, commandBuffer: buffer))
            if !device.hasUnifiedMemory, let blit = buffer.makeBlitCommandEncoder() { blit.synchronize(resource: texture); blit.endEncoding() }
            buffer.commit(); buffer.waitUntilCompleted()
            return CACurrentMediaTime() - started
        }
        _ = try render(from)
        var times: [Double] = []
        func frame(_ p: Double) throws -> Double { try render(apply(from: from, to: to, compiled: c, values: values(c.params, params, progress: p), bounds: size)) }
        for p in [0.25, 0.5, 0.75] { times.append(try frame(p)) }
        // Its cost is its fastest frame: a busy Mac only adds time, so a few more tries come before refusing it.
        for p in [0.5, 0.25, 0.75, 0.5, 0.25, 0.75] where times.min()! * 1_000 > 40 { times.append(try frame(p)) }
        let ms = times.min()! * 1_000
        guard ms <= 40 else { throw DirectionError("shader_too_slow", "The transition takes \(Int(ms.rounded())) ms a frame at 1080p; it has to be under 40.") }
        var row = [UInt16](repeating: 0, count: 1920 * 4)
        for y in 0..<1080 {
            row.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 1920 * 8, from: MTLRegionMake2D(0, y, 1920, 1), mipmapLevel: 0) }
            if row.contains(where: { $0 & 0x7C00 == 0x7C00 }) { throw DirectionError("shader_invalid", "The transition makes NaN or infinite values (row \(y) of the test frame, three quarters through).") }
        }
        return .object(["msPerFrame": .number((ms * 10).rounded() / 10), "frames": .number(3), "size": .string("1920×1080"), "params": (try? .wrapping(c.params)) ?? .array([])])
    }

    // MARK: Direction's own

    static let sources: [String: String] = [
        "push": """
        // direction: param x -1 1 -1
        // direction: param y -1 1 0
        // The new shot pushes the old one out, both moving the same way.
        [[ stitchable ]] float4 push(coreimage::sampler from, coreimage::sampler to, float progress, float x, float y, coreimage::destination dest) {
            float2 uv = direction::uv(from, dest), dir = float2(x, -y);
            float p = progress * progress * (3.0 - 2.0 * progress);
            float2 a = uv - dir * p, b = uv - dir * (p - 1.0);
            return direction::inside(a) ? direction::at(from, a) : direction::at(to, b);
        }
        """,
        "slide": """
        // direction: param x -1 1 -1
        // direction: param y -1 1 0
        // The new shot slides in over the old one, which stays where it is.
        [[ stitchable ]] float4 slide(coreimage::sampler from, coreimage::sampler to, float progress, float x, float y, coreimage::destination dest) {
            float2 uv = direction::uv(from, dest), dir = float2(x, -y);
            float p = progress * progress * (3.0 - 2.0 * progress);
            float2 b = uv - dir * (p - 1.0);
            return direction::inside(b) ? direction::at(to, b) : direction::at(from, uv);
        }
        """,
        "whip": """
        // direction: param x -1 1 -1
        // direction: param y -1 1 0
        // direction: param blur 0 1 0.7
        // A whip pan: a fast push, smeared along the way it travels, hardest in the middle.
        float4 pushed(coreimage::sampler from, coreimage::sampler to, float2 uv, float2 dir, float p) {
            float2 a = uv - dir * p, b = uv - dir * (p - 1.0);
            return direction::inside(a) ? direction::at(from, a) : direction::at(to, b);
        }
        [[ stitchable ]] float4 whip(coreimage::sampler from, coreimage::sampler to, float progress, float x, float y, float blur, coreimage::destination dest) {
            float2 uv = direction::uv(from, dest), dir = float2(x, -y);
            float p = progress < 0.5 ? 4.0 * progress * progress * progress : 1.0 - pow(-2.0 * progress + 2.0, 3.0) / 2.0;
            float spread = blur * 0.45 * sin(3.14159265 * progress);
            float4 c = float4(0.0);
            for (int i = 0; i < 16; i++) { c += pushed(from, to, uv + dir * (float(i) / 15.0 - 0.5) * spread, dir, p); }
            return c / 16.0;
        }
        """,
        "zoom": """
        // direction: param amount 1.2 6 2.5
        // The old shot rushes toward the middle; the new one settles out of the rush.
        float4 rushed(coreimage::sampler s, float2 uv, float zoom, float streak) {
            float2 c = float2(0.5);
            float4 sum = float4(0.0);
            for (int i = 0; i < 10; i++) { float f = 1.0 - streak * float(i) / 9.0; sum += direction::at(s, c + (uv - c) / zoom * f); }
            return sum / 10.0;
        }
        [[ stitchable ]] float4 zoom(coreimage::sampler from, coreimage::sampler to, float progress, float amount, coreimage::destination dest) {
            float2 uv = direction::uv(from, dest);
            float streak = 0.18 * sin(3.14159265 * progress);
            float a = mix(1.0, amount, smoothstep(0.0, 0.5, progress)), b = mix(amount, 1.0, smoothstep(0.5, 1.0, progress));
            return mix(rushed(from, uv, a, streak), rushed(to, uv, b, streak), smoothstep(0.42, 0.58, progress));
        }
        """,
        "wipe": """
        // direction: param angle -180 180 0
        // direction: param softness 0 0.5 0.08
        // An edge crosses the frame onto the new shot. 0 travels left to right, 90 top to bottom.
        [[ stitchable ]] float4 wipe(coreimage::sampler from, coreimage::sampler to, float progress, float angle, float softness, coreimage::destination dest) {
            float2 uv = direction::uv(from, dest);
            float r = angle * 3.14159265 / 180.0;
            float2 d = float2(cos(r), -sin(r));
            float along = dot(uv - 0.5, d), reach = 0.5 * (abs(d.x) + abs(d.y)) + softness;
            float edge = mix(-reach, reach, progress);
            float t = 1.0 - smoothstep(edge - softness * 0.5, edge + softness * 0.5, along);
            return mix(direction::at(from, uv), direction::at(to, uv), t);
        }
        """,
        "iris": """
        // direction: param x 0 1 0.5
        // direction: param y 0 1 0.5
        // direction: param softness 0 0.5 0.04
        // A circle opens from x, y (fractions of the frame from its top left) onto the new shot.
        [[ stitchable ]] float4 iris(coreimage::sampler from, coreimage::sampler to, float progress, float x, float y, float softness, coreimage::destination dest) {
            float2 uv = direction::uv(from, dest), c = float2(x, 1.0 - y), k = float2(direction::ratio(from), 1.0);
            float far = 0.0;
            for (int i = 0; i < 4; i++) { float2 corner = float2(float(i % 2), float(i / 2)); far = max(far, length((corner - c) * k)); }
            float r = progress * (far + softness), d = length((uv - c) * k);
            float t = 1.0 - smoothstep(r - softness, r, d);
            return mix(direction::at(from, uv), direction::at(to, uv), t);
        }
        """,
    ]
}

final class TransitionKernel: CIImageProcessorKernel {
    override class var outputFormat: CIFormat { .RGBAh }
    override class func formatForInput(at input: Int32) -> CIFormat { .RGBAh }
    override class func roi(forInput input: Int32, arguments: [String: Any]?, outputRect: CGRect) -> CGRect {
        (arguments?["extent"] as? CIVector)?.cgRectValue ?? outputRect
    }
    override class func process(with inputs: [CIImageProcessorInput]?, arguments: [String: Any]?, output: CIImageProcessorOutput) throws {
        guard let inputs, inputs.count == 2, let a = inputs[0].metalTexture, let b = inputs[1].metalTexture, let target = output.metalTexture, let buffer = output.metalCommandBuffer,
              let key = arguments?["key"] as? String, let c = TransitionShader.compiled.withLock({ $0[key] }), let data = arguments?["values"] as? Data,
              let encoder = buffer.makeComputeCommandEncoder() else { throw DirectionError("render_failed", "The transition couldn't run.") }
        encoder.setComputePipelineState(c.pipeline)
        encoder.setTexture(a, index: 0); encoder.setTexture(b, index: 1); encoder.setTexture(target, index: 2)
        data.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: max(4, data.count), index: 0) }
        var geo = SIMD4<Float>(Float(inputs[0].region.minX), Float(inputs[0].region.maxY), Float(inputs[1].region.minX), Float(inputs[1].region.maxY))
        encoder.setBytes(&geo, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        var out = SIMD2<Float>(Float(output.region.minX), Float(output.region.maxY))
        encoder.setBytes(&out, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
        let w = c.pipeline.threadExecutionWidth, h = max(1, c.pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1), threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        encoder.endEncoding()
    }
}
