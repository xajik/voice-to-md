import Foundation

/// Locates external CLI tools without spawning `which`, so resolution does not
/// depend on the process PATH. Apps launched from Finder/Dock inherit launchd's
/// minimal PATH (no /opt/homebrew/bin), which is why PATH-based lookup finds
/// whisper-cli/ffmpeg from a terminal `open` but not from /Applications.
enum ExecutableResolver {
    /// Homebrew locations probed even when absent from PATH
    /// (Apple Silicon, then Intel).
    static let fallbackDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// First executable found for any of `names`, trying each name across
    /// the PATH entries and then `fallbackDirectories`. Earlier names win.
    static func resolve(_ names: String...) -> URL? {
        resolve(names: names)
    }

    static func resolve(names: [String]) -> URL? {
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let directories = pathDirectories + fallbackDirectories.filter { !pathDirectories.contains($0) }
        for name in names {
            for directory in directories {
                let candidate = (directory as NSString).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        return nil
    }
}
