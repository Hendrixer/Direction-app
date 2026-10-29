import Foundation
import GRDB

// Looks (specs/looks.md). The director chooses the look; the renderer applies it over every cut.

/// One look: a LUT at a strength plus filters.
public struct LookSettings: Codable, Hashable, Sendable {
    public var name: String
    /// A .cube file, absolute path.
    public var lut: String?
    public var strength: Double
    /// Filter kind → amount 0…1 (looks.md › Filters).
    public var filters: [String: Double]
    /// Filter kind → option, e.g. "grain": "fine", "letterbox": "2.39".
    public var options: [String: String]
    /// "you", "editor" or "folder".
    public var by: String
    public init(name: String, lut: String? = nil, strength: Double = 1, filters: [String: Double] = [:], options: [String: String] = [:], by: String = "you") {
        self.name = name; self.lut = lut; self.strength = strength; self.filters = filters; self.options = options; self.by = by
    }
}

/// The film's look, and any scene's own look, keyed by scene id.
public struct FilmLook: Codable, Hashable, Sendable {
    public var film: LookSettings?
    public var scenes: [String: LookSettings]
    public init(film: LookSettings? = nil, scenes: [String: LookSettings] = [:]) { self.film = film; self.scenes = scenes }
}

/// What the renderer needs to apply looks: the look and which scene each take belongs to.
public struct LookContext: Sendable, Hashable {
    public var look: FilmLook
    public var sceneForAsset: [String: String]
    public init(look: FilmLook, sceneForAsset: [String: String]) { self.look = look; self.sceneForAsset = sceneForAsset }
}

extension ProjectStore {
    static func ensureLookTables(_ db: Database) throws {}
    /// The film's look for rendering. Owned by the looks area; nil until a look is chosen.
    public func lookContext() throws -> LookContext? { nil }
}
