import AppKit
import CoreText
import Foundation

/// The approved Direction artwork, kept unmodified from the supplied icon export.
@MainActor
enum BrandAssets {
    static let icon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "DirectionBrand", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// The chrome D, cut out on transparency: welcome and empty states.
    static let mark: NSImage? = {
        guard let url = Bundle.module.url(forResource: "BrandMark", withExtension: "png") else { return icon }
        return NSImage(contentsOf: url)
    }()

    private static let archivoURL = Bundle.module.url(forResource: "Archivo-Variable", withExtension: "ttf")
        ?? Bundle.module.url(forResource: "Archivo-Variable", withExtension: "ttf", subdirectory: "Fonts")

    private static let archivoGraphicsFont: CGFont? = {
        guard let url = archivoURL, let provider = CGDataProvider(url: url as CFURL) else { return nil }
        return CGFont(provider)
    }()

    private static let fontRegistration: Void = {
        guard let url = archivoURL else { return }
        // Process scope avoids installing the font or changing the user's font collection.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func registerFonts() { _ = fontRegistration }

    /// Archivo's real variable axes, rather than a synthesized expanded system face.
    static func archivo(size: CGFloat, width: Double = 125, weight: Double = 800) -> CTFont {
        registerFonts()
        guard let graphicsFont = archivoGraphicsFont else {
            return CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
        }
        let base = CTFontCreateWithGraphicsFont(graphicsFont, size, nil, nil)
        let axes: [NSNumber: NSNumber] = [
            NSNumber(value: 0x77647468): NSNumber(value: min(125, max(62, width.isFinite ? width : 125))), // wdth
            NSNumber(value: 0x77676874): NSNumber(value: min(900, max(100, weight.isFinite ? weight : 800))), // wght
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base), [kCTFontVariationAttribute: axes] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
