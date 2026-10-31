import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

@Test func unboundAgentCreatesAndRoutesMultipleProjectsWithoutImplicitSwitching() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-router-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let router = try ProjectRouter(library: ProjectLibrary(url: root.appendingPathComponent("library.sqlite")))
    var paths: [String] = []
    for name in ["First", "Second"] {
        let result = try await router.invoke("direction_create_project", arguments: .object(["path": .string(root.appendingPathComponent(name + ".direction").path), "name": .string(name)]))
        paths.append(try result.value.requiredString("projectPath"))
        #expect(result.value["project"]["name"].string == name)
    }
    let listing = try await router.invoke("direction_projects")
    #expect(listing.value["projects"].array?.count == 2)
    _ = try await router.invoke("direction_open_project", arguments: .object(["path": .string(paths[1])]))
    let first = try await router.invoke("direction_inspect", arguments: .object(["projectPath": .string(paths[0])]))
    #expect(first.value["project"]["name"].string == "First")
    do { _ = try await router.invoke("direction_inspect"); Issue.record("Should require an explicit project") }
    catch let error as DirectionError { #expect(error.code == "project_required") }
    do { _ = try await router.invoke("direction_create_project", arguments: .object(["path": .string(paths[0]), "name": .string("Overwrite")])); Issue.record("Should preserve existing project") }
    catch let error as DirectionError { #expect(error.code == "project_exists") }
    #expect(try ProjectStore(url: URL(fileURLWithPath: paths[0])).read().name == "First")
}

@Test func boundRuntimeRejectsMismatchedProjectAndRouterRejectsRelativePaths() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-routing-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ProjectStore.create(at: root.appendingPathComponent("First.direction"), name: "First")
    let runtime = try ToolRuntime(store: store)
    let router = try ProjectRouter(runtime: runtime, library: ProjectLibrary(url: root.appendingPathComponent("library.sqlite")))
    #expect(try await router.invoke("direction_inspect").value["project"]["name"].string == "First")
    do { _ = try await runtime.invoke("direction_inspect", arguments: .object(["projectPath": .string(root.appendingPathComponent("Other.direction").path)])); Issue.record("Should reject wrong target") }
    catch let error as DirectionError { #expect(error.code == "project_mismatch") }
    // Started for one film, it reaches that film only.
    let other = try ProjectStore.create(at: root.appendingPathComponent("Other.direction"), name: "Other")
    for (tool, args) in [("direction_inspect", ["projectPath": JSONValue.string(other.url.path)]), ("direction_open_project", ["path": .string(other.url.path)]),
                         ("direction_create_project", ["path": .string(root.appendingPathComponent("New.direction").path), "name": .string("New")])] {
        do { _ = try await router.invoke(tool, arguments: .object(args)); Issue.record("\(tool) reached another film") }
        catch let error as DirectionError { #expect(error.code == "other_film") }
    }
    #expect(try await router.invoke("direction_projects").value["projects"].array?.map { $0["name"].string } == ["First"])
    #expect(try await router.invoke("direction_open_project", arguments: .object(["path": .string(store.url.path)])).value["project"]["name"].string == "First")
    let unbound = try ProjectRouter(library: ProjectLibrary(url: root.appendingPathComponent("library.sqlite")))
    do { _ = try await unbound.invoke("direction_create_project", arguments: .object(["path": .string("relative.direction"), "name": .string("Relative")])); Issue.record("Should reject relative path") }
    catch let error as DirectionError { #expect(error.code == "invalid_project_path") }
}
