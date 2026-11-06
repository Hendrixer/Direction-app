import Foundation
import DirectionCore

extension ToolCatalog {
    /// Validate the JSON Schema subset emitted by our catalog before interpreting arguments.
    /// This keeps mistyped flags and unknown fields from silently becoming no-op edits. Every problem in the call
    /// is named at once, with its path, what it takes and what came instead; the words say nothing changed,
    /// since Codex doesn't show the model that a result was an error.
    static func validate(_ arguments: JSONValue, for name: String) throws {
        guard let definition = definitions.first(where: { $0.name == name }) else { throw DirectionError("unknown_tool", "Unknown Direction tool: \(name).") }
        var problems: [String] = []
        check(arguments, schema: definition.inputSchema, path: "arguments", into: &problems)
        guard problems.isEmpty else { throw DirectionError("invalid_arguments", problems.joined(separator: " ") + " Nothing was changed; call \(name) again with \(problems.count == 1 ? "that" : "these") put right.") }
    }

    static func check(_ value: JSONValue, schema: JSONValue, path: String, into problems: inout [String]) {
        func invalid(_ reason: String) { problems.append("\(path): \(reason)") }
        // One of several typed shapes: it fits if any of them takes it.
        if let shapes = schema["anyOf"].array {
            var fits = false
            for shape in shapes { var none: [String] = []; check(value, schema: shape, path: path, into: &none); if none.isEmpty { fits = true; break } }
            if !fits { invalid("expected \(shapes.map(describe).joined(separator: " or ")), not \(value.kindName).") }
            return
        }
        if let choices = schema["enum"].array, !choices.contains(value) { return invalid("use one of \(choices.compactMap(\.string).joined(separator: ", ")).") }
        switch schema["type"].string {
        case "object":
            guard case .object(let fields) = value else { return invalid("expected an object, not \(value.kindName).") }
            for key in schema["required"].array?.compactMap(\.string) ?? [] where fields[key] == nil { invalid("\(key) is required.") }
            var properties: [String: JSONValue] = [:]
            if case .object(let p) = schema["properties"] { properties = p }
            for (key, field) in fields.sorted(by: { $0.key < $1.key }) {
                if let child = properties[key] { check(field, schema: child, path: path + "." + key, into: &problems) }
                else if case .object = schema["additionalProperties"] { check(field, schema: schema["additionalProperties"], path: path + "." + key, into: &problems) }
                else if schema["additionalProperties"].bool == false { invalid("unknown field \(key); it takes \(properties.keys.sorted().joined(separator: ", ")).") }
            }
        case "array":
            guard let values = value.array else { return invalid("expected a list, not \(value.kindName).") }
            if schema["items"] != .null { for (i, field) in values.enumerated() { check(field, schema: schema["items"], path: path + "[\(i)]", into: &problems) } }
        case "string": if value.string == nil { invalid("expected text, not \(value.kindName).") }
        case "boolean": if value.bool == nil { invalid("expected true or false, not \(value.kindName).") }
        case "number", "integer":
            guard let number = value.double, number.isFinite else { return invalid("expected a number, not \(value.kindName).") }
            if schema["type"].string == "integer" && number.rounded() != number { return invalid("expected a whole number.") }
            if let minimum = schema["minimum"].double, number < minimum { invalid("must be at least \(minimum.formatted()).") }
            if let maximum = schema["maximum"].double, number > maximum { invalid("must be at most \(maximum.formatted()).") }
        default: break
        }
    }

    /// A shape in a few words: "a number", "{value, timescale}".
    private static func describe(_ schema: JSONValue) -> String {
        switch schema["type"].string {
        case "object":
            guard case .object(let p) = schema["properties"] else { return "an object" }
            return "{" + p.keys.sorted().joined(separator: ", ") + "}"
        case "array": return "a list"
        case "string": return "text"
        case "boolean": return "true or false"
        case "integer": return "a whole number"
        default: return "a number"
        }
    }
}

extension JSONValue {
    /// What a value is, for saying what was sent instead.
    var kindName: String {
        switch self {
        case .string(let s): "the text \u{201C}\(s.count > 40 ? String(s.prefix(40)) + "\u{2026}" : s)\u{201D}"
        case .number: "a number"; case .bool: "true or false"; case .array: "a list"; case .object: "an object"; case .null: "null"
        }
    }
}
