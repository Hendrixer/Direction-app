import Foundation
import AppKit
import DirectionCore

/// One MCP/API process can own jobs in several projects. Calls always route by an
/// explicit path, never a mutable global selection. Started for one film (--project, as every
/// editor run is), it reaches that film only: no other film, no new ones, no list of the rest.
public actor ProjectRouter {
    private let defaultRuntime: ToolRuntime?
    private let library: ProjectLibrary
    private var runtimes: [String: ToolRuntime] = [:]

    public init(runtime: ToolRuntime? = nil, library: ProjectLibrary? = nil) throws {
        defaultRuntime = runtime
        self.library = try library ?? ProjectLibrary()
        if let runtime {
            runtimes[runtime.store.url.resolvingSymlinksInPath().path] = runtime
            try self.library.register(runtime.store)
        }
    }
    public func invoke(_ name: String, arguments: JSONValue = .object([:])) async throws -> ToolResponse {
        try ToolCatalog.validate(arguments, for: name)
        if let bound = defaultRuntime { return try await invoke(name, arguments: arguments, bound: bound) }
        switch name {
        case "direction_projects":
            return ToolResponse(.object(["projects": try .wrapping(library.list())]))
        case "direction_create_project":
            let url = try projectURL(arguments.requiredString("path"))
            guard url.pathExtension == "direction" else { throw DirectionError("invalid_project_path", "Use a .direction package path.") }
            let title = try arguments.requiredString("name").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw DirectionError("invalid_project_name", "Provide a project name.") }
            let store = try ProjectStore.create(at: url, name: title)
            let runtime = try ToolRuntime(store: store)
            runtimes[url.path] = runtime
            try library.register(store)
            return try await runtime.invoke("direction_inspect")
        case "direction_open_project":
            let url = try projectURL(arguments.requiredString("path"))
            let runtime = try runtime(at: url)
            try library.register(runtime.store)
            var result = try await runtime.invoke("direction_inspect")
            if arguments["showInApp"].bool == true {
                // Opening a document is part of the app's public interface. A failure is
                // reported in the result without pretending that the project failed to open.
                let shown = await MainActor.run { NSWorkspace.shared.open(url) }
                if case .object(var fields) = result.value { fields["shownInApp"] = .bool(shown); result.value = .object(fields) }
            }
            return result
        default:
            let target: ToolRuntime
            if let path = arguments["projectPath"].string { target = try runtime(at: projectURL(path)) }
            else if let defaultRuntime { target = defaultRuntime }
            else { throw DirectionError("project_required", "Pass projectPath on this call. Use direction_projects, direction_create_project, or direction_open_project first.") }
            return try await target.invoke(name, arguments: arguments)
        }
    }
    /// The one film this process was started for.
    private func invoke(_ name: String, arguments: JSONValue, bound: ToolRuntime) async throws -> ToolResponse {
        let own = bound.store.url.resolvingSymlinksInPath().path
        let outside = DirectionError("other_film", "This run is for \(bound.store.url.deletingPathExtension().lastPathComponent) only; other films are out of reach.")
        switch name {
        case "direction_projects":
            return ToolResponse(.object(["projects": try .wrapping(library.list().filter { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == own })]))
        case "direction_create_project": throw outside
        case "direction_open_project":
            guard try projectURL(arguments.requiredString("path")).path == own else { throw outside }
            return try await bound.invoke("direction_inspect")
        default:
            if let path = arguments["projectPath"].string, try projectURL(path).path != own { throw outside }
            return try await bound.invoke(name, arguments: arguments)
        }
    }
    private func projectURL(_ path: String) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw DirectionError("invalid_project_path", "Project paths must be absolute (or start with ~/).") }
        return URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()
    }
    private func runtime(at url: URL) throws -> ToolRuntime {
        if let existing = runtimes[url.path] { return existing }
        let runtime = try ToolRuntime(store: ProjectStore(url: url)); runtimes[url.path] = runtime
        try library.register(runtime.store)
        return runtime
    }
    public func cancelAll() async { for runtime in runtimes.values { await runtime.cancelAll() } }
}
