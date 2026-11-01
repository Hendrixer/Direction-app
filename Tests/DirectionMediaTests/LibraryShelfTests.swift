import Testing
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
import DirectionCore
import DirectionMedia
import DirectionTools

/// The director's sounds and images (library.md): what Direction hears and sees in each, and a film taking its own copy.
struct LibraryShelfTests {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-shelf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A word in black on nothing, as a logo is often drawn.
    static func logo(_ url: URL, text: String = "DIRECTION") throws -> URL {
        let width = 900, height = 260
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 120, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]))
        context.textPosition = CGPoint(x: 40, y: 80); CTLineDraw(line, context)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func aLogoIsSeenForItsSizeTransparencyAndWords() async throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let images = MediaLibrary(.images, folder: dir.appendingPathComponent("Images"))
        let item = try images.add(try Self.logo(dir.appendingPathComponent("Mark.png")))
        let seen = try await LibraryMeasuring.measure(item, in: images, cacheDirectory: dir.appendingPathComponent("cache"))
        let m = try #require(seen.measured)
        #expect(m.width == 900 && m.height == 260 && m.transparent == true)
        #expect(m.words?.uppercased().contains("DIRECTION") == true, "\(m.words ?? "nil")")
        #expect(!images.needsMeasuring(seen) && seen.kind == .image)
    }

    @Test func aSoundIsHeardForItsLengthAndLevel() async throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let sounds = MediaLibrary(.sounds, folder: dir.appendingPathComponent("Sounds"))
        let tone = dir.appendingPathComponent("Beep.wav")
        try MediaFixture.writeTone(to: tone, frequency: 880, seconds: 3, quiet: 2..<3)
        let heard = try await LibraryMeasuring.measure(try sounds.add(tone), in: sounds, cacheDirectory: dir.appendingPathComponent("cache"))
        let m = try #require(heard.measured)
        #expect(abs((m.seconds ?? 0) - 3) < 0.05)
        // Its level: loud for two seconds, then nothing.
        let levels = try #require(m.levels)
        #expect(levels.count > 20 && levels.count <= 96 && levels.first! > 0.5 && levels.last! < 0.1, "\(levels)")
        #expect(!sounds.needsMeasuring(heard))
        // Measured again, the director's choice of kind stands.
        let chosen = try sounds.update(heard.file) { $0.kind = heard.kind == .music ? .effect : .music }
        #expect(try await LibraryMeasuring.measure(chosen, in: sounds, cacheDirectory: dir.appendingPathComponent("cache")).kind == chosen.kind)
        // A beep isn't a song to bring into the library instead of the footage.
        #expect(await !LibraryMeasuring.isMusic(tone))
    }

    @Test func theEditorFindsASoundAndTheFilmKeepsItsOwnCopy() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let name = "Bed " + UUID().uuidString.prefix(8)
        let tone = f.directory.appendingPathComponent("\(name).wav")
        try MediaFixture.writeTone(to: tone, frequency: 220, seconds: 2)
        let item = try MediaLibrary.sounds.add(tone, note: "Under the opening")
        defer { try? MediaLibrary.sounds.remove(item) { try FileManager.default.removeItem(at: $0) } }

        let listed = try await f.runtime.invoke("direction_library", arguments: .object(["query": .string(String(name))]))
        #expect(listed.value["items"].array?.count == 1 && listed.value["items"].array?.first?["note"].string == "Under the opening")

        let brought = try await f.runtime.invoke("direction_import", arguments: .object(["library": .string(name.lowercased())]))
        let asset = try f.store.read().asset(try #require(brought.value["asset"]["id"].string))
        #expect(asset.fromLibrary == item.file && !asset.isFootage(film: f.store.url))
        #expect(asset.path.hasPrefix(f.store.url.appendingPathComponent("Library/Sounds").standardizedFileURL.path))
        #expect(FileManager.default.contentsEqual(atPath: asset.path, andPath: MediaLibrary.sounds.url(item).path))
        // Asked again, by name or by its file on the shelf, it's the copy already in.
        let again = try await f.runtime.invoke("direction_import", arguments: .object(["library": .string(name)]))
        let byPath = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(MediaLibrary.sounds.url(item).path)]))
        #expect(again.value["asset"]["id"].string == asset.id && byPath.value["asset"]["id"].string == asset.id && again.value["alreadyIn"].bool == true)
        #expect(try f.store.read().assets.filter { $0.fromLibrary == item.file }.count == 1)
        await #expect(throws: DirectionError.self) { _ = try await f.runtime.invoke("direction_import", arguments: .object(["library": .string("Nothing called this")])) }
    }
}
