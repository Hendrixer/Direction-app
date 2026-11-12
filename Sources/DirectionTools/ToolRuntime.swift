import Foundation
import Darwin
import DirectionCore
import DirectionMedia

public struct ToolResponse: Sendable {
    public var value: JSONValue
    public var imagePaths: [String] = []
    public var audioPaths: [String] = []
    public init(_ value: JSONValue, imagePaths: [String] = [], audioPaths: [String] = []) { self.value = value; self.imagePaths = imagePaths; self.audioPaths = audioPaths }
}

public actor ToolRuntime {
    public nonisolated let store: ProjectStore
    public nonisolated let cacheDirectory: URL
    private var tasks: [String: Task<Void, Never>] = [:]

    public init(store: ProjectStore) throws {
        self.store = store
        cacheDirectory = DirectionPaths.cache(forFilm: try store.read().id)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Every tool call, from the app or the editor. A call that fails goes in Direction's log.
    public func invoke(_ name: String, arguments a: JSONValue = .object([:])) async throws -> ToolResponse {
        do { return try await dispatch(name, a) }
        catch is CancellationError { throw CancellationError() }
        catch {
            let code = (error as? DirectionError)?.code
            DirectionLog.warning("\(name) failed\(code.map { " (\($0))" } ?? ""): \(error.localizedDescription)", "tools")
            throw error
        }
    }

    private func dispatch(_ name: String, _ a: JSONValue) async throws -> ToolResponse {
        noteToolCall(name, a)
        try Task.checkCancellation()
        try ToolCatalog.validate(a, for: name)
        if let path = a["projectPath"].string {
            let requested = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
            guard requested.path == store.url.resolvingSymlinksInPath().path else { throw DirectionError("project_mismatch", "The requested project differs from this bound runtime.") }
        }
        switch name {
        case "direction_capabilities":
            return ToolResponse(.object(["version": .string("0.2.0"), "gpu": .string(GPUCompositor.deviceName ?? "unavailable"), "transcription": await LocalTranscriber.availability(), "whisper": WhisperTranscriber.availability(), "transcriptionEngine": .string(SharedSettings.transcriptionEngine.rawValue), "tools": .array(ToolCatalog.definitions.map { .object(["name": .string($0.name), "does": .string(ToolCatalog.firstSentence($0.description))]) }), "timeContract": .string("Canonical media times are {value,timescale}; ranges are half-open. Convenience start/end parameters use seconds. Comments and renders pin editRevision. Text editing deletes existing timed words; it does not synthesize speech."), "feedbackLoop": .string("Read direction_feedback at the beginning of each user-requested revision. Saving a comment does not wake the external agent.")]))
        case "direction_inspect":
            let p = try store.read(revision: a["revision"].int), sequence = try p.sequence(a["sequenceID"].string)
            // The sequence once, not again inside the project, and no bookmarks (a kilobyte of base64 per take
            // that only Direction reads); the other sequences by name.
            var project = try JSONValue.wrapping(p)
            if case .object(var fields) = project {
                fields["sequences"] = .array(p.sequences.map { .object(["id": .string($0.id), "name": .string($0.name), "durationSeconds": .number($0.duration.seconds), "clips": .number(Double($0.clips.count))]) })
                if case .array(let assets) = fields["assets"] ?? .null { fields["assets"] = .array(assets.map { asset in guard case .object(var a) = asset else { return asset }; a["bookmark"] = nil; return .object(a) }) }
                project = .object(fields)
            }
            return ToolResponse(.object(["project": project, "sequence": try .wrapping(sequence), "durationSeconds": .number(sequence.duration.seconds), "projectPath": .string(store.url.path), "eventCursor": .number(Double(try store.eventCursor()))]))
        case "direction_import":
            // A sound or image from the library comes in as the film's own copy, never as footage (library.md).
            if let name = a["library"].string { return try await importFromLibrary(name, a) }
            let path = try a.requiredString("path")
            let original = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
            if let shelf = MediaLibrary.holding(original), let item = shelf.items().first(where: { shelf.url($0).standardizedFileURL.resolvingSymlinksInPath() == original }) { return try await importFromLibrary(item.file, a) }
            var file = original
            // HDR comes in as an SDR copy in the film's Footage folder, and a file with open keyframes as a
            // copy that plays from any frame; the original stays as it is.
            let hdr = await SDRCopy.isHDR(original), seekable = hdr ? false : await SeekableCopy.isNeeded(original)
            if hdr || seekable {
                guard try !store.read().assets.contains(where: { $0.sdrCopyOf == original.path || $0.seekableCopyOf == original.path }) else { throw DirectionError("already_imported", "This file is already in the project, as Direction\u{2019}s copy of it.") }
                let copies = MediaAsset.copies(in: store.url)
                file = hdr ? try await SDRCopy.make(original, in: copies) : try await SeekableCopy.make(original, in: copies)
            }
            let output: Project, asset: MediaAsset
            do {
                var inspected = try await MediaInspector.inspect(url: file, thumbnailDirectory: cacheDirectory.appendingPathComponent("Thumbnails"))
                if hdr { inspected.sdrCopyOf = original.path } else if seekable { inspected.seekableCopyOf = original.path }
                asset = inspected
                let p = try store.read()
                output = try store.addAsset(asset, append: a["append"].bool ?? false, sequenceID: a["sequenceID"].string, frameRate: a["frameRate"].double.map(FrameRate.nearest), expectedRevision: a["baseEditRevision"].int ?? p.editRevision, key: a["idempotencyKey"].string ?? UUID().uuidString)
            } catch {
                // A copy no take uses isn't kept.
                if file != original { try? FileManager.default.removeItem(at: file) }
                throw error
            }
            let saved = try output.assets.first(where: { $0.path == asset.path }) ?? output.asset(asset.id)
            return ToolResponse(.object(["asset": try .wrapping(saved), "editRevision": .number(Double(output.editRevision))]))
        case "direction_edit": return try await invokeEdit(a)
        case "direction_add_comment":
            let p = try store.read(revision: a["revision"].int)
            guard (a["start"] == .null) == (a["end"] == .null), a["time"] == .null || a["start"] == .null else { throw DirectionError("invalid_arguments", "Use time for a moment, start and end for a range, or neither for the whole cut.") }
            let range = a["end"].double != nil ? try secondsRange(a) : nil
            let time = range == nil ? try optionalTime(a["time"]) : nil
            let region: FrameRegion? = a["region"] == .null ? nil : try a["region"].decode(FrameRegion.self)
            let c = try store.addComment(text: a.requiredString("text"), author: a["author"].string ?? "Director", sequenceID: a["sequenceID"].string, revision: p.editRevision, cutID: a["cutID"].string, range: range, time: time, region: region)
            return ToolResponse(try c.forEditor())
        case "direction_feedback":
            // Drafts, dropped notes and outside notes the director hasn't accepted stay private.
            let comments = try store.comments(since: Int64(a["since"].int ?? 0))
            return ToolResponse(.object(["comments": .array(try comments.filter(\.visibleToEditor).map { try $0.forEditor() }), "nextCursor": .number(Double(comments.last?.cursor ?? Int64(a["since"].int ?? 0))), "hasMore": .bool(comments.count == 500)]))
        case "direction_feedback_context":
            return try await feedbackContext(id: a.requiredString("commentID"), includeMedia: a["includeMedia"].bool ?? true, includeAudio: a["includeAudio"].bool ?? true)
        case "direction_feedback_reply":
            let updated = try store.reply(commentID: a.requiredString("commentID"), text: a.requiredString("text"), author: a["author"].string ?? "Agent", revision: a["revision"].int, status: a["status"].string)
            return ToolResponse(try updated.forEditor())
        case "direction_create_cut":
            return ToolResponse(try .wrapping(store.createCut(name: a.requiredString("name"), sequenceID: a["sequenceID"].string, revision: a["revision"].int)))
        case "direction_cuts": return ToolResponse(try .wrapping(store.cuts()))
        case "direction_restore": return ToolResponse(try .wrapping(store.restore(revision: try requiredInt(a, "revision"), expectedRevision: try baseRevision(a), key: a["idempotencyKey"].string ?? UUID().uuidString, keepingLocks: true)))
        case "direction_transcript":
            let offset = max(0, a["offset"].int ?? 0), limit = min(5_000, max(1, a["limit"].int ?? 300))
            if let assetID = a["assetID"].string {
                // A take's own words: the transcript chosen last, if it has more than one track.
                _ = try store.read().asset(assetID)
                guard let t = try store.transcripts().filter({ $0.assetID == assetID }).max(by: { ($0.selectedAt ?? 0) < ($1.selectedAt ?? 0) }) else {
                    return ToolResponse(.object(["assetID": .string(assetID), "words": .array([]), "text": .string(""), "total": .number(0), "nextOffset": .null, "note": .string("This take has no transcript yet.")]))
                }
                let words = Array(t.words.dropFirst(offset).prefix(limit)), next = min(t.words.count, offset + words.count)
                let timed: [JSONValue] = words.map { .object(["id": .string($0.id), "text": .string($0.text), "start": .number(($0.range.start.seconds * 100).rounded() / 100), "end": .number(($0.range.end.seconds * 100).rounded() / 100)]) }
                return ToolResponse(.object(["assetID": .string(assetID), "audioTrackID": .number(Double(t.audioTrackID)), "provider": .string(t.provider), "words": .array(timed), "text": .string(words.map(\.text).joined(separator: " ")), "total": .number(Double(t.words.count)), "nextOffset": next < t.words.count ? .number(Double(next)) : .null]))
            }
            let p = try store.read(revision: a["revision"].int), all = TranscriptEditing.words(in: try p.sequence(a["sequenceID"].string), transcripts: try store.transcripts())
            let words = Array(all.dropFirst(offset).prefix(limit)), next = min(all.count, offset + words.count)
            // Each word as the editor uses it: its id for word cuts, and where it is in cut seconds.
            let timed: [JSONValue] = words.map { .object(["id": .string($0.id), "text": .string($0.text), "start": .number(($0.range.start.seconds * 100).rounded() / 100), "end": .number(($0.range.end.seconds * 100).rounded() / 100)]) }
            return ToolResponse(.object(["editRevision": .number(Double(p.editRevision)), "words": .array(timed), "total": .number(Double(all.count)), "nextOffset": next < all.count ? .number(Double(next)) : .null]))
        case "direction_import_transcript":
            let t = try a["transcript"].decode(SourceTranscript.self); try store.saveTranscript(t)
            return ToolResponse(.object(["assetID": .string(t.assetID), "wordCount": .number(Double(t.words.count))]))
        case "direction_transcribe":
            let p = try store.read(), asset = try p.asset(a.requiredString("assetID"))
            guard let track = a["trackID"].int.flatMap(Int32.init(exactly:)) ?? asset.audio.first(where: { !$0.settings.muted })?.id ?? asset.audio.first?.id else { throw DirectionError("no_audio", "Choose an asset with an audio track.") }
            let language = a["language"].string ?? "en-US", directory = cacheDirectory.appendingPathComponent("Audio"), store = store
            // Settings › Engines picks the engine; an explicit `engine` overrides it. A chosen Whisper
            // that isn't installed falls back to Apple and says so, so logging never stalls on setup.
            let requested = try a["engine"].string.map { value in
                guard let e = SharedSettings.TranscriptionEngine(rawValue: value) else { throw DirectionError("invalid_arguments", "engine is apple or whisper.") }
                return e
            }
            var engine = requested ?? SharedSettings.transcriptionEngine, note: String?
            if engine == .whisper && (WhisperTranscriber.executable() == nil || WhisperTranscriber.ffmpeg() == nil) {
                if requested == .whisper { throw DirectionError("whisper_unavailable", "Whisper isn't set up on this Mac: it needs mlx_whisper (`pip install mlx-whisper`) and ffmpeg.") }
                engine = .apple; note = "Whisper is chosen in Settings but isn't installed, so Apple's engine was used."
            }
            let model = a["model"].string ?? SharedSettings.whisperModel
            let useWhisper = engine == .whisper, fallbackNote = note
            let phase = engine == .whisper ? (WhisperTranscriber.isDownloaded(model) ? "Transcribing with Whisper" : "Downloading the Whisper model") : "Preparing local speech model"
            let job = try startJob(kind: "transcription", revision: p.editRevision, phase: phase, assetID: asset.id) {
                let transcript = useWhisper
                    ? try await WhisperTranscriber.transcribe(asset: asset, trackID: track, language: language, model: model, directory: directory)
                    : try await LocalTranscriber.transcribe(asset: asset, trackID: track, language: language, directory: directory)
                try store.saveTranscript(transcript)
                var result: [String: JSONValue] = ["assetID": .string(asset.id), "audioTrackID": .number(Double(track)), "wordCount": .number(Double(transcript.words.count)), "provider": .string(transcript.provider)]
                if let fallbackNote { result["note"] = .string(fallbackNote) }
                return .object(result)
            }
            return ToolResponse(try .wrapping(job))
        case "direction_measure_audio":
            if a["levels"] != .null { return try await levels(a) }
            guard let assetID = a["assetID"].string else {
                // No take: the cut's mix, as it plays and delivers.
                let p = try store.read(revision: a["revision"].int)
                // Several stretches in one answer, compiled once.
                if let ranges = a["ranges"].array {
                    guard !ranges.isEmpty, ranges.count <= 20 else { throw DirectionError("bad_argument", "ranges lists 1 to 20 stretches, each {start, end} in cut seconds.") }
                    let compiled = try await SequenceRenderer.compile(project: p, sequenceID: a["sequenceID"].string, cacheDirectory: cacheDirectory)
                    var out: [JSONValue] = []
                    for r in ranges {
                        let range = try secondsRange(r)
                        let v = try await SequenceRenderer.loudness(compiled, range: range)
                        out.append(.object(["start": r["start"], "end": r["end"], "integratedLUFS": v["integratedLUFS"], "truePeakDBTP": v["truePeakDBTP"], "samplePeakDBFS": v["samplePeakDBFS"], "loudest": v["profile"]["loudest"]]))
                    }
                    return ToolResponse(.object(["editRevision": .number(Double(p.editRevision)), "ranges": .array(out)]))
                }
                let range = a["start"] == .null && a["end"] == .null ? nil : try secondsRange(a)
                let compiled = try await SequenceRenderer.compile(project: p, sequenceID: a["sequenceID"].string, cacheDirectory: cacheDirectory)
                var value = try await SequenceRenderer.loudness(compiled, range: range)
                // The whole cut against the target, so one call says whether it's ready and what to do.
                if range == nil, case .object(var fields) = value {
                    let verdict = LoudnessCheck.verdict(integrated: fields["integratedLUFS"]?.double, truePeak: fields["truePeakDBTP"]?.double ?? -120)
                    fields["target"] = .object(["lufs": .number(SharedSettings.loudnessTarget), "truePeakDBTP": .number(SharedSettings.truePeakCeiling), "mixGainDB": .number(compiled.sequence.mixGainDB ?? 0),
                                                "ready": .bool(verdict.isReady), "says": .string(verdict.words ?? "On target."),
                                                "next": .string(verdict.isReady ? "Nothing to do for loudness." : "direction_edit with {op: \"loudness\"} brings the whole mix to the target.")])
                    value = .object(fields)
                }
                return ToolResponse(value)
            }
            let p = try store.read(), asset = try p.asset(assetID)
            guard let track = a["trackID"].int.flatMap(Int32.init(exactly:)) ?? asset.audio.first?.id else { throw DirectionError("no_audio", "The source has no audio.") }
            return ToolResponse(try await AudioProcessor.measure(asset: asset, trackID: track, directory: cacheDirectory.appendingPathComponent("Audio")))
        case "direction_frame":
            if a["assetID"] != .null { return try await sourceFrame(a) }
            let p = try store.read(revision: a["revision"].int)
            let compiled = try await SequenceRenderer.compile(project: p, sequenceID: a["sequenceID"].string, cacheDirectory: cacheDirectory, looks: try? store.lookContext())
            // Several moments in one answer: each step of the editor's resends everything said so far, so eight frames
            // in one call cost far less than eight calls.
            if let times = a["times"].array {
                let seconds = times.compactMap(\.double)
                guard !seconds.isEmpty, seconds.count == times.count, seconds.count <= 8, seconds.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                    throw DirectionError("invalid_time", "times lists 1 to 8 nonnegative cut seconds.")
                }
                let size = min(1920, max(160, a["maxDimension"].int ?? 640))
                var frames: [JSONValue] = [], paths: [String] = []
                for s in seconds {
                    let output = cacheDirectory.appendingPathComponent("Frames").appendingPathComponent(newID("frame") + ".png")
                    frames.append(try await SequenceRenderer.frame(compiled, at: .init(seconds: s), to: output, maxDimension: size))
                    paths.append(output.path)
                }
                return ToolResponse(.object(["frames": .array(frames), "editRevision": .number(Double(p.editRevision))]), imagePaths: paths)
            }
            let seconds = a["time"].double ?? 0
            guard seconds.isFinite && seconds >= 0 else { throw DirectionError("invalid_time", "Frame time must be a nonnegative number.") }
            let output = cacheDirectory.appendingPathComponent("Frames").appendingPathComponent(newID("frame") + ".png")
            let value = try await SequenceRenderer.frame(compiled, at: .init(seconds: seconds), to: output, maxDimension: min(1920, max(160, a["maxDimension"].int ?? 1280)))
            return ToolResponse(value, imagePaths: [output.path])
        case "direction_export", "direction_preview":
            let p = try store.read(revision: a["revision"].int), directory = cacheDirectory, sequenceID = a["sequenceID"].string
            let preset = a["preset"].string ?? "h264"
            let preview = name == "direction_preview"
            let output = preview ? cacheDirectory.appendingPathComponent("Previews").appendingPathComponent(newID("preview") + ".mp4") : URL(fileURLWithPath: NSString(string: try a.requiredString("path")).expandingTildeInPath).standardizedFileURL
            guard !p.assets.contains(where: { URL(fileURLWithPath: $0.path).standardizedFileURL == output }) else { throw DirectionError("source_overwrite", "An export cannot overwrite source footage.") }
            let range = preview ? try secondsRange(a) : nil
            if let range, range.duration.seconds > 30 { throw DirectionError("preview_too_long", "Preview samples are limited to 30 seconds; use export for a full cut.") }
            // Another size of the same shape: the cut renders at that multiple of its own size.
            var scale = 1.0
            if !preview, let w = a["width"].int, let h = a["height"].int {
                let s = try p.sequence(sequenceID)
                scale = Double(w) / Double(s.width)
                guard abs(Double(h) / Double(s.height) - scale) < 0.01, (0.25...4).contains(scale), max(w, h) <= 8192 else {
                    throw DirectionError("invalid_size", "Export at the cut\u{2019}s shape (\(s.width) \u{00D7} \(s.height)) or a multiple of it, up to 8192 wide.")
                }
            }
            // A timeline for another editing app: a folder with the FCPXML, renders, sound and LUTs (issue #4).
            if preset == "timeline", !preview {
                let s = try p.sequence(sequenceID)
                // The cut this is, or the one it was finished from.
                let cut = try store.cuts().filter { $0.editRevision <= p.editRevision && $0.sequenceID == s.id }.max { ($0.editRevision, $0.createdAt) < ($1.editRevision, $1.createdAt) }
                let request = InterchangeExport.Request(project: p, sequenceID: s.id, filmName: p.name, cutName: cut?.name ?? "Working cut", dailies: try store.dailies(), notes: try store.notes(),
                                                        looks: try? store.lookContext(), cacheDirectory: directory, folder: output)
                let job = try startJob(kind: "export", revision: p.editRevision, phase: "Writing the timeline", progress: nil) { [store] job in
                    let phases = JobPhases(job: job, store: store)
                    return try await InterchangeExport.write(request) { phases.say($0) }
                }
                return ToolResponse(try .wrapping(job))
            }
            let job = try startJob(kind: preview ? "preview" : "export", revision: p.editRevision, phase: "Compiling pinned edit for \(preset)") { [scale] in
                let compiled = try await SequenceRenderer.compile(project: p, sequenceID: sequenceID, cacheDirectory: directory, looks: try? self.store.lookContext(), scale: scale)
                return try await SequenceRenderer.export(compiled, to: output, preset: preset, range: range)
            }
            return ToolResponse(try .wrapping(job))
        case "direction_job":
            var job = try store.job(a.requiredString("jobID"))
            if !job.isTerminal && job.ownerPID != getpid() && kill(job.ownerPID, 0) != 0 && errno == ESRCH { job.status = "interrupted"; job.phase = "The process running this job exited"; job.updatedAt = Date().timeIntervalSince1970; try store.saveJob(job) }
            return ToolResponse(try .wrapping(job))
        case "direction_jobs": return ToolResponse(try .wrapping(store.jobs()))
        case "direction_cancel_job":
            let id = try a.requiredString("jobID"), job = try store.job(id)
            guard let task = tasks[id] else { if job.isTerminal { return ToolResponse(try .wrapping(job)) }; throw DirectionError("job_owned_elsewhere", "Cancel this job in the app or MCP process that started it.") }
            task.cancel(); return ToolResponse(.object(["jobID": .string(id), "cancellationRequested": .bool(true)]))
        case "direction_events": return ToolResponse(try .wrapping(store.events(since: Int64(a["since"].int ?? 0))))
        default:
            // Sound is done only when the mix is ready to deliver.
            if name == "direction_finishing", a["items"].array?.contains(where: { $0["id"].string == "sound" && $0["state"].string == "done" }) == true {
                let (verdict, _) = try await loudnessVerdict()
                if !verdict.isReady { throw DirectionError("loudness_off_target", (verdict.words ?? "") + " direction_edit with {op: \"loudness\"} brings it to the target; then mark sound done.") }
            }
            if let response = try invokeDirecting(name, a) { return response }
            if let response = try await invokePhase2(name, a) { return response }
            throw DirectionError("unknown_tool", "Unknown Direction tool: \(name).")
        }
    }

    public func waitForJob(_ id: String) async throws -> JobRecord {
        while true {
            try Task.checkCancellation()
            let response = try await invoke("direction_job", arguments: .object(["jobID": .string(id)]))
            let job = try response.value.decode(JobRecord.self)
            if job.isTerminal { if job.status != "completed" { throw DirectionError("job_" + job.status, job.error ?? job.phase) }; return job }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    public func cancelAll() { for task in tasks.values { task.cancel() } }

    func startJob(kind: String, revision: Int, phase: String, assetID: String? = nil, operation: @escaping @Sendable () async throws -> JSONValue) throws -> JobRecord {
        try startJob(kind: kind, revision: revision, phase: phase, assetID: assetID, progress: nil) { _ in try await operation() }
    }
    /// `operation` gets the job's record, to report its phase and progress on.
    func startJob(kind: String, revision: Int, phase: String, assetID: String? = nil, progress: Double?, operation: @escaping @Sendable (JobRecord) async throws -> JSONValue) throws -> JobRecord {
        let now = Date().timeIntervalSince1970
        let job = JobRecord(id: newID("job"), kind: kind, revision: revision, ownerPID: getpid(), status: "running", phase: phase, progress: progress, result: nil, error: nil, createdAt: now, updatedAt: now, assetID: assetID)
        try store.saveJob(job)
        tasks[job.id] = Task { [store] in
            var completed = job
            do { completed.result = try await operation(job); try Task.checkCancellation(); completed.status = "completed"; completed.phase = "Completed"; completed.progress = 1 }
            catch { completed.status = Task.isCancelled || error is CancellationError ? "cancelled" : "failed"; completed.error = error.localizedDescription; completed.errorCode = (error as? DirectionError)?.code; completed.phase = completed.status == "cancelled" ? "Cancelled" : "Failed" }
            // B-roll with nothing said in it isn't a failure.
            if completed.errorCode == "no_speech" { DirectionLog.info("The \(kind) job heard no speech\(assetID.map { " on \($0)" } ?? "").", "jobs") }
            else if completed.status == "failed" { DirectionLog.error("The \(kind) job failed\(assetID.map { " on \($0)" } ?? ""): \(completed.error ?? "")", "jobs") }
            completed.updatedAt = Date().timeIntervalSince1970
            try? store.saveJob(completed)
            self.finished(job.id)
        }
        return job
    }
    private func finished(_ id: String) { tasks.removeValue(forKey: id) }

    private func feedbackContext(id: String, includeMedia: Bool, includeAudio: Bool) async throws -> ToolResponse {
        let comment = try store.comment(id), original = try store.read(revision: comment.editRevision), current = try store.read()
        let originalSequence = try original.sequence(comment.sequenceID), currentSequence = try? current.sequence(comment.sequenceID)
        let anchors = try comment.anchors.map { anchor -> JSONValue in
            .object(["source": try .wrapping(anchor), "currentProjection": try currentSequence.map { try JSONValue.wrapping(ReviewAnchoring.project(anchor, onto: $0)) } ?? .null])
        }
        let assetIDs = Set(comment.anchors.compactMap(\.assetID))
        var value: [String: JSONValue] = ["comment": try comment.forEditor(), "originalSequence": try .wrapping(originalSequence), "sourceAssets": try .wrapping(original.assets.filter { assetIDs.contains($0.id) }), "anchors": .array(anchors), "currentEditRevision": .number(Double(current.editRevision)), "coordinateSpace": .string("region: normalized rendered output frame, origin top-left; pinned to original editRevision"), "transcript": .string(comment.transcriptContext.map(\.text).joined(separator: " "))]
        var frames: [JSONValue] = [], imagePaths: [String] = [], audioPaths: [String] = []
        if includeMedia && originalSequence.duration > .zero {
            let compiled = try await SequenceRenderer.compile(project: original, sequenceID: comment.sequenceID, cacheDirectory: cacheDirectory, previewMaxDimension: 1280, looks: try? store.lookContext())
            let frameStep = MediaTime(originalSequence.frameRate.frameDuration)
            let start = comment.range?.start ?? comment.time ?? .zero
            let duration = comment.range?.duration ?? MediaTime(seconds: min(6, max(0, originalSequence.duration.seconds - start.seconds)))
            let last = max(start, min(originalSequence.duration - frameStep, start + duration - frameStep))
            let times = Array(Set([start, min(last, start + duration.scaled(by: 0.5)), max(start, last)])).sorted()
            for time in times {
                let output = cacheDirectory.appendingPathComponent("Feedback").appendingPathComponent(newID("context") + ".png")
                frames.append(try await SequenceRenderer.frame(compiled, at: time, to: output, maxDimension: 960)); imagePaths.append(output.path)
            }
            if includeAudio && !compiled.audioMix.inputParameters.isEmpty {
                let output = cacheDirectory.appendingPathComponent("Feedback").appendingPathComponent(newID("context") + ".wav")
                let audioRange = MediaRange(start: start, duration: min(MediaTime(seconds: 8), originalSequence.duration - start))
                if audioRange.isValid { value["audioSample"] = try await SequenceRenderer.audioPreview(compiled, range: audioRange, to: output); audioPaths.append(output.path) }
            }
        }
        value["frames"] = .array(frames)
        value["previewTool"] = .object(["name": .string("direction_preview"), "revision": .number(Double(comment.editRevision)), "sequenceID": .string(comment.sequenceID), "start": .number(comment.range?.start.seconds ?? comment.time?.seconds ?? 0), "end": .number(min(originalSequence.duration.seconds, (comment.range?.end.seconds ?? comment.time?.seconds ?? 0) + 3))])
        return ToolResponse(.object(value), imagePaths: imagePaths, audioPaths: audioPaths)
    }

    private func baseRevision(_ a: JSONValue) throws -> Int { try requiredInt(a, "baseEditRevision") }
    private func requiredInt(_ a: JSONValue, _ key: String) throws -> Int { guard let n = a[key].double, n.isFinite, n.rounded() == n, let v = a[key].int, v >= 0 else { throw DirectionError("invalid_arguments", "\(key) must be a nonnegative integer.") }; return v }
    private func optionalTime(_ value: JSONValue) throws -> MediaTime? { guard value != .null else { return nil }; guard let v = value.double, v.isFinite && v >= 0 else { throw DirectionError("invalid_time", "Time must be a nonnegative number of seconds.") }; return .init(seconds: v) }
    /// measure_audio's levels: every frame (or `every` seconds) over a stretch, of the cut's mix or a take's track.
    private func levels(_ a: JSONValue) async throws -> ToolResponse {
        let l = a["levels"], p = try store.read(revision: a["revision"].int)
        guard let start = l["start"].double, let end = l["end"].double, start.isFinite, end.isFinite, start >= 0, end > start else { throw DirectionError("invalid_range", "levels takes {start, end} in seconds, with 0 \u{2264} start < end.") }
        var asset: MediaAsset?, frameRate = 30.0
        if let id = a["assetID"].string { asset = try p.asset(id); frameRate = asset?.video.first?.frameRate ?? 30 }
        else { frameRate = try p.sequence(a["sequenceID"].string).frameRate.value }
        let every = l["every"].double ?? 1 / max(1, frameRate)
        guard every.isFinite, every >= 0.005 else { throw DirectionError("bad_argument", "every is at least 0.005 s.") }
        guard (end - start) / every <= Double(Levels.most) else {
            throw DirectionError("bad_argument", "That\u{2019}s \(Int(((end - start) / every).rounded(.up))) windows; levels gives up to \(Levels.most). Measure a shorter stretch, or a longer every.")
        }
        if let asset {
            guard let track = a["trackID"].int.flatMap(Int32.init(exactly:)) ?? asset.audio.first?.id else { throw DirectionError("no_audio", "The source has no audio.") }
            let v = try await AudioProcessor.levels(asset: asset, trackID: track, start: start, end: end, every: every, directory: cacheDirectory.appendingPathComponent("Audio"))
            guard case .object(var o) = v.json else { return ToolResponse(v.json) }
            o["assetID"] = .string(asset.id); o["audioTrackID"] = .number(Double(track))
            return ToolResponse(.object(o))
        }
        let compiled = try await SequenceRenderer.compile(project: p, sequenceID: a["sequenceID"].string, cacheDirectory: cacheDirectory)
        let v = try await SequenceRenderer.levels(compiled, range: MediaRange(start: start, end: end), every: every)
        guard case .object(var o) = v.json else { return ToolResponse(v.json) }
        o["editRevision"] = .number(Double(p.editRevision))
        return ToolResponse(.object(o))
    }

    private func secondsRange(_ a: JSONValue) throws -> MediaRange { guard let start = a["start"].double, let end = a["end"].double, start.isFinite && end.isFinite && start >= 0 && end > start else { throw DirectionError("invalid_range", "Provide start/end seconds, with 0 ≤ start < end.") }; return .init(start: start, end: end) }
}

extension ReviewComment {
    /// A note as the editor reads it: the words said there as a short excerpt with their count, in place of
    /// every captured word and its timing, so a note on the whole cut stays small. Word cuts take their ids
    /// from direction_transcript.
    func forEditor() throws -> JSONValue {
        var plain = self; plain.transcriptContext = []
        // A note on the whole cut rests on every clip in it: its anchors are the cut itself, four fifths of a
        // turnover's length and nothing the editor doesn't read in direction_timeline.
        if range == nil && time == nil { plain.anchors = [] }
        guard case .object(var fields) = try JSONValue.wrapping(plain) else { return .null }
        if range == nil && time == nil { fields["anchors"] = nil; fields["anchoredTo"] = .string("the whole cut") }
        fields["transcriptContext"] = .object(["excerpt": .string(transcriptExcerpt()), "wordCount": .number(Double(transcriptContext.count))])
        return .object(fields)
    }
}

/// A running job's phase, saved as it changes ("Rendering 2 of 3: a title").
final class JobPhases: @unchecked Sendable {
    private let lock = NSLock()
    private var job: JobRecord
    private let store: ProjectStore
    init(job: JobRecord, store: ProjectStore) { self.job = job; self.store = store }
    func say(_ phase: String) {
        lock.withLock {
            guard phase != job.phase else { return }
            job.phase = phase; job.updatedAt = Date().timeIntervalSince1970
            try? store.saveJob(job)
        }
    }
}
