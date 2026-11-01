import Foundation
import DirectionCore

extension ToolCatalog {
    /// Validate the JSON Schema subset emitted by our catalog before interpreting arguments.
    /// This keeps mistyped flags and unknown fields from silently becoming no-op edits.
    static func validate(_ arguments: JSONValue, for name: String) throws {
        guard let definition = definitions.first(where: { $0.name == name }) else { throw DirectionError("unknown_tool", "Unknown Direction tool: \(name).") }
        try validate(arguments, schema: definition.inputSchema, path: "arguments")
    }

    private static func validate(_ value: JSONValue, schema: JSONValue, path: String) throws {
        func invalid(_ reason: String) -> DirectionError { .init("invalid_arguments", "\(path): \(reason)") }
        if let choices = schema["enum"].array, !choices.contains(value) { throw invalid("use one of \(choices.compactMap(\.string).joined(separator: ", ")).") }
        switch schema["type"].string {
        case "object":
            guard case .object(let fields) = value else { throw invalid("expected an object.") }
            for key in schema["required"].array?.compactMap(\.string) ?? [] where fields[key] == nil { throw invalid("\(key) is required.") }
            var properties: [String: JSONValue] = [:]
            if case .object(let p) = schema["properties"] { properties = p }
            for (key, field) in fields {
                if let child = properties[key] { try validate(field, schema: child, path: path + "." + key) }
                else if case .object = schema["additionalProperties"] { try validate(field, schema: schema["additionalProperties"], path: path + "." + key) }
                else if schema["additionalProperties"].bool == false { throw invalid("unknown field \(key); it takes \(properties.keys.sorted().joined(separator: ", ")).") }
            }
        case "array":
            guard let values = value.array else { throw invalid("expected an array.") }
            if schema["items"] != .null { for (i, field) in values.enumerated() { try validate(field, schema: schema["items"], path: path + "[\(i)]") } }
        case "string": guard value.string != nil else { throw invalid("expected text, not \(value.kindName).") }
        case "boolean": guard value.bool != nil else { throw invalid("expected true or false.") }
        case "number", "integer":
            guard let number = value.double, number.isFinite else { throw invalid("expected a number, not \(value.kindName).") }
            if schema["type"].string == "integer" && number.rounded() != number { throw invalid("expected a whole number.") }
            if let minimum = schema["minimum"].double, number < minimum { throw invalid("must be at least \(minimum.formatted()).") }
            if let maximum = schema["maximum"].double, number > maximum { throw invalid("must be at most \(maximum.formatted()).") }
        default: break
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
