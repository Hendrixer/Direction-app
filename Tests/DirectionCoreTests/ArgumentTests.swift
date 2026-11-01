import Testing
import Foundation
@testable import DirectionCore

/// What the editor sends in the wrong shape says which field and what it should be, so it can put it right.
struct ArgumentTests {
    private struct Item: Decodable { var id: String; var progress: Double?; var parts: [Part]? }
    private struct Part: Decodable { var at: Double }

    @Test func aValueInTheWrongShapeNamesItsField() throws {
        let wrongType = JSONValue.object(["id": .string("sound"), "progress": .string("Reading the mix")])
        do { _ = try wrongType.decode(Item.self); Issue.record("Expected an error") }
        catch let e as DirectionError { #expect(e.code == "invalid_arguments" && e.message.hasPrefix("progress: ") && e.message.contains("Double"), "\(e.message)") }
        do { _ = try JSONValue.object(["progress": .number(0.5)]).decode(Item.self); Issue.record("Expected an error") }
        catch let e as DirectionError { #expect(e.message == "id is required.", "\(e.message)") }
        do { _ = try JSONValue.object(["id": .string("a"), "parts": .array([.object(["at": .number(1)]), .object([:])])]).decode(Item.self); Issue.record("Expected an error") }
        catch let e as DirectionError { #expect(e.message == "parts[1].at is required.", "\(e.message)") }
    }
}
