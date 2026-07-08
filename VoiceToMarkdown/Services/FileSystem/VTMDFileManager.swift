import Foundation

final class VTMDFileManager {
    static let shared = VTMDFileManager()

    let vtmdRoot: URL
    let modelsDir: URL
    let voiceToMarkdownDir: URL
    let logsDir: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        vtmdRoot = home.appendingPathComponent(".vtmd")
        modelsDir = vtmdRoot.appendingPathComponent("models/tts")
        voiceToMarkdownDir = vtmdRoot.appendingPathComponent("voice-to-markdown")
        logsDir = vtmdRoot.appendingPathComponent("logs")
    }

    func bootstrap() throws {
        try createDirectoryIfNeeded(at: vtmdRoot)
        try createDirectoryIfNeeded(at: modelsDir)
        try createDirectoryIfNeeded(at: voiceToMarkdownDir)
        try createDirectoryIfNeeded(at: logsDir)
        VTMDLogger.shared.configure(logsDir: logsDir)
    }

    func createSessionDirectory(id: String) throws -> URL {
        let dir = voiceToMarkdownDir.appendingPathComponent(id)
        try createDirectoryIfNeeded(at: dir)
        return dir
    }

    func appendTranscript(_ text: String, to url: URL) throws {
        let line = text + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func writeMarkdown(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func readMarkdown(from url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func isModelDownloaded(_ size: ModelSize) -> Bool {
        FileManager.default.fileExists(atPath: size.localPath(in: modelsDir).path)
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
