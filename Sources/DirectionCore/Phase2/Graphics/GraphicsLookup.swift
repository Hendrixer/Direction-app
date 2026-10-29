import Foundation

extension ProjectStore {
    /// The rendered asset for a checked graphic, so `placeGraphic` can place it like footage.
    /// Owned by the graphics area; nil until `direction_graphic` has rendered it once. The asset keeps
    /// its id across re-renders; reads swap in the current render's file (`withCurrentGraphics`).
    public func graphicAssetID(_ name: String) throws -> String? { try graphic(name)?.assetID }
}
