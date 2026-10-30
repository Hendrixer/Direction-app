import Foundation
import ArgumentParser
import DirectionCore

/// `direction key save|remove|status`: this tool's own copy of the director's OpenRouter key.
/// Direction's Settings › Engines runs it, with the key on stdin. Nothing here prints the key
/// (see OpenRouter.Key for why each binary keeps its own copy).
struct KeyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "key", abstract: "Keep this tool's copy of the OpenRouter key. Direction's Settings › Engines does this for you; the key is never printed.", subcommands: [Save.self, Remove.self, Status.self])

    struct Options: ParsableArguments {
        @Option(help: .hidden) var service = OpenRouter.Key.defaultService
        func apply() throws {
            guard service.hasPrefix(OpenRouter.Key.defaultService) else { throw ValidationError("Only Direction's own keychain items.") }
            OpenRouter.Key.service = service
        }
    }

    struct Save: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Save the key read from standard input.")
        @OptionGroup var options: Options
        func run() throws {
            try options.apply()
            let key = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ValidationError("Pipe the key in on standard input.") }
            try OpenRouter.Key.store(key, .tools)
            try emit(JSONValue.object(["saved": .bool(true)]))
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove this tool's copy.")
        @OptionGroup var options: Options
        func run() throws { try options.apply(); OpenRouter.Key.delete(.tools); try emit(JSONValue.object(["removed": .bool(true)])) }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Whether this tool has a copy it can read without asking.")
        @OptionGroup var options: Options
        func run() throws {
            try options.apply()
            try emit(JSONValue.object(["present": .bool(OpenRouter.Key.exists(.tools)), "readable": .bool(OpenRouter.Key.item(.tools) != nil)]))
        }
    }
}
