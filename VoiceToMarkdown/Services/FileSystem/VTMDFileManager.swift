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

    /// Recent sessions, newest first, for the "recent sessions" quick-access list.
    func listSessions() -> [SessionListing] {
        Self.listSessions(in: voiceToMarkdownDir)
    }

    /// Directory-parameterized so it's testable against a temp directory
    /// instead of the real `~/.vtmd` tree.
    static func listSessions(in directory: URL) -> [SessionListing] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []

        return entries
            .filter { $0.hasDirectoryPath }
            .compactMap { dir -> SessionListing? in
                let id = dir.lastPathComponent
                guard let millis = Double(id) else { return nil }
                let format = detectedFormat(id: id, dirPath: dir)
                let docPath = dir.appendingPathComponent("\(id).\(format.fileExtension)")
                let content = (try? String(contentsOf: docPath, encoding: .utf8)) ?? ""
                return SessionListing(
                    id: id,
                    dirPath: dir,
                    format: format,
                    createdAt: Date(timeIntervalSince1970: millis / 1000),
                    preview: previewLine(from: content)
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The raw transcript is always `{id}.txt`; a formatted doc in `md`/`html`
    /// lives alongside it as a second file. No second file means the session's
    /// format was `txt` (raw and doc paths coincide — see `VTMDSession.docPath`).
    private static func detectedFormat(id: String, dirPath: URL) -> OutputFormat {
        for format: OutputFormat in [.html, .md] {
            let path = dirPath.appendingPathComponent("\(id).\(format.fileExtension)").path
            if FileManager.default.fileExists(atPath: path) { return format }
        }
        return .txt
    }

    private static func previewLine(from content: String) -> String {
        let line = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let plain = line.trimmingCharacters(in: CharacterSet(charactersIn: "#<>*`"))
            .trimmingCharacters(in: .whitespaces)
        return plain.count > 80 ? String(plain.prefix(80)) + "…" : plain
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
