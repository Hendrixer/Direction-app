import Testing
import Foundation
@preconcurrency import AVFoundation
import DirectionCore
@testable import DirectionMedia
import DirectionTools

/// The mix measured to ITU-R BS.1770-4, with the signals EBU Tech 3341 checks a meter against.
@Suite(.serialized)
struct LoudnessTests {
    /// Stereo, interleaved: a sine peaking at `dBFS` in the channels named.
    static func sine(_ hz: Double, dBFS: Double, seconds: Double, left: Bool = true, right: Bool = true, phase: Double = 0) -> [Float] {
        let a = pow(10, dBFS / 20), n = Int(seconds * 48_000)
        var out = [Float](repeating: 0, count: n * 2)
        for i in 0..<n {
            let v = Float(a * sin(2 * .pi * hz * Double(i) / 48_000 + phase))
            if left { out[2 * i] = v }
            if right { out[2 * i + 1] = v }
        }
        return out
    }
    static func measure(_ parts: [Float]...) -> LoudnessMeter {
        var m = LoudnessMeter(sampleRate: 48_000, channels: 2)
        for p in parts { p.withUnsafeBufferPointer { m.add($0) } }
        return m
    }

    @Test func aSineAtMinus20InOneChannelReadsMinus23() throws {
        // The filters are BS.1770-4's own at 48 kHz (its table 1 and 2).
        let m = LoudnessMeter(sampleRate: 48_000, channels: 2), s = m.shelf[0], h = m.highPass[0]
        let table = [1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585, -1.99004745483398, 0.99007225036621]
        #expect(zip([s.b0, s.b1, s.b2, s.a1, s.a2, h.a1, h.a2], table).allSatisfy { abs($0 - $1) < 1e-8 } && [h.b0, h.b1, h.b2] == [1, -2, 1])
        let one = Self.measure(Self.sine(1_000, dBFS: -20, seconds: 3, right: false))
        #expect(abs(try #require(one.integrated) + 23) < 0.05, "\(String(describing: one.integrated))")
        // Both channels count the same: −23 dBFS in each is −23 LUFS too (Tech 3341, case 1), and −20 is −20.
        let both = Self.measure(Self.sine(1_000, dBFS: -23, seconds: 2))
        #expect(abs(try #require(both.integrated) + 23) < 0.05 && abs(both.samplePeakDBFS + 23) < 0.01)
        #expect(abs(try #require(Self.measure(Self.sine(1_000, dBFS: -20, seconds: 2)).integrated) + 20) < 0.05)
        // K-weighting lifts the top: 4 kHz reads about 3.3 dB louder than 1 kHz at the same level.
        let high = try #require(Self.measure(Self.sine(4_000, dBFS: -23, seconds: 2)).integrated)
        #expect(high > -20 && high < -19.4, "\(high)")
    }

    @Test func silenceAndTheQuietPartsAreGatedOut() throws {
        // Silence is under the absolute gate. The three blocks that straddle the end count at their share,
        // so 3 s of −23 then silence is (27 + 1.5) / 30 of the tone: −23.22.
        let paused = Self.measure(Self.sine(1_000, dBFS: -23, seconds: 3), [Float](repeating: 0, count: 48_000 * 2 * 2))
        #expect(abs(try #require(paused.integrated) + 23.22) < 0.03, "\(String(describing: paused.integrated))")
        // 20 LU quieter is under the relative gate: (57 + 1.515) / 60 of the loud part, −23.11, where
        // without the gate it would read −25.97.
        let quiet = Self.measure(Self.sine(1_000, dBFS: -23, seconds: 6), Self.sine(1_000, dBFS: -43, seconds: 6))
        #expect(abs(try #require(quiet.integrated) + 23.11) < 0.03, "\(String(describing: quiet.integrated))")
        #expect(Self.measure([Float](repeating: 0, count: 48_000 * 2)).integrated == nil)
        #expect(Self.measure(Self.sine(1_000, dBFS: -23, seconds: 0.3)).integrated == nil)
    }

    @Test func theTruePeakIsFoundBetweenSamples() {
        // A quarter of the rate at 45°: every sample lands at 0.707 of the peak (Tech 3341, case 15).
        let m = Self.measure(Self.sine(12_000, dBFS: -6, seconds: 1, phase: .pi / 4))
        #expect(abs(m.samplePeakDBFS + 9.01) < 0.05 && abs(m.truePeakDBTP + 6) < 0.4, "\(m.samplePeakDBFS) \(m.truePeakDBTP)")
        let plain = Self.measure(Self.sine(997, dBFS: -6, seconds: 1))
        #expect(abs(plain.truePeakDBTP - plain.samplePeakDBFS) < 0.1)
    }

    @Test func theCutsMixIsMeasuredAsItPlays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("direction-loudness-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A stereo file with the 1 kHz sine at −20 dBFS on the left only, then 2 s of silence.
        let wav = directory.appendingPathComponent("left.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let samples = Self.sine(1_000, dBFS: -20, seconds: 4, right: false) + [Float](repeating: 0, count: 48_000 * 2 * 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count / 2))!
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i] = samples[2 * i]; buffer.floatChannelData![1][i] = samples[2 * i + 1] }
        do { let file = try AVAudioFile(forWriting: wav, settings: format.settings); try file.write(from: buffer) }
        let store = try ProjectStore.create(at: directory.appendingPathComponent("Loud.direction"), name: "Loudness")
        let runtime = try ToolRuntime(store: store)
        _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(wav.path), "append": .bool(true)]))
        // Through the renderer's mix, as the meter reads it: the blocks across the end of the tone count at
        // their share, (37 + 1.5) / 40 of it, −23.17.
        let whole = try await runtime.invoke("direction_measure_audio", arguments: .object([:])).value
        #expect(abs(try #require(whole["integratedLUFS"].double) + 23.17) < 0.03, "\(whole)")
        let peak = try #require(whole["samplePeakDBFS"].double), truePeak = try #require(whole["truePeakDBTP"].double)
        #expect(abs(peak + 20) < 0.05 && abs(truePeak + 20) < 0.1 && abs((whole["seconds"].double ?? 0) - 6) < 0.05)
        // A range of it, and the silence alone, which has nothing to measure.
        let part = try await runtime.invoke("direction_measure_audio", arguments: .object(["start": .number(1), "end": .number(3)])).value
        #expect(abs(try #require(part["integratedLUFS"].double) + 23) < 0.03 && abs((part["seconds"].double ?? 0) - 2) < 0.05)
        let silent = try await runtime.invoke("direction_measure_audio", arguments: .object(["start": .number(4.2), "end": .number(6)])).value
        #expect(silent["integratedLUFS"] == .null && silent["note"].string != nil)
        // Gain in the cut moves the mix by as much.
        let clipID = try #require(store.read().sequences[0].clips.first?.id)
        _ = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Down 6 dB"),
                                                                     "operations": .array([.object(["op": .string("gain"), "target": .string(clipID), "dB": .number(-6)])])]))
        let lower = try await runtime.invoke("direction_measure_audio", arguments: .object([:])).value
        #expect(abs(try #require(lower["integratedLUFS"].double) + 29.17) < 0.03, "\(lower)")
        // And up: gain over 0 dB is heard as louder, not held at the take's own level.
        _ = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Up 6 dB"),
                                                                     "operations": .array([.object(["op": .string("gain"), "target": .string(clipID), "dB": .number(6)])])]))
        let louder = try await runtime.invoke("direction_measure_audio", arguments: .object([:])).value
        #expect(abs(try #require(louder["integratedLUFS"].double) + 17.17) < 0.03, "\(louder)")
        // One call says how it moves: short-term loudness each second, the loudest stretch, the peaks.
        let profile = louder["profile"]
        #expect(profile["shortTermLUFS"].array?.count == 4 && profile["loudest"].array?.first?["end"].double ?? 0 <= 4.05 && profile["peaks"].array?.first?["truePeakDBTP"].double ?? 0 > -14.2, "\(profile)")
        #expect(louder["target"]["ready"] != .null)

        // The loudness step: the whole mix to the target in one operation, worked out from Direction's own measurement.
        func edit(_ op: JSONValue) async throws -> JSONValue {
            try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "idempotencyKey": .string(UUID().uuidString), "operations": .array([op])])).value
        }
        _ = try await edit(.object(["op": .string("loudness"), "lufs": .number(-14)]))
        #expect(abs((try store.read().sequences[0].mixGainDB ?? 0) - 3.17) < 0.05)
        let leveled = try await runtime.invoke("direction_measure_audio", arguments: .object([:])).value
        #expect(abs(try #require(leveled["integratedLUFS"].double) + 14) < 0.05, "\(leveled)")
        // Again: nothing more to do. With a ceiling the peaks reach first, it stops there and says where.
        _ = try await edit(.object(["op": .string("loudness"), "lufs": .number(-14)]))
        #expect(abs((try store.read().sequences[0].mixGainDB ?? 0) - 3.17) < 0.05)
        let held = try await edit(.object(["op": .string("loudness"), "lufs": .number(-8), "truePeak": .number(-9)]))
        let warnings = held["operations"].array?.first?["warnings"].array?.compactMap(\.string) ?? held["warnings"].array?.compactMap(\.string) ?? []
        #expect(warnings.contains { $0.contains("The peaks hold the mix") }, "\(held)")
        let capped = try await runtime.invoke("direction_measure_audio", arguments: .object([:])).value
        #expect(abs(try #require(capped["truePeakDBTP"].double) + 9) < 0.15, "\(capped)")
        // The mix gain is the cut's, so the outline says it.
        let outline = try await runtime.invoke("direction_timeline").value["outline"].string ?? ""
        #expect(outline.contains("mix +"), "\(outline)")
    }
}
