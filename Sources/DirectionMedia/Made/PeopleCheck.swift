import Foundation
import CoreGraphics
import ImageIO
import Vision

/// Whether frames sent to a service show a person: a face, or a body seen from any side (the back of
/// a head counts). Some services refuse those (`MadeRanking.refusesPeople`), so Direction asks first,
/// on this Mac, for nothing.
public enum PeopleCheck {
    /// JPEG or PNG data of each frame.
    public static func anyPerson(in frames: [Data]) async -> Bool {
        let images = frames.compactMap { data -> VisionImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return VisionImage(image: image)
        }
        guard !images.isEmpty else { return false }
        return (try? await VisionWork.run {
            for frame in images {
                let faces = VNDetectFaceRectanglesRequest(), bodies = VNDetectHumanRectanglesRequest()
                bodies.upperBodyOnly = false
                try VNImageRequestHandler(cgImage: frame.image, options: [:]).perform([faces, bodies])
                if !(faces.results ?? []).isEmpty || (bodies.results ?? []).contains(where: { $0.confidence > 0.5 }) { return true }
            }
            return false
        }) ?? false
    }
}
