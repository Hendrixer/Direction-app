import AppKit
import Foundation

/// The approved Direction artwork, kept unmodified from the supplied icon export.
@MainActor
enum BrandAssets {
    static let icon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "DirectionBrand", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}
