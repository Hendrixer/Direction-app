import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Direction's own look at each made way as it arrives (decisions.md › Judging made shots). Five frames are
/// asked whether anything in them is broken, the first and last whether the people and place stayed the
/// same, all five whether things move or morph, and whether the shot does what was asked.
///
/// Shadow for now: the check is recorded, shown and handed to the editor, and holds nothing back. Its
/// verdicts are compared with what the director keeps before any threshold is trusted.
public struct MadeCheck: Codable, Hashable, Sendable {
    public enum Verdict: String, Codable, Sendable { case clean, minor, broken }
    public struct Frame: Codable, Hashable, Sendable {
        /// Seconds into the made clip; 0 for a still.
        public var at: Double
        public var verdict: Verdict
        public var confidence: Double?
    }
    /// The worst thing any answer found.
    public var verdict: Verdict
    /// What was found, worst first: "Something looks broken at 0:03."
    public var findings: [String]
    public var frames: [Frame]
    /// Every answer as it came back, so thresholds can be set from them later.
    public var answers: [String: Decisions.Answer]
    /// The version that answered.
    public var version: String
    public var spend: Double?
    public var checkedAt: Double
    /// Recorded only: nothing was held back because of it.
    public var shadow: Bool

    /// Checks record and advise; none holds a way back yet.
    public static let holdsBack = false

    /// "Looks clean", "Slightly off", "Looks broken at 0:03".
    public var short: String {
        switch verdict {
        case .clean: return "Looks clean"
        case .minor: return "Slightly off"
        case .broken:
            let at = frames.first { $0.verdict == .broken }.map { MadeFormat.length($0.at) }
            return at.map { "Looks broken at \($0)" } ?? "Looks broken"
        }
    }

    /// What the editor reads in `direction_job`.
    public var forEditor: JSONValue {
        .object(["verdict": .string(verdict.rawValue), "findings": .array(findings.map(JSONValue.string)), "shadow": .bool(shadow),
                 "frames": .array(frames.map { .object(["at": .number(($0.at * 100).rounded() / 100), "verdict": .string($0.verdict.rawValue)]) })])
    }
}

public enum MadeChecker {
    /// Picture that can break the way made pictures do. Slow motion and sharpening are this Mac's or a
    /// service's work on real footage.
    public static func checks(_ kind: MadeKind) -> Bool { kind.isMadeShot || kind == .still }

    /// Start, a quarter, half, three quarters, and the last frame.
    public static func moments(duration: Double) -> [Double] {
        guard duration > 0.2 else { return [0] }
        return [0, duration * 0.25, duration * 0.5, duration * 0.75, max(0, duration - 0.1)]
    }

    /// "frame 3 of 5", or "the still" for one frame.
    static func name(_ i: Int, of n: Int) -> String { n == 1 ? "the picture" : "frame \(i + 1) of \(n)" }

    /// What one way is asked: its frames, each labelled with its place and time, then the ask; and the questions.
    public static func request(kind: MadeKind, ask: String, moments: [Double], frames: [Data]) -> (state: [Decisions.Part], questions: [String: Decisions.Question]) {
        let ask = ask.trimmingCharacters(in: .whitespacesAndNewlines), n = moments.count
        var state: [Decisions.Part] = [.text(n == 1 ? "A \(kind == .still ? "still" : "frame") made for a film:" : "\(n) frames of one shot made for a film, in order.")]
        for (i, frame) in zip(moments.indices, frames) {
            if n > 1 { state.append(.text("Frame \(i + 1) of \(n), at \(MadeFormat.length(moments[i]))\(i == 0 ? ", the start" : i == n - 1 ? ", the end" : ""):")) }
            state.append(.image(frame))
        }
        if !ask.isEmpty { state.append(.text("It was made from this description: \u{201C}\(ask)\u{201D}")) }
        return (state, questions(kind: kind, ask: ask, count: n))
    }

    static func questions(kind: MadeKind, ask: String, count n: Int) -> [String: Decisions.Question] {
        var q: [String: Decisions.Question] = [:]
        for i in 0..<n {
            q["look\(i + 1)"] = .init("Look only at \(name(i, of: n)). Is anything in it broken the way made pictures break?", [
                ("clean", "Everything looks physically real: faces, hands, bodies, objects, edges and the horizon are whole and correctly shaped."),
                ("minor", "Slightly soft, smeared or odd in a small area, but nothing a viewer would notice at a glance."),
                ("broken", "A face, hand or body is melted, warped, doubled or has the wrong number of parts; an object is malformed or fused into another; or the picture is garbled."),
            ])
        }
        if n > 1 {
            q["morph"] = .init("Frames 1 to \(n) are moments of one shot, in order. Do the things in it move the way real things move?", [
                ("moves", "People, objects and the place keep their shape and identity; what changes comes from motion, the camera moving, or light."),
                ("morphs", "Something changes shape or turns into something else, appears from nothing, vanishes, or melts between frames."),
            ])
            q["same"] = .init("Compare frame 1 with frame \(n). Is anyone in them still the same person, and is it still the same place?", [
                ("same", "The same people (face, hair, clothes) in the same place. A camera move that shows more of the place is still the same place, and a shot with no people can be the same."),
                ("drifted", "Someone's face, hair or clothes have turned into a different person's, or the place has become a different place."),
            ])
        }
        if !ask.isEmpty {
            q["asked"] = .init("Does the picture show what the description asks for, including its action and camera move?", [
                ("yes", "It shows what was asked."),
                ("partly", "Some of it, but the action, the camera move or something named is missing or different."),
                ("no", "It shows something else."),
            ])
        }
        return q
    }

    /// The check from the answers: the worst thing any of them found, in words.
    public static func check(from reply: Decisions.Reply, moments: [Double], now: Date = Date()) -> MadeCheck {
        var frames: [MadeCheck.Frame] = []
        for i in moments.indices {
            let a = reply.answers["look\(i + 1)"]
            frames.append(.init(at: moments[i], verdict: a.flatMap { MadeCheck.Verdict(rawValue: $0.choice) } ?? .clean, confidence: a?.confidence))
        }
        var broken: [String] = [], minor: [String] = []
        let times = { (v: MadeCheck.Verdict) in frames.filter { $0.verdict == v }.map { MadeFormat.length($0.at) } }
        func list(_ t: [String]) -> String { t.count < 2 ? t.joined() : t.dropLast().joined(separator: ", ") + " and " + t.last! }
        let still = moments.count == 1
        if !times(.broken).isEmpty { broken.append(still ? "Something in it looks broken." : "Something looks broken at \(list(times(.broken))).") }
        if reply.answers["morph"]?.choice == "morphs" { broken.append("Something changes shape or appears from nothing instead of moving.") }
        if reply.answers["same"]?.choice == "drifted" { broken.append("A person or the place turns into someone or somewhere else by the end.") }
        if reply.answers["asked"]?.choice == "no" { broken.append("It doesn\u{2019}t show what was asked.") }
        if !times(.minor).isEmpty { minor.append(still ? "It looks slightly off in places." : "Slightly off at \(list(times(.minor))).") }
        if reply.answers["asked"]?.choice == "partly" { minor.append("It shows only part of what was asked.") }
        let verdict: MadeCheck.Verdict = !broken.isEmpty ? .broken : !minor.isEmpty ? .minor : .clean
        return MadeCheck(verdict: verdict, findings: broken + minor, frames: frames, answers: reply.answers, version: reply.version, spend: reply.cost,
                         checkedAt: now.timeIntervalSince1970, shadow: !MadeCheck.holdsBack)
    }

    /// Checks one made file with every frame version at once. The first in `Decisions.frameVersions` that
    /// answers is the check; the others are kept beside it for comparing. Throws when none could check it;
    /// a made way never fails because of it.
    public static func check(_ url: URL, kind: MadeKind, ask: String, filmID: String?, turnoverID: String?, versions: [String] = Decisions.frameVersions) async throws -> (check: MadeCheck, others: [MadeCheck]) {
        if let cap = SharedSettings.spendStopAt, SpendLedger.monthSpent(SpendLedger.entries()) >= cap {
            throw DirectionError("spend_cap", "This month\u{2019}s limit is reached.")
        }
        let still = kind == .still
        let moments = still ? [0] : moments(duration: await MadeMedia.duration(url) ?? 0)
        var frames: [Data] = []
        for t in moments { frames.append(fitted(try await MadeMedia.frame(of: url.path, at: t, isImage: still, maxDimension: Decisions.frameSize), longSide: Decisions.frameSize)) }
        let (state, questions) = request(kind: kind, ask: ask, moments: moments, frames: frames)
        let replies = await withTaskGroup(of: (Int, Result<Decisions.Reply, Error>).self) { group in
            for (i, v) in versions.enumerated() {
                group.addTask {
                    do { return (i, .success(try await Decisions.ask(questions, state: state, version: v, spend: .checking, filmID: filmID, turnoverID: turnoverID))) }
                    catch { return (i, .failure(error)) }
                }
            }
            return await group.reduce(into: [Int: Result<Decisions.Reply, Error>]()) { $0[$1.0] = $1.1 }
        }
        var checks: [MadeCheck] = [], failures: [String] = []
        for i in versions.indices {
            switch replies[i] {
            case .success(let r)?: checks.append(check(from: r, moments: moments))
            case .failure(let e)?: failures.append("\(versions[i]): \(e.localizedDescription)")
            case nil: break
            }
        }
        guard let first = checks.first else { throw DirectionError("unchecked", failures.joined(separator: " ")) }
        return (first, Array(checks.dropFirst()))
    }

    /// Jev turns away frames under 256 px a side, so small ones are drawn up to `longSide`.
    static func fitted(_ jpeg: Data, longSide: Int) -> Data {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              min(image.width, image.height) < 256 else { return jpeg }
        let scale = Double(longSide) / Double(max(image.width, image.height))
        let w = Int((Double(image.width) * scale).rounded()), h = Int((Double(image.height) * scale).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return jpeg }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let out = NSMutableData()
        guard let scaled = ctx.makeImage(), let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return jpeg }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : jpeg
    }
}
