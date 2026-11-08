import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import DirectionCore

/// Writes the cut for another editing app (Interchange, issue #4): a folder with the FCPXML timeline, the
/// stretches only Direction draws rendered as ProRes, the sound as the cut plays it (the mix and each track on
/// its own, as WAV), the look as LUTs, and a read-me saying what's where and what didn't go across.
public enum InterchangeExport {
    public struct Request: Sendable {
        public var project: Project
        public var sequenceID: String?
        public var filmName: String
        public var cutName: String
        public var dailies: Dailies
        public var notes: [ReviewComment]
        public var looks: LookContext?
        public var cacheDirectory: URL
        /// The folder to make. It must not exist: Direction never overwrites.
        public var folder: URL
        public init(project: Project, sequenceID: String?, filmName: String, cutName: String, dailies: Dailies, notes: [ReviewComment], looks: LookContext?, cacheDirectory: URL, folder: URL) {
            self.project = project; self.sequenceID = sequenceID; self.filmName = filmName; self.cutName = cutName; self.dailies = dailies; self.notes = notes; self.looks = looks; self.cacheDirectory = cacheDirectory; self.folder = folder
        }
    }

    public static func write(_ r: Request, phase: @escaping @Sendable (String) -> Void = { _ in }) async throws -> JSONValue {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: r.folder.path) else { throw DirectionError("destination_exists", "Choose a new folder; Direction does not overwrite.") }
        let p = r.project, s = try p.sequence(r.sequenceID)
        guard s.duration > .zero else { throw DirectionError("empty_sequence", "There\u{2019}s nothing in this cut to export.") }
        let plan = Interchange.plan(project: p, sequence: s, looks: r.looks, dailies: r.dailies)
        // Written beside the destination and moved into place whole, so a stopped export leaves nothing half made.
        // The timeline names files where they'll be.
        clearLeftovers(beside: r.folder)
        let temp = r.folder.deletingLastPathComponent().appendingPathComponent(".direction-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        func inside(_ path: String) -> (temp: URL, final: URL) { (temp.appendingPathComponent(path), r.folder.appendingPathComponent(path)) }
        func safe(_ name: String) -> String { name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
        func asset(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in p.assets.first { $0.id == id } } }
        do {
            // Where each file's timecode starts, so other apps find the same frames.
            var sources: [String: Interchange.SourceFacts] = [:]
            for a in p.assets where s.clips.contains(where: { $0.assetID == a.id }) && a.graphic == nil && !a.isImage {
                if let start = await timecodeStart(URL(fileURLWithPath: a.path)) { sources[a.id] = .init(timecodeStart: start) }
            }

            // The stretches only Direction draws: everything up to that layer, with each take's camera LUT and
            // balance, without the look (that goes out as a LUT) and without sound (the timeline keeps it).
            var rendered: [String: URL] = [:]
            let cameraOnly = r.looks.map { LookContext(look: FilmLook(), sceneForAsset: $0.sceneForAsset, cameraLUTs: $0.cameraLUTs) }
            for (k, render) in plan.renders.enumerated() {
                try Task.checkCancellation()
                phase("Rendering \(k + 1) of \(plan.renders.count): \(render.reasons.joined(separator: ", "))")
                var q = p, seq = s
                seq.clips = s.clips.filter { $0.kind != .audio && $0.layer <= render.upToLayer }.map { c in
                    var c = c
                    for stream in asset(c)?.audio ?? [] { var set = c.audioOverrides[String(stream.id)] ?? stream.settings; set.muted = true; c.audioOverrides[String(stream.id)] = set }
                    return c
                }
                q.sequences = p.sequences.map { $0.id == s.id ? seq : $0 }
                let compiled = try await SequenceRenderer.compile(project: q, sequenceID: s.id, cacheDirectory: r.cacheDirectory, looks: cameraOnly)
                let file = inside("Renders/\(safe(render.name)).mov")
                try fm.createDirectory(at: file.temp.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try await SequenceRenderer.export(compiled, to: file.temp, preset: "prores", range: MediaRange(start: render.start, end: min(render.end, compiled.sequence.duration.seconds)))
                rendered[render.id] = file.final
            }

            // The sound as the cut plays it: the mix, then each track on its own, every file the cut's length.
            var stems: [String] = []
            let length = s.duration.seconds
            var groups: [(name: String, keep: (Clip) -> Bool)] = [("Mix", { _ in true }), ("A1 Dialogue", { $0.layer == 0 })]
            for layer in Set(s.clips.filter { $0.kind == .audio && $0.layer > 0 }.map(\.layer)).sorted() {
                let clips = s.clips.filter { $0.kind == .audio && $0.layer == layer }
                let music = clips.allSatisfy { c in asset(c).map { $0.song != nil || layer == 1 } ?? false }
                let name = "A\(layer + 1) " + (music ? "Music" : layer == 2 ? "Effects" : "Sound")
                groups.append((name, { $0.kind == .audio && $0.layer == layer }))
            }
            for layer in Set(s.clips.filter { $0.kind == .video && $0.layer > 0 && Interchange.audible($0, asset($0)) }.map(\.layer)).sorted() {
                groups.append(("V\(layer + 1) Sound", { $0.kind == .video && $0.layer == layer }))
            }
            for g in groups {
                try Task.checkCancellation()
                var seq = s
                seq.clips = s.clips.filter { g.keep($0) && $0.kind != .title }
                guard seq.clips.contains(where: { Interchange.audible($0, asset($0)) || ($0.kind == .audio && asset($0) != nil) }) else { continue }
                phase("Writing the sound: \(g.name)")
                var q = p
                q.sequences = p.sequences.map { $0.id == s.id ? seq : $0 }
                let compiled = try await SequenceRenderer.compile(project: q, sequenceID: s.id, cacheDirectory: r.cacheDirectory, looks: nil)
                let file = inside("Sound/\(safe(r.filmName)) \u{2013} \(g.name).wav")
                if try await writeSound(compiled, length: length, to: file.temp) { stems.append(g.name) }
            }

            // The look as LUTs: the film's, each scene's own, and the camera LUTs for log takes.
            var lookFiles: [String] = [], cameraFiles: [String] = []
            if let looks = r.looks {
                var named: [(String, LookSettings)] = []
                if let film = looks.look.film, !film.isNone { named.append(("Look", film)) }
                for (id, look) in looks.look.scenes.sorted(by: { $0.key < $1.key }) where !look.isNone {
                    let number = r.dailies.scenes.first { $0.id == id }?.number
                    named.append(("Look \u{2013} Scene \(number.map(String.init) ?? id)", look))
                }
                for (name, look) in named {
                    guard let text = cube(look) else { continue }
                    let file = inside("\(safe(name)).cube")
                    try text.write(to: file.temp, atomically: true, encoding: .utf8)
                    lookFiles.append(file.final.lastPathComponent)
                }
            }
            // Camera LUTs as the renderer picks them: a take's own .cube, none when it's "none", else the one matched
            // to its log footage. Two files of one name get " 2".
            var byPath: [String: [String]] = [:]
            for a in p.assets where s.clips.contains(where: { $0.assetID == a.id && $0.kind == .video }) {
                let path: String? = switch a.cameraLUT { case let x? where x.hasSuffix(".cube"): x; case "none": nil; default: r.looks?.cameraLUTs[a.id] }
                if let path, fm.fileExists(atPath: path) { byPath[path, default: []].append(a.name) }
            }
            var names = Set<String>()
            for (path, takes) in byPath.sorted(by: { $0.key < $1.key }) {
                let source = URL(fileURLWithPath: path)
                var name = source.lastPathComponent, n = 2
                while !names.insert(name.lowercased()).inserted { name = source.deletingPathExtension().lastPathComponent + " \(n).cube"; n += 1 }
                let file = inside("Camera LUTs/\(name)")
                try fm.createDirectory(at: file.temp.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: file.temp)
                cameraFiles.append("\(name) for \(takes.sorted().joined(separator: ", "))")
            }

            phase("Writing the timeline")
            let xml = try Interchange.fcpxml(.init(project: p, sequence: s, filmName: r.filmName, cutName: r.cutName, dailies: r.dailies, notes: r.notes, plan: plan, rendered: rendered, sources: sources))
            let timeline = inside("\(safe(r.filmName)) \u{2013} \(safe(r.cutName)).fcpxml")
            try xml.write(to: timeline.temp, atomically: true, encoding: .utf8)
            let readMe = Interchange.readMe(filmName: r.filmName, cutName: r.cutName, timeline: timeline.final.lastPathComponent, plan: plan, stems: stems, looks: lookFiles, cameraLUTs: cameraFiles)
            try readMe.write(to: inside("Read Me.txt").temp, atomically: true, encoding: .utf8)
            try Task.checkCancellation()
            try fm.createDirectory(at: r.folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: temp, to: r.folder)
            return .object([
                "path": .string(r.folder.path), "timeline": .string(timeline.final.path), "format": .string("FCPXML 1.10"),
                "renders": .array(plan.renders.map { .object(["name": .string($0.name), "start": .number($0.start), "end": .number($0.end), "why": .string($0.reasons.joined(separator: ", "))]) }),
                "sound": .array(stems.map(JSONValue.string)), "looks": .array(lookFiles.map(JSONValue.string)), "cameraLUTs": .array(cameraFiles.map(JSONValue.string)),
                "notes": .array(plan.notes.map(JSONValue.string)), "editRevision": .number(Double(p.editRevision)), "sequenceID": .string(s.id),
            ])
        } catch { try? fm.removeItem(at: temp); throw error }
    }

    /// The first frame's timecode, in seconds of the file's own time (frames × frame length, as FCPXML counts it).
    /// A sound recorder's WAV keeps it as the Broadcast Wave time reference instead.
    public static func timecodeStart(_ url: URL) async -> Double? {
        if ["wav", "bwf"].contains(url.pathExtension.lowercased()) { return broadcastWaveStart(url) }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .timecode).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { ReadStall.cancel(reader) }
        // The reader can hand back an empty sample first, and a sample read as it is may not carry its
        // description; the track's has the same.
        let described = try? await track.load(.formatDescriptions).first
        var found: (CMSampleBuffer, CMBlockBuffer)?
        for _ in 0..<8 {
            guard let sample = await output.nextSample(of: reader) else { break }
            if CMSampleBufferGetNumSamples(sample) > 0, let data = CMSampleBufferGetDataBuffer(sample) { found = (sample, data); break }
        }
        guard let (sample, data) = found, let format = CMSampleBufferGetFormatDescription(sample) ?? described else { return nil }
        let frameLength = CMTimeCodeFormatDescriptionGetFrameDuration(format)
        guard frameLength.isValid, frameLength.seconds > 0 else { return nil }
        let frame: Int64
        switch CMFormatDescriptionGetMediaSubType(format) {
        case kCMTimeCodeFormatType_TimeCode32:
            var v: Int32 = 0
            guard CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: 4, destination: &v) == kCMBlockBufferNoErr else { return nil }
            frame = Int64(Int32(bigEndian: v))
        case kCMTimeCodeFormatType_TimeCode64:
            var v: Int64 = 0
            guard CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: 8, destination: &v) == kCMBlockBufferNoErr else { return nil }
            frame = Int64(bigEndian: v)
        default: return nil
        }
        // The timecode sample is for the track's first moment; a track that starts later counts from there.
        let offset = (try? await track.load(.timeRange).start.seconds) ?? 0
        return max(0, Double(frame) * frameLength.seconds - offset)
    }

    /// A Broadcast Wave's start: its bext chunk's time reference (samples since midnight) over its sample rate.
    static func broadcastWaveStart(_ url: URL) -> Double? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        func read(_ n: Int) -> Data? { let d = try? file.read(upToCount: n); return d?.count == n ? d : nil }
        func u32(_ d: Data, _ at: Int) -> UInt32 { d[d.startIndex + at ..< d.startIndex + at + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
        guard let head = read(12), head.prefix(4) == Data("RIFF".utf8), head.suffix(4) == Data("WAVE".utf8) else { return nil }
        var rate: Double?, reference: UInt64?
        // The chunks before the sound: fmt and bext come first in every recorder's files.
        for _ in 0..<64 {
            guard let chunk = read(8) else { break }
            let id = String(decoding: chunk.prefix(4), as: UTF8.self), size = Int(u32(chunk, 4))
            if id == "fmt ", let d = read(size) { rate = Double(u32(d, 4)) }
            else if id == "bext", size >= 346, let d = read(size) { reference = UInt64(u32(d, 338)) | UInt64(u32(d, 342)) << 32 }
            else if id == "data" { break }
            else { guard (try? file.seek(toOffset: file.offsetInFile + UInt64(size))) != nil else { break } }
            if size % 2 == 1 { _ = read(1) }
            if rate != nil && reference != nil { break }
        }
        guard let rate, rate > 0, let reference, reference > 0 else { return nil }
        return Double(reference) / rate
    }

    /// Folders a stopped export left beside its destination (`.direction-<uuid>`, made more than six hours ago), to the Trash.
    static func clearLeftovers(beside folder: URL) {
        let fm = FileManager.default, parent = folder.deletingLastPathComponent()
        let old = Date().addingTimeInterval(-6 * 3600)
        for url in (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])) ?? [] {
            let name = url.lastPathComponent
            guard name.hasPrefix(".direction-"), UUID(uuidString: String(name.dropFirst(11))) != nil,
                  let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]), v.isDirectory == true, (v.contentModificationDate ?? .now) < old else { continue }
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }
    }

    /// The cut's sound as a 48 kHz 24-bit stereo WAV exactly `length` seconds long. False when there's no sound.
    static func writeSound(_ compiled: CompiledSequence, length: Double, to url: URL) async throws -> Bool {
        let tracks = try await compiled.composition.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return false }
        let reader = try AVAssetReader(asset: compiled.composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: compiled.sequence.duration.cmTime)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        let mix = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings); mix.audioMix = compiled.audioMix
        reader.add(mix)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true)!
        let fileSettings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        let file = try AVAudioFile(forWriting: url, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: true)
        // Counted here: the file's own length lags while it converts to 24-bit.
        let total = AVAudioFramePosition((length * 48_000).rounded())
        var written: AVAudioFramePosition = 0
        guard reader.startReading() else { throw reader.error ?? DirectionError("sound_failed", "Can\u{2019}t read the cut\u{2019}s sound.") }
        do {
            while written < total {
                try Task.checkCancellation()
                guard let sample = await mix.nextSample(of: reader) else {
                    // The end of the sound, or a read that stopped: only the first is padded with silence.
                    try ReadStall.check(reader, "the cut\u{2019}s sound")
                    guard reader.status == .completed else { throw reader.error ?? DirectionError("sound_failed", "Writing the sound stopped partway.") }
                    break
                }
                let n = min(AVAudioFramePosition(CMSampleBufferGetNumSamples(sample)), total - written)
                guard n > 0, let data = CMSampleBufferGetDataBuffer(sample), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
                      let pointer = buffer.mutableAudioBufferList.pointee.mBuffers.mData else { continue }
                buffer.frameLength = AVAudioFrameCount(n)
                guard CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: Int(n) * 8, destination: pointer) == kCMBlockBufferNoErr else { throw DirectionError("sound_failed", "The cut\u{2019}s sound came back unreadable.") }
                try file.write(from: buffer)
                written += n
            }
            ReadStall.cancel(reader)
            // Silence to the end of the cut, so every file lines up.
            while written < total {
                let n = min(48_000, total - written)
                guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { break }
                silence.frameLength = AVAudioFrameCount(n)
                if let p = silence.mutableAudioBufferList.pointee.mBuffers.mData { memset(p, 0, Int(n) * 8) }
                try file.write(from: silence)
                written += n
            }
            return true
        } catch { ReadStall.cancel(reader); try? FileManager.default.removeItem(at: url); throw error }
    }

    /// A look's color as a 33-point .cube: its LUT at its strength. Filters that aren't color (grain, a vignette,
    /// letterbox) can't go in one, and the read-me says so; nil when there's no LUT to carry.
    static func cube(_ look: LookSettings) -> String? {
        guard let path = look.lut, let lut = try? CubeLUT.load(URL(fileURLWithPath: path)) else { return nil }
        let strength = Float(max(0, min(1, look.strength)))
        guard strength < 1 || lut.kind != .threeD || lut.size != 33 else { return (try? String(contentsOfFile: path, encoding: .utf8)) ?? lut.text }
        return CubeLUT.make(size: 33, title: look.name) { c in c + (lut.sample(c) - c) * strength }.text
    }
}
