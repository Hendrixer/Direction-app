import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
import CryptoKit
import DirectionCore

public enum AudioProcessor {
    public static func extract(asset: MediaAsset, trackID: Int32, directory: URL) async throws -> URL {
        let identity = "\(asset.path):\(asset.fileSize):\(asset.modifiedAt):\(trackID):pcm48-v3"
        let target = directory.appendingPathComponent(digest(Data(identity.utf8)) + ".caf")
        if FileManager.default.fileExists(atPath: target.path) { _ = try MediaInspector.checkedURL(asset); return target }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let access = try MediaAccess(assets: [asset]); defer { withExtendedLifetime(access) {} }
        let source = AVURLAsset(url: try MediaInspector.checkedURL(asset))
        guard let track = try await source.loadTracks(withMediaType: .audio).first(where: { $0.trackID == trackID }) else { throw DirectionError("audio_track_not_found", "Source audio track \(trackID) not found.") }
        let descriptions = try await track.load(.formatDescriptions)
        let channels = min(2, max(1, descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 1))
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: true)!
        let reader = try AVAssetReader(asset: source)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        let temp = directory.appendingPathComponent(UUID().uuidString + ".caf")
        do {
            let file = try AVAudioFile(forWriting: temp, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: true)
            guard reader.startReading() else { throw reader.error ?? DirectionError("audio_decode_failed", "Cannot decode audio.") }
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let data = CMSampleBufferGetDataBuffer(sample) else { continue }
                let frames = CMSampleBufferGetNumSamples(sample)
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let expectedFrame = timestamp.isFinite && timestamp >= 0 && timestamp < 604_800 ? AVAudioFramePosition((timestamp * format.sampleRate).rounded()) : file.length
                // Preserve source-timeline offsets. A separate mic track may begin later
                // than picture; concatenating decoded buffers would move its speech early.
                while file.length < expectedFrame {
                    let count = AVAudioFrameCount(min(4_096, expectedFrame - file.length))
                    guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count), let bytes = silence.mutableAudioBufferList.pointee.mBuffers.mData else { throw DirectionError("audio_buffer_failed", "Cannot allocate audio padding.") }
                    silence.frameLength = count
                    memset(bytes, 0, Int(count) * Int(channels) * MemoryLayout<Float>.size)
                    try file.write(from: silence)
                    try Task.checkCancellation()
                }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)), let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData else { throw DirectionError("audio_buffer_failed", "Cannot allocate audio buffer.") }
                buffer.frameLength = AVAudioFrameCount(frames)
                let byteCount = frames * Int(channels) * MemoryLayout<Float>.size
                guard CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: byteCount, destination: destination) == kCMBlockBufferNoErr else { throw DirectionError("audio_decode_failed", "Invalid PCM sample buffer.") }
                try file.write(from: buffer)
            }
            guard reader.status == .completed else { throw reader.error ?? DirectionError("audio_decode_failed", "Audio decoding did not complete.") }
            try install(temp: temp, at: target)
            return target
        } catch { reader.cancelReading(); try? FileManager.default.removeItem(at: temp); throw error }
    }

    public static func processed(asset: MediaAsset, trackID: Int32, effects: AudioEffects, directory: URL) async throws -> URL {
        let input = try await extract(asset: asset, trackID: trackID, directory: directory)
        guard effects.isActive else { return input }
        let key = input.lastPathComponent + digest(try JSONEncoder.direction.encode(effects)) + "-dsp-v1.caf"
        let target = directory.appendingPathComponent(key)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let source = try AVAudioFile(forReading: input)
        let format = source.processingFormat
        let engine = AVAudioEngine(), player = AVAudioPlayerNode(), eq = AVAudioUnitEQ(numberOfBands: 3)
        eq.bands[0].filterType = .highPass; eq.bands[0].frequency = Float(max(20, effects.highPassHz)); eq.bands[0].bypass = effects.highPassHz == 0
        eq.bands[1].filterType = .lowShelf; eq.bands[1].frequency = 180; eq.bands[1].gain = Float(effects.bassDB); eq.bands[1].bypass = effects.bassDB == 0
        eq.bands[2].filterType = .highShelf; eq.bands[2].frequency = 6_000; eq.bands[2].gain = Float(effects.trebleDB); eq.bands[2].bypass = effects.trebleDB == 0
        engine.attach(player); engine.attach(eq); engine.connect(player, to: eq, format: format)
        var last: AVAudioNode = eq
        if effects.compressor {
            let compressor = AVAudioUnitEffect(audioComponentDescription: .init(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
            AudioUnitSetParameter(compressor.audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, Float(effects.thresholdDB), 0)
            AudioUnitSetParameter(compressor.audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 6, 0)
            AudioUnitSetParameter(compressor.audioUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
            engine.attach(compressor); engine.connect(last, to: compressor, format: format); last = compressor
        }
        if effects.limiter {
            let limiter = AVAudioUnitEffect(audioComponentDescription: .init(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
            engine.attach(limiter); engine.connect(last, to: limiter, format: format); last = limiter
        }
        engine.connect(last, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        let temp = directory.appendingPathComponent(UUID().uuidString + ".caf")
        do {
            let destination = try AVAudioFile(forWriting: temp, settings: format.settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else { throw DirectionError("audio_buffer_failed", "Cannot allocate DSP output.") }
            player.scheduleFile(source, at: nil, completionHandler: nil)
            try engine.start(); player.play()
            var attempts = 0
            while engine.manualRenderingSampleTime < source.length {
                try Task.checkCancellation()
                let remaining = source.length - engine.manualRenderingSampleTime
                let status = try engine.renderOffline(AVAudioFrameCount(min(remaining, AVAudioFramePosition(buffer.frameCapacity))), to: buffer)
                switch status {
                case .success: try destination.write(from: buffer); attempts = 0
                case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                    attempts += 1; if attempts > 100 { throw DirectionError("audio_processing_stalled", "Offline audio processing stopped producing samples.") }
                case .error: throw DirectionError("audio_processing_failed", "Native audio processing failed.")
                @unknown default: throw DirectionError("audio_processing_failed", "Unknown native audio rendering status.")
                }
            }
            engine.stop(); player.stop(); engine.disableManualRenderingMode()
            try install(temp: temp, at: target)
            return target
        } catch { engine.stop(); player.stop(); try? FileManager.default.removeItem(at: temp); throw error }
    }

    public static func measure(asset: MediaAsset, trackID: Int32, directory: URL) async throws -> JSONValue {
        let path = try await extract(asset: asset, trackID: trackID, directory: directory)
        let file = try AVAudioFile(forReading: path)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096) else { throw DirectionError("audio_buffer_failed", "Cannot allocate analysis buffer.") }
        var peak: Double = 0, squares: Double = 0, count: Int64 = 0, waveform: [Double] = []
        while file.framePosition < file.length {
            try Task.checkCancellation(); try file.read(into: buffer)
            guard let data = buffer.floatChannelData else { throw DirectionError("audio_format", "Expected floating point PCM.") }
            var blockPeak: Double = 0
            for c in 0..<Int(buffer.format.channelCount) { for i in 0..<Int(buffer.frameLength) { let x = Double(data[c][i]); peak = max(peak, abs(x)); blockPeak = max(blockPeak, abs(x)); squares += x*x; count += 1 } }
            waveform.append(blockPeak)
        }
        if waveform.count > 400 { let stride = Int(ceil(Double(waveform.count) / 400)); waveform = Swift.stride(from: 0, to: waveform.count, by: stride).map { waveform[$0..<min($0+stride, waveform.count)].max() ?? 0 } }
        return .object(["assetID": .string(asset.id), "audioTrackID": .number(Double(trackID)), "samplePeakDBFS": .number(20 * log10(max(peak, 1e-12))), "rmsDBFS": .number(10 * log10(max(squares / Double(max(1, count)), 1e-24))), "waveformPeaks": .array(waveform.map(JSONValue.number)), "note": .string("Sample peak and RMS, not integrated LUFS or true peak.")])
    }

    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func install(temp: URL, at target: URL) throws { if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: temp) } else { do { try FileManager.default.moveItem(at: temp, to: target) } catch { if FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.removeItem(at: temp) } else { throw error } } } }
}
