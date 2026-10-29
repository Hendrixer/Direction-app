import Foundation
import CoreImage
import DirectionCore

/// Applies the director's look to a composited frame (specs/looks.md › Where color happens).
/// The compositor calls this after every layer below the look, before layers marked above it.
public enum LookPipeline {
    /// - storyAssetID: the take on the story track (V1) at this frame, to find its scene's look.
    /// - frameIndex: frames from the cut's start; grain and gate weave are seeded by it.
    public static func apply(_ image: CIImage, context: LookContext?, storyAssetID: String?, frameIndex: Int) -> CIImage { image }

    /// One filter on its own (looks.md › Filters), for the editor's per-clip `filter.<kind>` effects.
    public static func filter(_ image: CIImage, kind: String, amount: Double, option: String?, frameIndex: Int) -> CIImage { image }
}
