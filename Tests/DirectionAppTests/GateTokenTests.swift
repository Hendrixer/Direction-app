import AppKit
import CoreText
import SwiftUI
import Testing
@testable import DirectionApp

struct KnownOKLCHColor: Sendable {
    let lightness: Double
    let chroma: Double
    let hue: Double
    let rgb: [Double]
}

@Suite("Gate design tokens")
@MainActor
struct GateTokenTests {
    /// Reference primary coordinates from the standard sRGB ↔ OKLab transform.
    @Test(arguments: [
        KnownOKLCHColor(lightness: 0, chroma: 0, hue: 0, rgb: [0, 0, 0]),
        KnownOKLCHColor(lightness: 1, chroma: 0, hue: 0, rgb: [1, 1, 1]),
        KnownOKLCHColor(lightness: 0.6279553606, chroma: 0.2576833077, hue: 29.2338851923, rgb: [1, 0, 0]),
        KnownOKLCHColor(lightness: 0.8664396115, chroma: 0.2948272403, hue: 142.4953388878, rgb: [0, 1, 0]),
        KnownOKLCHColor(lightness: 0.4520137184, chroma: 0.3132143717, hue: 264.0520206381, rgb: [0, 0, 1]),
    ])
    func colorConversionRecoversKnownSRGBPrimaries(_ sample: KnownOKLCHColor) {
        let converted = GateColorSpace.sRGB(lightness: sample.lightness, chroma: sample.chroma, hue: sample.hue)
        for (actual, expected) in zip([converted.red, converted.green, converted.blue], sample.rgb) {
            #expect(abs(actual - expected) < 0.0001)
        }
        #expect(converted.opacity == 1)
    }

    @Test func perceptualLightnessIsNotTreatedAsAnRGBGrayValue() {
        let converted = GateColorSpace.sRGB(lightness: 0.5, chroma: 0, hue: 0)
        #expect(abs(converted.red - 0.3885728590) < 0.000001)
        #expect(abs(converted.green - converted.red) < 0.000001)
        #expect(abs(converted.blue - converted.red) < 0.000001)
    }

    @Test func hueWrapsWithoutChangingTheColor() {
        let base = GateColorSpace.sRGB(lightness: 0.72, chroma: 0.20, hue: 330)
        let positive = GateColorSpace.sRGB(lightness: 0.72, chroma: 0.20, hue: 690)
        let negative = GateColorSpace.sRGB(lightness: 0.72, chroma: 0.20, hue: -30)
        for comparison in [positive, negative] {
            #expect(abs(base.red - comparison.red) < 0.000000001)
            #expect(abs(base.green - comparison.green) < 0.000000001)
            #expect(abs(base.blue - comparison.blue) < 0.000000001)
        }
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude])
    func invalidOrExtremeInputsRemainFiniteAndInsideSRGB(_ value: Double) {
        let converted = GateColorSpace.sRGB(lightness: value, chroma: value, hue: value, opacity: value)
        #expect([converted.red, converted.green, converted.blue, converted.opacity].allSatisfy { $0.isFinite && (0...1).contains($0) })
        let negativeChroma = GateColorSpace.sRGB(lightness: 0.5, chroma: -1, hue: value)
        #expect(abs(negativeChroma.red - negativeChroma.green) < 0.000001)
        #expect(abs(negativeChroma.green - negativeChroma.blue) < 0.000001)
    }

    @Test func opacityIsPreservedAndClamped() {
        #expect(GateColorSpace.sRGB(lightness: 0.82, chroma: 0.13, hue: 72, opacity: 0.15).opacity == 0.15)
        #expect(GateColorSpace.sRGB(lightness: 0.82, chroma: 0.13, hue: 72, opacity: -1).opacity == 0)
        #expect(GateColorSpace.sRGB(lightness: 0.82, chroma: 0.13, hue: 72, opacity: 2).opacity == 1)
        #expect(GateColorSpace.sRGB(lightness: 0.82, chroma: 0.13, hue: 72, opacity: .nan).opacity == 0)
    }

    /// Fixed sRGB snapshots protect the exact CSS primitives against the guide's approximate Swift ramp.
    @Test func semanticColorsUseTheAuthoritativeCSSValues() throws {
        try expectRGB(Gate.Surface.canvas, [0, 0, 0])
        try expectRGB(Gate.Surface.panel, [0.0818548007, 0.0863185428, 0.0955052905])
        try expectRGB(Gate.Text.secondary, [0.6865373254, 0.6940746358, 0.7095228794])
        try expectRGB(Gate.Voice.director, [0.9722760269, 0.7119324074, 0.3657240039])
        try expectRGB(Gate.Component.Button.steelTop, [0.9711733347, 0.9738577143, 0.9793533545])
    }

    @Test func prismKeepsItsFourDifferentCSSLightnessAndChromaValues() throws {
        let expected = [
            [0.2979172290, 0.8600093870, 0.8887378881],
            [0.4542053358, 0.5947081761, 1.0],
            [0.9060322653, 0.4319207257, 0.8743924624],
            [1.0, 0.7156263909, 0.4266148616],
        ]
        #expect(Gate.Voice.agentStroke.count == expected.count)
        for (color, rgb) in zip(Gate.Voice.agentStroke, expected) { try expectRGB(color, rgb) }
    }

    @Test func archivoUsesTheBundledVariableFontAtTheRequestedAxes() throws {
        let font = BrandAssets.archivo(size: 22)
        #expect((CTFontCopyFamilyName(font) as String).contains("Archivo"))
        #expect(CTFontGetSize(font) == 22)
        let axes = try #require(CTFontCopyVariation(font) as? [NSNumber: NSNumber])
        #expect(axes[NSNumber(value: 0x77647468)]?.doubleValue == 125)
        #expect(axes[NSNumber(value: 0x77676874)]?.doubleValue == 800)
    }

    private func expectRGB(_ color: Color, _ expected: [Double]) throws {
        let converted = try #require(NSColor(color).usingColorSpace(.sRGB))
        for (actual, target) in zip([converted.redComponent, converted.greenComponent, converted.blueComponent], expected) {
            #expect(abs(Double(actual) - target) < 0.000002)
        }
    }
}
