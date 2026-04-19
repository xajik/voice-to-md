import Foundation

final class CodexProvider: Provider {
    let name = "codex"
    let supportsVoiceHooks = false

    func setup(workDir: String, hooksPort: Int, agentID: String, taskID: String) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let codexDir = "\(home)/.codex"
        try FileManager.default.createDirectory(atPath: codexDir, withIntermediateDirectories: true)

        let configPath = "\(codexDir)/config.toml"
        let stopURL = "http://localhost:\(hooksPort)/hooks/codex?agent=\(agentID)&task_id=\(taskID)"
        let notifyLine = "notify = \"\(notifyCommand(url: stopURL))\""

        var lines: [String] = []
        if let existing = try? String(contentsOfFile: configPath, encoding: .utf8) {
            lines = existing.components(separatedBy: "\n")
        }

        var replaced = false
        for i in 0..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("notify") {
                lines[i] = notifyLine
                replaced = true
                break
            }
        }
        if !replaced { lines.append(notifyLine) }

        try lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    func setupVoice(workDir: String, hooksPort: Int) throws {
        throw ProviderError.notSupported("voice hooks")
    }

    private func notifyCommand(url: String) -> String {
        "curl -sS -X POST '\(url)' -H 'Content-Type: application/json' -d @- > /dev/null 2>&1"
    }
}
