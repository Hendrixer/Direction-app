import Foundation
import CoreMedia

public struct MediaTime: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var value: Int64
    public var timescale: Int32
    public init(value: Int64, timescale: Int32) { self.value = value; self.timescale = timescale }
    public init(_ time: CMTime) { value = time.value; timescale = time.timescale }
    public init(seconds: Double) { self.init(seconds.isFinite ? CMTime(seconds: seconds, preferredTimescale: 600_000) : .invalid) }
    public static let zero = MediaTime(value: 0, timescale: 600_000)
    public var isValid: Bool { timescale > 0 && seconds.isFinite }
    public var cmTime: CMTime { CMTime(value: value, timescale: timescale) }
    public var seconds: Double { timescale > 0 ? Double(value) / Double(timescale) : .nan }
    public var description: String { guard isValid, seconds < Double(Int.max) else { return "Invalid time" }; return String(format: "%02d:%05.2f", Int(max(0, seconds)) / 60, max(0, seconds).truncatingRemainder(dividingBy: 60)) }
    public static func < (l: Self, r: Self) -> Bool { CMTimeCompare(l.cmTime, r.cmTime) < 0 }
    public static func == (l: Self, r: Self) -> Bool { l.timescale > 0 && r.timescale > 0 && CMTimeCompare(l.cmTime, r.cmTime) == 0 }
    public func hash(into hasher: inout Hasher) {
        let d = Int64(Self.gcd(value.magnitude, UInt64(max(1, timescale))))
        hasher.combine(value / d); hasher.combine(Int64(timescale) / d)
    }
    private static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 { var a = a, b = b; while b != 0 { (a, b) = (b, a % b) }; return max(1, a) }
    public static func + (l: Self, r: Self) -> Self { Self(CMTimeAdd(l.cmTime, r.cmTime)) }
    public static func - (l: Self, r: Self) -> Self { Self(CMTimeSubtract(l.cmTime, r.cmTime)) }
    public func scaled(by factor: Double) -> Self { Self(CMTimeMultiplyByFloat64(cmTime, multiplier: factor)) }
}

public struct MediaRange: Codable, Hashable, Sendable {
    public var start: MediaTime
    public var duration: MediaTime
    public init(start: MediaTime, duration: MediaTime) { self.start = start; self.duration = duration }
    public init(start: Double, end: Double) { self.init(start: .init(seconds: start), duration: .init(seconds: end - start)) }
    public var end: MediaTime { start + duration }
    public var cmRange: CMTimeRange { CMTimeRange(start: start.cmTime, duration: duration.cmTime) }
    public var isValid: Bool { start.isValid && duration.isValid && start >= .zero && duration > .zero }
    public func contains(_ time: MediaTime) -> Bool { time >= start && time < end }
    public func intersection(_ other: Self) -> Self? {
        let a = max(start, other.start), b = min(end, other.end)
        return b > a ? Self(start: a, duration: b - a) : nil
    }
}

public struct FrameRate: Codable, Hashable, Sendable {
    public var numerator: Int32
    public var denominator: Int32
    public init(_ numerator: Int32 = 30, _ denominator: Int32 = 1) { self.numerator = numerator; self.denominator = denominator }
    public var frameDuration: CMTime { CMTime(value: Int64(denominator), timescale: numerator) }
    public var value: Double { Double(numerator) / Double(denominator) }
}

public struct DirectionError: Error, Codable, Sendable, LocalizedError {
    public let code: String
    public let message: String
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
    public var errorDescription: String? { message }
}

public func newID(_ prefix: String) -> String { prefix + "-" + UUID().uuidString.lowercased() }

public enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    public subscript(_ key: String) -> Self { if case .object(let d) = self { return d[key] ?? .null }; return .null }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var double: Double? { if case .number(let n) = self { return n }; return nil }
    public var int: Int? { double.flatMap { $0.isFinite && $0 >= Double(Int.min) && $0 < Double(Int.max) ? Int($0) : nil } }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var array: [Self]? { if case .array(let a) = self { return a }; return nil }
    public static func wrapping<T: Encodable>(_ value: T) throws -> Self { try JSONDecoder().decode(Self.self, from: JSONEncoder.direction.encode(value)) }
    public func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder.direction.encode(self)) }
    public func data(pretty: Bool = false) throws -> Data { let e = JSONEncoder.direction; if pretty { e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] }; return try e.encode(self) }
    public func requiredString(_ key: String) throws -> String { guard let s = self[key].string, !s.isEmpty else { throw DirectionError("invalid_arguments", "\(key) must be a nonempty string.") }; return s }
}

extension JSONEncoder {
    public static var direction: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e }
}
