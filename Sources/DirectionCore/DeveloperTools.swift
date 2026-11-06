import Foundation

/// Apple's command line developer tools, or Xcode. Without them `/usr/bin/python3`, `git`, `make` and the
/// rest are placeholders that open an installer on the director's screen when anything runs them, so Direction
/// never runs them then, and tells the editor not to.
public enum DeveloperTools {
    /// Asked once a process: `xcode-select -p` names the folder without ever offering to install.
    public static let installed: Bool = {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select"); p.arguments = ["-p"]
        p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let folder = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !folder.isEmpty && FileManager.default.isExecutableFile(atPath: folder + "/usr/bin/git")
    }()

    /// A placeholder macOS puts in /usr/bin until the developer tools are installed.
    public static func isPlaceholder(_ path: String) -> Bool {
        !installed && (path as NSString).deletingLastPathComponent == "/usr/bin" && ["python3", "pip3", "git", "make", "clang", "swift"].contains((path as NSString).lastPathComponent)
    }
}
