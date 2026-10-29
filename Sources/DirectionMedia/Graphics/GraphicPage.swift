import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers
import DirectionCore

// The offscreen page a graphic renders in (graphics.md › How Direction renders a graphic):
// a WKWebView at the sequence's pixel size, device pixel ratio 1, transparent; served through a
// private scheme; network blocked by a content rule list and the page's security policy.
// WKWebView runs in the `direction` command-line helper as well as the app: the helper's async main
// runs the main run loop, which is all WebKit needs (no window, no NSApplication.run).

/// What a page declares with `direction.graphic()`.
public struct GraphicDeclaration: Sendable {
    public var duration: Double
    public var words: [GraphicWord]
}

/// One run of visible text on a frame (runtime.js › inspect).
struct GraphicText: Decodable, Sendable {
    var text: String
    var word: String?
    var x: Double, y: Double, width: Double, height: Double
    var fontSize: Double
    /// sRGB 0–255 and alpha 0–1, opacity included.
    var color: [Double]
    /// Background colors right behind the text, nearest first; nil when a gradient or image is behind it.
    var backing: [[Double]]?
    /// "box" when the words don't fit their box, "picture" when they run off the frame.
    var overflow: String?
}
struct GraphicInspection: Decodable, Sendable { var width: Double; var height: Double; var texts: [GraphicText] }

/// A frame's pixels: premultiplied BGRA, sRGB, `width * 4` bytes a row.
public struct GraphicImage: Sendable {
    public var width: Int
    public var height: Int
    public var bytes: Data
    public var cgImage: CGImage? {
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    static func from(_ image: CGImage, width: Int, height: Int) throws -> GraphicImage {
        var bytes = Data(count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw DirectionError("graphic_snapshot_failed", "Couldn't read the graphic's frame.") }
        return GraphicImage(width: width, height: height, bytes: bytes)
    }
}

@MainActor
final class GraphicPage: NSObject, WKNavigationDelegate {
    struct PageError: Decodable, Sendable { var message: String; var source: String; var line: Int; var column: Int }
    struct Report: Decodable, Sendable { var errors: [PageError]; var consoleErrors: [String]; var internet: [String] }

    let folder: URL, width: Int, height: Int
    private let scheme: GraphicScheme
    private var web: WKWebView?
    private var navigation: CheckedContinuation<Void, Error>?
    private var crashed = false
    /// Top-level navigations away from the graphic, refused (graphics can't use the internet).
    private(set) var refused: [String] = []

    init(folder: URL, width: Int, height: Int) throws {
        self.folder = folder.standardizedFileURL; self.width = width; self.height = height
        scheme = GraphicScheme(folder: self.folder, web: try GraphicResources.required())
    }

    // MARK: Opening

    func open(words: [String: String], seed: UInt32) async throws -> GraphicDeclaration {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(scheme, forURLScheme: "direction")
        config.suppressesIncrementalRendering = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .nonPersistent()
        let setup = try JSONSerialization.data(withJSONObject: ["words": words, "seed": seed, "width": width, "height": height], options: [.sortedKeys])
        let content = config.userContentController
        content.addUserScript(WKUserScript(source: "window.__directionSetup = \(String(decoding: setup, as: UTF8.self));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addUserScript(WKUserScript(source: try GraphicResources.runtimeSource(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(try await Self.offline())

        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        Self.setDevicePixelRatioOne(view)
        view.navigationDelegate = self
        web = view

        try await withTimeout(10, DirectionError("graphic_timeout", "The graphic's page didn't load within 10 s.")) {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                self.navigation = c
                view.load(URLRequest(url: URL(string: "direction://graphic/index.html")!))
            }
        }
        try await check()
        let declared: Declared
        do {
            declared = try await call(Declared.self, "return JSON.stringify(await window.__direction.ready())", timeout: 2)
        } catch let e as DirectionError where e.code == "graphic_timeout" {
            try await check()
            throw DirectionError("graphic_not_declared", "index.html never called direction.graphic({ duration, words, render }).")
        }
        _ = try await call(Bool.self, "if (document.fonts) await document.fonts.ready; return 'true'", timeout: 2)
        let fields = declared.words.map { key, w in GraphicWord(key: key, label: w.label, text: w.text, maxLength: w.max.map { Int($0) }) }.sorted { $0.key < $1.key }
        return GraphicDeclaration(duration: declared.duration, words: fields)
    }
    private struct Declared: Decodable { struct Field: Decodable { var label: String; var text: String; var max: Double? }; var duration: Double; var words: [String: Field] }

    func setWords(_ words: [String: String]) async throws {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: words, options: [.sortedKeys]), as: UTF8.self)
        _ = try await call(Bool.self, "window.__direction.setWords(\(json)); return 'true'", timeout: 2)
    }

    // MARK: Frames

    /// Sets t, awaits render and fonts, and snapshots with alpha. Fails past 2 s, on a thrown error, or on any request for the internet.
    func frame(_ t: Double) async throws -> (image: GraphicImage, milliseconds: Double) {
        let started = Date()
        let image = try await withTimeout(2, DirectionError("graphic_frame_timeout", "The frame at \(String(format: "%.2f", t)) s took longer than 2 s to draw.")) {
            _ = try await self.call(Double.self, "return String(await window.__direction.frame(\(t)))", timeout: nil)
            try await self.check()
            return try await self.snapshot()
        }
        return (image, Date().timeIntervalSince(started) * 1000)
    }

    func inspect() async throws -> GraphicInspection { try await call(GraphicInspection.self, "return JSON.stringify(window.__direction.inspect())", timeout: 2) }

    func report() async throws -> Report {
        var r = try await call(Report.self, "return JSON.stringify(window.__direction.report())", timeout: 2)
        r.internet += refused
        r.consoleErrors += scheme.missing.map { $0 == "lib/gsap.js" ? "GSAP isn't bundled with Direction (its license); use anime.js." : "Not found: \($0)" }
        return r
    }

    /// The page's failures, worst first: the internet, then a thrown error with its line.
    func check() async throws {
        if crashed { throw DirectionError("graphic_crashed", "The graphic's page crashed.") }
        let r = try await report()
        if let url = r.internet.first { throw DirectionError("graphic_internet", "Graphics can't use the internet: \(url)") }
        if let e = r.errors.first {
            let place = e.line > 0 ? "\(e.source.isEmpty ? "index.html" : e.source):\(e.line): " : ""
            throw DirectionError("graphic_threw", "\(place)\(e.message)")
        }
    }

    func close() {
        web?.stopLoading(); web?.navigationDelegate = nil
        web?.configuration.userContentController.removeAllUserScripts()
        web = nil
    }

    // MARK: WebKit

    private func snapshot() async throws -> GraphicImage {
        guard let web else { throw DirectionError("graphic_closed", "The graphic's page is closed.") }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)
        config.snapshotWidth = NSNumber(value: width)
        config.afterScreenUpdates = true
        let image = try await web.takeSnapshot(configuration: config)
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw DirectionError("graphic_snapshot_failed", "Couldn't take the graphic's frame.") }
        return try GraphicImage.from(cg, width: width, height: height)
    }

    private func call<T: Decodable & Sendable>(_ type: T.Type, _ body: String, timeout: Double?) async throws -> T {
        guard let web else { throw DirectionError("graphic_closed", "The graphic's page is closed.") }
        let run: @MainActor @Sendable () async throws -> T = {
            let value: Any?
            do { value = try await web.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page) }
            catch { throw DirectionError("graphic_threw", Self.describe(error)) }
            guard let text = value as? String else { throw DirectionError("graphic_threw", "The graphic's page returned nothing.") }
            if T.self == Bool.self { return true as! T }
            if T.self == Double.self { return (Double(text) ?? 0) as! T }
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        }
        guard let timeout else { return try await run() }
        return try await withTimeout(timeout, DirectionError("graphic_timeout", "The graphic's page stopped answering."), run)
    }

    private static func describe(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        let message = info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
        if let line = info["WKJavaScriptExceptionLineNumber"] as? Int, line > 0 { return "line \(line): \(message)" }
        return message
    }

    /// Device pixel ratio 1 whatever the screen: one CSS pixel is one pixel of the frame.
    private static func setDevicePixelRatioOne(_ view: WKWebView) {
        let selector = NSSelectorFromString("_setOverrideDeviceScaleFactor:")
        guard view.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        unsafeBitCast(view.method(for: selector), to: Setter.self)(view, selector, 1)
    }

    /// Blocks every request to the network. Compiled once per process.
    private static var compiledRules: WKContentRuleList?
    static func offline() async throws -> WKContentRuleList {
        if let compiledRules { return compiledRules }
        // Content rule regexes have no alternation: one rule per scheme.
        let rules = "[" + ["^https?://", "^wss?://", "^ftp://"].map { #"{"trigger":{"url-filter":"\#($0)"},"action":{"type":"block"}}"# }.joined(separator: ",") + "]"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dev.direction.graphics-rules", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WKContentRuleListStore(url: directory) ?? WKContentRuleListStore.default()!
        let list = try await store.compileContentRuleList(forIdentifier: "direction-graphics-offline-v1", encodedContentRuleList: rules)
        guard let list else { throw DirectionError("graphics_unavailable", "Couldn't block the network for graphics.") }
        compiledRules = list
        return list
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if ["direction", "about", "data", "blob"].contains(url.scheme?.lowercased() ?? "") { return .allow }
        refused.append(url.absoluteString)
        return .cancel
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { self.navigation?.resume(); self.navigation = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { self.navigation?.resume(throwing: DirectionError("graphic_load_failed", error.localizedDescription)); self.navigation = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let missing = scheme.missing.contains("index.html")
        self.navigation?.resume(throwing: DirectionError(missing ? "graphic_not_found" : "graphic_load_failed", missing ? "The graphic's folder has no index.html." : error.localizedDescription)); self.navigation = nil
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { crashed = true; self.navigation?.resume(throwing: DirectionError("graphic_crashed", "The graphic's page crashed.")); self.navigation = nil }
}

/// Serves `direction://graphic/…` from the graphic's folder only, and `direction:lib/…` and
/// `direction:fonts/…` from Direction's own resources. Nothing else.
final class GraphicScheme: NSObject, WKURLSchemeHandler {
    let folder: URL, web: URL
    private(set) var missing: [String] = []
    /// Everything the page may load comes from Direction; the browser refuses the rest and says which URL.
    static let policy = "default-src 'self' direction: data: blob: 'unsafe-inline' 'unsafe-eval'"

    init(folder: URL, web: URL) { self.folder = folder; self.web = web }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        var status = 200, body = Data(), path = ""
        if let file = resolve(url, path: &path), let data = try? Data(contentsOf: file) {
            body = file.pathExtension.lowercased() == "html" && file.deletingLastPathComponent().standardizedFileURL.path.hasPrefix(folder.path) ? Self.inject(data) : data
        } else {
            status = 404
            if !missing.contains(path) { missing.append(path) }
        }
        var headers = ["Content-Type": Self.mime(path), "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store", "Content-Security-Policy": Self.policy]
        headers["Content-Length"] = String(body.count)
        task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(body)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    /// Maps a URL to a file, or nil. The graphic's folder can't be escaped with `..` or links.
    private func resolve(_ url: URL, path: inout String) -> URL? {
        var s = url.absoluteString
        if let i = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<i]) }
        s = s.removingPercentEncoding ?? s
        let base: URL, rest: String
        if s.hasPrefix("direction://graphic/") { base = folder; rest = String(s.dropFirst("direction://graphic/".count)) }
        else if s.hasPrefix("direction://lib/") { base = web.appendingPathComponent("lib"); rest = String(s.dropFirst("direction://lib/".count)); path = "lib/" + rest; return library(rest) }
        else if s.hasPrefix("direction:lib/") { rest = String(s.dropFirst("direction:lib/".count)); path = "lib/" + rest; return library(rest) }
        else if s.hasPrefix("direction:fonts/") || s.hasPrefix("direction://fonts/") { base = web.appendingPathComponent("fonts"); rest = s.components(separatedBy: "fonts/").dropFirst().joined(separator: "fonts/") }
        else { path = s; return nil }
        path = rest.isEmpty ? "index.html" : rest
        let file = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        let root = base.standardizedFileURL.resolvingSymlinksInPath().path
        guard file.path.hasPrefix(root + "/"), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    /// `anime.js`, `d3.js`, `three.js` (classic, global THREE), `three.module.js` (ES module), `lottie.js`.
    private func library(_ name: String) -> URL? {
        let plain = name.replacingOccurrences(of: ".min.js", with: ".js")
        let known = GraphicResources.libraries.map { "\($0).js" } + ["three.module.js"]
        guard known.contains(plain) else { return nil }
        return web.appendingPathComponent("lib").appendingPathComponent(plain)
    }

    /// The policy as the page's first element too, so it holds even for files a page opens itself.
    static func inject(_ html: Data) -> Data {
        var text = String(decoding: html, as: UTF8.self)
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
        if let head = text.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) { text.insert(contentsOf: meta, at: head.upperBound) }
        else { text = meta + text }
        return Data(text.utf8)
    }

    static func mime(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "wasm": return "application/wasm"
        default: return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}

/// Resumes once: with the body's result, or with `failure` after `seconds`. A body that never
/// returns (a page stuck in a loop) is abandoned rather than awaited.
@MainActor
func withTimeout<T: Sendable>(_ seconds: Double, _ failure: DirectionError, _ body: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
    let once = Once<T>()
    return try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
        once.continuation = c
        let work = Task { @MainActor in
            do { once.resume(.success(try await body())) } catch { once.resume(.failure(error)) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if once.resume(.failure(failure)) { work.cancel() }
        }
    }
}

@MainActor
private final class Once<T: Sendable> {
    var continuation: CheckedContinuation<T, Error>?
    @discardableResult func resume(_ result: Result<T, Error>) -> Bool {
        guard let c = continuation else { return false }
        continuation = nil
        c.resume(with: result)
        return true
    }
}
