import SwiftUI
import AppKit
import Metal
import MetalKit

/// The chrome D lit by a light that circles it. The letter's bevel is rebuilt from its silhouette, so
/// the edges turned toward the light catch it and the far edges fall off; red, green and blue each see
/// the light from a slightly different angle, so the highlights split into rainbows the way chrome
/// and glass disperse light. The light moves slowly, gathers speed, eases into a stall, then rests.
/// Reduce Motion, or a Mac without Metal, shows the still mark.
struct ChromeMark: View {
    var size: CGFloat = 168
    /// Pins the moment, in seconds, for snapshots. Nil follows the clock.
    var at: Double? = nil
    /// Holds the light still, coming from this direction (radians, image coordinates, y down): a film's poster.
    var light: Double? = nil
    @Environment(\.displayScale) private var displayScale

    static let pass = 5.6, rest = 2.4
    /// Slow out of the rest, quick through the middle, a long eased stall.
    static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.72, y: 0), endControlPoint: UnitPoint(x: 0.14, y: 1))
    /// Where the light rests: up and to the left, in image coordinates (y down).
    static let restingAngle = 1.25 * Double.pi

    /// The light's direction around the letter: once around per pass, parked through the rest.
    static func angle(_ time: Double) -> Double {
        let t = time.truncatingRemainder(dividingBy: pass + rest)
        return restingAngle + (t >= pass ? 0 : curve.value(at: t / pass)) * 2 * .pi
    }

    var body: some View {
        if let mark = BrandAssets.mark {
            Group {
                if let renderer = ChromeLightRenderer.shared, !(at == nil && light == nil && SettingsKey.reducesMotion) {
                    if let at { lit(renderer, Self.angle(at), scale: 2) }
                    else if let light { lit(renderer, light, scale: max(2, displayScale)) }
                    else { TimelineView(.animation(minimumInterval: 1 / 60)) { lit(renderer, Self.angle($0.date.timeIntervalSinceReferenceDate), scale: displayScale) } }
                } else {
                    Image(nsImage: mark).resizable().interpolation(.high).scaledToFit()
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func lit(_ renderer: ChromeLightRenderer, _ angle: Double, scale: CGFloat) -> some View {
        if let image = renderer.image(angle: angle, pixels: Int((size * scale).rounded())) {
            Image(decorative: image, scale: scale).resizable().interpolation(.high)
        }
    }
}

/// Renders the lit mark on the GPU. The shader is compiled from source at first use, so the app
/// needs no build-time Metal tools.
@MainActor final class ChromeLightRenderer {
    static let shared = ChromeLightRenderer()

    private let device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLComputePipelineState
    private let art: MTLTexture, height: MTLTexture
    private var output: MTLTexture?
    /// The last few drawn, so posters lit from their own directions aren't drawn again on every hover.
    private var recent: [(angle: Double, pixels: Int, image: CGImage)] = []

    /// How the light behaves. Tuned against the art; see design/spec/specs/start.md.
    struct Params {
        var light: SIMD2<Float> = .zero  // direction from the letter's center to the light
        var elevation: Float = 0.32      // low, so edges catch it and the face mostly doesn't
        var lod: Float = 0
        var bevel: Float = 30            // how steeply the rim turns away from the face
        var detail: Float = 1.4          // relief from the chrome's own flecks
        var intensity: Float = 2.2
        var spread: Float = 0.5         // radians between red, green and blue: the width of the rainbows
        var orbit: Float = 0.78          // the light's distance from the center, in the mark's widths
        var falloff: Float = 1.6         // how quickly the light fades across the letter
        var saturation: Float = 0.2      // how much of the art's painted rainbow stays far from the light
        var lobe: Float = 7              // how narrow the lit stretch of edge is
    }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let mark = BrandAssets.mark, let cg = mark.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let library = try? device.makeLibrary(source: Self.shader, options: nil),
              let function = library.makeFunction(name: "chromeLight"),
              let pipeline = try? device.makeComputePipelineState(function: function),
              let art = try? MTKTextureLoader(device: device).newTexture(cgImage: cg, options: [.SRGB: false, .generateMipmaps: true, .textureStorageMode: MTLStorageMode.private.rawValue]),
              let height = Self.heightTexture(cg, device: device) else { return nil }
        self.device = device; self.queue = queue; self.pipeline = pipeline; self.art = art; self.height = height
    }

    func image(angle: Double, pixels: Int) -> CGImage? {
        let pixels = max(32, min(pixels, 1024))
        if let hit = recent.first(where: { $0.angle == angle && $0.pixels == pixels }) { return hit.image }
        if output?.width != pixels {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: pixels, height: pixels, mipmapped: false)
            d.usage = [.shaderWrite]; d.storageMode = .shared
            output = device.makeTexture(descriptor: d)
        }
        guard let output, let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else { return nil }
        var params = Params()
        params.light = SIMD2(Float(cos(angle)), Float(sin(angle)))
        params.lod = log2(Float(art.width) / Float(pixels))
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(art, index: 0); encoder.setTexture(height, index: 1); encoder.setTexture(output, index: 2)
        encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreadgroups(MTLSize(width: (pixels + 15) / 16, height: (pixels + 15) / 16, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        buffer.commit(); buffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
        output.getBytes(&bytes, bytesPerRow: pixels * 4, from: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        recent = [(angle, pixels, image)] + recent.prefix(11)
        return image
    }

    /// The bevel as a height field: 0 at the silhouette, rising to 1 about a bevel's width inside it.
    /// It's the alpha blurred wide and re-ranged, an emboss that has no pixel steps to ripple the light.
    private static func heightTexture(_ cg: CGImage, device: MTLDevice) -> MTLTexture? {
        let side = 512, radius = 11
        var alpha = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(data: &alpha, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var field = alpha.map { Float($0) / 255 }
        // Three separable box blurs approximate a Gaussian (σ ≈ 11 px here, about 2% of the mark).
        func blur(_ index: (Int, Int) -> Int) {
            var line = [Float](repeating: 0, count: side)
            for row in 0..<side {
                var sum: Float = 0
                for k in -radius...radius { sum += field[index(row, min(max(k, 0), side - 1))] }
                for col in 0..<side {
                    line[col] = sum / Float(2 * radius + 1)
                    sum += field[index(row, min(col + radius + 1, side - 1))] - field[index(row, max(col - radius, 0))]
                }
                for col in 0..<side { field[index(row, col)] = line[col] }
            }
        }
        for _ in 0..<3 { blur { $0 * side + $1 }; blur { $1 * side + $0 } }
        // The rim sits just inside the silhouette, on the art's own chrome bevel; then the face.
        let h = field.map { v -> Float in let t = min(max((v - 0.72) / 0.275, 0), 1); return 1 - (1 - t) * (1 - t) }
        // Half floats: always filterable, unlike 32-bit floats on some GPUs.
        let half = h.map(Float16.init)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: side, height: side, mipmapped: false)
        descriptor.usage = [.shaderRead]; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, withBytes: half, bytesPerRow: side * 2)
        return texture
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Params { float2 light; float elevation; float lod; float bevel; float detail; float intensity; float spread; float orbit; float falloff; float saturation; float lobe; };

    static float luma(float3 c) { return dot(c, float3(0.3, 0.59, 0.11)); }

    kernel void chromeLight(texture2d<float> art [[texture(0)]], texture2d<float> height [[texture(1)]],
                            texture2d<float, access::write> out [[texture(2)]], constant Params& p [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
        float2 uv = (float2(gid) + 0.5) / float2(out.get_width(), out.get_height());
        float4 c = art.sample(s, uv, level(p.lod));
        if (c.a < 0.002) { out.write(float4(0.0), gid); return; }

        // The surface: the rim's slope from the height field, plus fine relief from the chrome's flecks.
        float2 hs = 1.0 / float2(height.get_width(), height.get_height());
        float hc = height.sample(s, uv).r;
        float hx = height.sample(s, uv + float2(hs.x, 0)).r - height.sample(s, uv - float2(hs.x, 0)).r;
        float hy = height.sample(s, uv + float2(0, hs.y)).r - height.sample(s, uv - float2(0, hs.y)).r;
        float2 as = exp2(p.lod) / float2(art.get_width(), art.get_height());
        float lx = luma(art.sample(s, uv + float2(as.x, 0), level(p.lod)).rgb) - luma(art.sample(s, uv - float2(as.x, 0), level(p.lod)).rgb);
        float ly = luma(art.sample(s, uv + float2(0, as.y), level(p.lod)).rgb) - luma(art.sample(s, uv - float2(0, as.y), level(p.lod)).rgb);
        float3 n = normalize(float3(-hx * p.bevel - lx * p.detail, -hy * p.bevel - ly * p.detail, 1.0));
        float rim = 1.0 - hc;

        // A point light circling just outside the letter: near parts get more of it.
        float2 toLight = float2(0.5) + p.light * p.orbit - uv;
        float reach = 1.0 / (1.0 + p.falloff * dot(toLight, toLight) * 4.0);
        // The art's painted rainbow is dispersion too: it shows where the light reaches and fades
        // where it doesn't, so it follows the light instead of staying put.
        c.rgb = mix(float3(luma(c.rgb)), c.rgb, mix(p.saturation, 1.0, saturate(reach * 1.5)));
        // The lit edge: the part of the bevel whose slope faces the light glows. Red, green and blue
        // are aimed a little apart, so where all three overlap the edge is white and at its ends the
        // light splits into spectral fringes, the way chrome and glass disperse it.
        float base = atan2(toLight.y, toLight.x);
        // Which way the edge faces comes from the bevel alone; the flecks only make glints.
        float2 slope = float2(-hx, -hy) / max(length(float2(hx, hy)), 1e-5);
        float band = sin(3.14159 * saturate(rim));
        // Seven wavelengths, red to violet, each aimed a step apart; their colors sum to white.
        const float3 spectrum[7] = { float3(1.0, 0.0, 0.05), float3(1.0, 0.45, 0.0), float3(0.85, 0.85, 0.0), float3(0.1, 1.0, 0.2),
                                     float3(0.0, 0.75, 1.0), float3(0.15, 0.25, 1.0), float3(0.6, 0.0, 1.0) };
        float3 fringe = float3(0.0);
        for (int i = 0; i < 7; i++) {
            float a = base + (float(i) - 3.0) / 3.0 * p.spread;
            fringe += spectrum[i] * pow(saturate(dot(slope, float2(cos(a), sin(a)))), p.lobe);
        }
        fringe /= float3(2.7, 3.3, 2.45);
        float core = pow(saturate(dot(slope, float2(cos(base), sin(base)))), p.lobe * 2.5);
        float3 edge = (float3(core) * 0.85 + fringe * 0.75) * band;
        // Glints: the face's own flecks catch a mirror highlight near the light.
        float3 l = normalize(float3(toLight, p.elevation));
        float glint = pow(max(dot(n, normalize(l + float3(0, 0, 1))), 0.0), 60.0) * (1.0 - rim);
        // The rim facing the light brightens; the rim facing away falls into shade.
        float facing = dot(slope, normalize(toLight));
        // The art's own lighting dims a little so the moving light reads: chrome near the light is
        // brighter, chrome far from it a touch darker, and edges turned away fall into shade.
        float ambient = 0.64 + 0.5 * reach;
        float3 shaded = c.rgb * ambient * mix(1.0, 0.5 + 0.65 * saturate(facing), band);
        float3 light = (edge * p.intensity + glint * 0.5) * reach;
        float3 lit = shaded + light * c.a;
        out.write(float4(min(lit, float3(c.a)), c.a), gid);
    }
    """
}
