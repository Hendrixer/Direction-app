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
            return ToolResponse(.object(["version": .string("0.2.0"), "gpu": .string(GPUCompositor.deviceName ?? "unavailable"), "transcription": await LocalTranscriber.availability(), "whisper": WhisperTranscriber.availability(), "transcriptionEngine": .string(SharedSettings.transcriptionEngine.rawValue), "tools": try .wrapping(ToolCatalog.definitions), "timeContract": .string("Canonical media times are {value,timescale}; ranges are half-open. Convenience start/end parameters use seconds. Comments and renders pin editRevision. Text editing deletes existing timed words; it does not synthesize speech."), "feedbackLoop": .string("Read direction_feedback at the beginning of each user-requested revision. Saving a comment does not wake the external agent.")]))
        case "direction_inspect":
            let p = try store.read(revision: a["revision"].int), sequence = try p.sequence(a["sequenceID"].string)
            return ToolResponse(.object(["project": try .wrapping(p), "sequence": try .wrapping(sequence), "durationSeconds": .number(sequence.duration.seconds), "projectPath": .string(store.url.path), "eventCursor": .number(Double(try store.eventCursor()))]))
        case "direction_import":
            let path = try a.requiredString("path")
            let asset = try await MediaInspector.inspect(url: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath), thumbnailDirectory: cacheDirectory.appendingPathComponent("Thumbnails"))
            let p = try store.read()
            let output = try store.addAsset(asset, append: a["append"].bool ?? false, sequenceID: a["sequenceID"].string, frameRate: a["frameRate"].double.map(FrameRate.nearest), expectedRevision: a["baseEditRevision"].int ?? p.editRevision, key: a["idempotencyKey"].string ?? UUID().uuidString)
            let saved = try output.assets.first(where: { $0.path == asset.path }) ?? output.asset(asset.id)
            return ToolResponse(.object(["asset": try .wrapping(saved), "editRevision": .number(Double(output.editRevision))]))
        case "direction_edit": return try await invokeEdit(a)
        case "direction_remove_range":
            let p = try store.read(), range = try secondsRange(a)
            var op = EditOperation("removeRange"); op.range = range; op.ripple = a["ripple"].bool ?? true
            let output = try store.apply(.init(baseEditRevision: try baseRevision(a), sequenceID: a["sequenceID"].string, idempotencyKey: a["idempotencyKey"].string ?? UUID().uuidString, summary: a["summary"].string ?? "Removed \(range.start)–\(range.end)", operations: [op]))
            _ = p
            return ToolResponse(try .wrapping(output))
        case "direction_audio":
            let p = try store.read(), assetID = try a.requiredString("assetID")
            let asset = try p.asset(assetID)
            guard let trackValue = a["trackID"].int, let trackID = Int32(exactly: trackValue), let stream = asset.audio.first(where: { $0.id == trackID }) else { throw DirectionError("audio_track_not_found", "Use an actual source audio track ID from direction_inspect.") }
            var settings = stream.settings
            if let clipID = a["clipID"].string {
                let sequence = try p.sequence(a["sequenceID"].string)
                guard let clip = sequence.clips.first(where: { $0.id == clipID }), clip.assetID == assetID else { throw DirectionError("clip_not_found", "Clip must reference the selected source asset.") }
                settings = clip.audioOverrides[String(trackID)] ?? settings
            }
            if let v = a["muted"].bool { settings.muted = v }; if let v = a["gainDB"].double { settings.gainDB = v }
            if let v = a["fadeIn"].double { settings.fadeIn = v }; if let v = a["fadeOut"].double { settings.fadeOut = v }
            if let v = a["highPassHz"].double { settings.effects.highPassHz = v }; if let v = a["bassDB"].double { settings.effects.bassDB = v }; if let v = a["trebleDB"].double { settings.effects.trebleDB = v }
            if let v = a["compressor"].bool { settings.effects.compressor = v }; if let v = a["thresholdDB"].double { settings.effects.thresholdDB = v }; if let v = a["limiter"].bool { settings.effects.limiter = v }
            var op = EditOperation("audio"); op.assetID = assetID; op.clipID = a["clipID"].string; op.audioTrackID = trackID; op.audio = settings
            let updated = try store.apply(.init(baseEditRevision: try baseRevision(a), sequenceID: a["sequenceID"].string, idempotencyKey: a["idempotencyKey"].string ?? UUID().uuidString, summary: "Updated \(stream.label) in \(asset.name)", operations: [op]))
            return ToolResponse(.object(["editRevision": .number(Double(updated.editRevision)), "trackID": .number(Double(trackID)), "settings": try .wrapping(settings)]))
        case "direction_add_comment":
            let p = try store.read(revision: a["revision"].int)
            guard (a["start"] == .null) == (a["end"] == .null), a["time"] == .null || a["start"] == .null else { throw DirectionError("invalid_arguments", "Use time for a moment, start and end for a range, or neither for the whole cut.") }
            let range = a["end"].double != nil ? try secondsRange(a) : nil
            let time = range == nil ? try optionalTime(a["time"]) : nil
            let region: FrameRegion? = a["region"] == .null ? nil : try a["region"].decode(FrameRegion.self)
            let c = try store.addComment(text: a.requiredString("text"), author: a["author"].string ?? "Director", sequenceID: a["sequenceID"].string, revision: p.editRevision, cutID: a["cutID"].string, range: range, time: time, region: region)
            return ToolResponse(try .wrapping(c))
        case "direction_feedback":
            // Drafts, dropped notes and outside notes the director hasn't accepted stay private.
            let comments = try store.comments(since: Int64(a["since"].int ?? 0))
            return ToolResponse(.object(["comments": try .wrapping(comments.filter(\.visibleToEditor)), "nextCursor": .number(Double(comments.last?.cursor ?? Int64(a["since"].int ?? 0))), "hasMore": .bool(comments.count == 500)]))
        case "direction_feedback_context":
            return try await feedbackContext(id: a.requiredString("commentID"), includeMedia: a["includeMedia"].bool ?? true, includeAudio: a["includeAudio"].bool ?? true)
        case "direction_feedback_reply":
            let updated = try store.reply(commentID: a.requiredString("commentID"), text: a.requiredString("text"), author: a["author"].string ?? "Agent", revision: a["revision"].int, status: a["status"].string)
            return ToolResponse(try .wrapping(updated))
        case "direction_create_cut":
            return ToolResponse(try .wrapping(store.createCut(name: a.requiredString("name"), sequenceID: a["sequenceID"].string, revision: a["revision"].int)))
        case "direction_cuts": return ToolResponse(try .wrapping(store.cuts()))
        case "direction_restore": return ToolResponse(try .wrapping(store.restore(revision: try requiredInt(a, "revision"), expectedRevision: try baseRevision(a), key: a["idempotencyKey"].string ?? UUID().uuidString)))
        case "direction_transcript":
            let offset = max(0, a["offset"].int ?? 0), limit = min(5_000, max(1, a["limit"].int ?? 1_000))
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
            return ToolResponse(.object(["editRevision": .number(Double(p.editRevision)), "words": try .wrapping(words), "total": .number(Double(all.count)), "nextOffset": next < all.count ? .number(Double(next)) : .null]))
        case "direction_import_transcript":
            let t = try a["transcript"].decode(SourceTranscript.self); try store.saveTranscript(t)
            return ToolResponse(.object(["assetID": .string(t.assetID), "wordCount": .number(Double(t.words.count))]))
        case "direction_edit_transcript":
            let p = try store.read(), sequence = try p.sequence(a["sequenceID"].string)
            guard p.editRevision == (try baseRevision(a)) else { throw DirectionError("revision_conflict", "Refresh the transcript before editing.") }
            let words = TranscriptEditing.words(in: sequence, transcripts: try store.transcripts())
            let ids: Set<String>
            if let text = a["editedText"].string { ids = try TranscriptEditing.deletedIDs(original: words, editedText: text) }
            else { ids = Set(a["deleteWordIDs"].array?.compactMap(\.string) ?? []) }
            if ids.isEmpty { return ToolResponse(.object(["editRevision": .number(Double(p.editRevision)), "removedWords": .number(0)])) }
            let ranges = try TranscriptEditing.deletionRanges(wordIDs: ids, words: words)
            let ops = ranges.map { r in var op = EditOperation("removeRange"); op.range = r; op.ripple = true; return op }
            let result = try store.apply(.init(baseEditRevision: p.editRevision, sequenceID: sequence.id, idempotencyKey: a["idempotencyKey"].string ?? UUID().uuidString, summary: "Removed \(ids.count) transcript words and their footage", operations: ops))
            return ToolResponse(.object(["editRevision": .number(Double(result.editRevision)), "removedWords": .number(Double(ids.count)), "removedRanges": try .wrapping(ranges)]))
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
            let p = try store.read(), asset = try p.asset(a.requiredString("assetID"))
            guard let track = a["trackID"].int.flatMap(Int32.init(exactly:)) ?? asset.audio.first?.id else { throw DirectionError("no_audio", "The source has no audio.") }
            return ToolResponse(try await AudioProcessor.measure(asset: asset, trackID: track, directory: cacheDirectory.appendingPathComponent("Audio")))
        case "direction_frame":
            if a["assetID"] != .null { return try await sourceFrame(a) }
            let p = try store.read(revision: a["revision"].int)
            let seconds = a["time"].double ?? 0
            guard seconds.isFinite && seconds >= 0 else { throw DirectionError("invalid_time", "Frame time must be a nonnegative number.") }
            let compiled = try await SequenceRenderer.compile(project: p, sequenceID: a["sequenceID"].string, cacheDirectory: cacheDirectory, looks: try? store.lookContext())
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
        let now = Date().timeIntervalSince1970
        let job = JobRecord(id: newID("job"), kind: kind, revision: revision, ownerPID: getpid(), status: "running", phase: phase, progress: nil, result: nil, error: nil, createdAt: now, updatedAt: now, assetID: assetID)
        try store.saveJob(job)
        tasks[job.id] = Task { [store] in
            var completed = job
            do { completed.result = try await operation(); try Task.checkCancellation(); completed.status = "completed"; completed.phase = "Completed"; completed.progress = 1 }
            catch { completed.status = Task.isCancelled || error is CancellationError ? "cancelled" : "failed"; completed.error = error.localizedDescription; completed.phase = completed.status == "cancelled" ? "Cancelled" : "Failed" }
            if completed.status == "failed" { DirectionLog.error("The \(kind) job failed\(assetID.map { " on \($0)" } ?? ""): \(completed.error ?? "")", "jobs") }
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
        var value: [String: JSONValue] = ["comment": try .wrapping(comment), "originalSequence": try .wrapping(originalSequence), "sourceAssets": try .wrapping(original.assets.filter { assetIDs.contains($0.id) }), "anchors": .array(anchors), "currentEditRevision": .number(Double(current.editRevision)), "coordinateSpace": .string("region: normalized rendered output frame, origin top-left; pinned to original editRevision"), "transcriptContext": try .wrapping(comment.transcriptContext)]
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
    private func secondsRange(_ a: JSONValue) throws -> MediaRange { guard let start = a["start"].double, let end = a["end"].double, start.isFinite && end.isFinite && start >= 0 && end > start else { throw DirectionError("invalid_range", "Provide start/end seconds, with 0 ≤ start < end.") }; return .init(start: start, end: end) }
}
