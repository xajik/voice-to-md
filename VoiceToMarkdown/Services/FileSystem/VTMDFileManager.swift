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
        try installCommandFiles()
    }

    func createSessionDirectory(id: String) throws -> URL {
        let dir = voiceToMarkdownDir.appendingPathComponent(id)
        try createDirectoryIfNeeded(at: dir)
        return dir
    }

    func createNotesDirectory(workDir: String) throws -> URL {
        let now = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm-ss"
        let timeStr = timeFormatter.string(from: now)

        let notesDir = URL(fileURLWithPath: workDir).appendingPathComponent(".tsq/notes/\(dateStr)")
        try createDirectoryIfNeeded(at: notesDir)
        return notesDir.appendingPathComponent("\(timeStr).md")
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

    func readConfig() -> String? {
        let configPath = vtmdRoot.appendingPathComponent("config.toml")
        return try? String(contentsOf: configPath, encoding: .utf8)
    }

    func agentCommand() -> String {
        guard let config = readConfig() else { return "claude --dangerously-skip-permissions" }
        for line in config.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("command") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    return parts.dropFirst().joined(separator: "=")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
        return "claude --dangerously-skip-permissions"
    }

    func isModelDownloaded(_ size: ModelSize) -> Bool {
        FileManager.default.fileExists(atPath: size.localPath(in: modelsDir).path)
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func installCommandFiles() throws {
        guard let commandContent = commandFileContent() else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Spec step 2: install to ~/.tsq/commands/ and ~/.tsq/agents/ (global)
        // and <workDir>/.tsq/commands/ and <workDir>/.tsq/agents/ (local)
        let tsqDirs: [URL] = [
            home.appendingPathComponent(".tsq/commands"),
            home.appendingPathComponent(".tsq/agents"),
            vtmdRoot.appendingPathComponent(".tsq/commands"),
            vtmdRoot.appendingPathComponent(".tsq/agents")
        ]

        // Legacy harness dirs for agent slash command availability
        let legacyDirs: [URL] = [
            vtmdRoot.appendingPathComponent(".claude/commands"),
            vtmdRoot.appendingPathComponent(".agents/commands"),
            vtmdRoot.appendingPathComponent(".opencode/commands")
        ]

        for dir in tsqDirs + legacyDirs {
            try? createDirectoryIfNeeded(at: dir)
            let dest = dir.appendingPathComponent("tsq-voice-to-md.md")
            try? commandContent.write(to: dest, atomically: true, encoding: .utf8)
        }
    }

    private func commandFileContent() -> String? {
        guard let url = Bundle.main.url(forResource: "tsq-voice-to-md", withExtension: "md", subdirectory: "commands") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
