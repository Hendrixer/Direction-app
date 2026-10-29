import Foundation

extension ProjectStore {
    /// The rendered asset for a checked graphic, so `placeGraphic` can place it like footage.
    /// Owned by the graphics area; nil until a graphic exists.
    public func graphicAssetID(_ name: String) throws -> String? { nil }
}
