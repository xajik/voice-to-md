import Foundation

final class GeminiProvider: Provider {
    let name = "gemini"
    let supportsVoiceHooks = true

    func setup(workDir: String, hooksPort: Int, agentID: String, taskID: String) throws {
        let settingsPath = "\(workDir)/.gemini/settings.json"
        let stopURL = "http://localhost:\(hooksPort)/hooks/stop?agent=\(agentID)&task_id=\(taskID)&provider=gemini"
        let hooks: [String: Any] = [
            "AfterAgent": [[
                "matcher": "*",
                "hooks": [[
                    "name": "tasksquad-stop",
                    "type": "command",
                    "command": hookCommand(url: stopURL),
                    "timeout": 5000
                ]]
            ]]
        ]
        try writeJSON(to: settingsPath, object: hooks)
    }

    func setupVoice(workDir: String, hooksPort: Int) throws {
        let settingsPath = "\(workDir)/.gemini/settings.json"
        let url = "http://localhost:\(hooksPort)/hooks/voice-to-md/notification"
        let hooks: [String: Any] = [
            "AfterAgent": [[
                "matcher": "*",
                "hooks": [[
                    "name": "tasksquad-voice",
                    "type": "command",
                    "command": hookCommand(url: url),
                    "timeout": 5000
                ]]
            ]]
        ]
        try writeJSON(to: settingsPath, object: hooks)
    }

    func env(hooksPort: Int) -> [String: String] {
        ["GEMINI_TRUST_WORKSPACE": "1"]
    }

    private func hookCommand(url: String) -> String {
        "curl -sS -X POST \"\(url)\" -H \"Content-Type: application/json\" -d @- > /dev/null 2>&1; printf '{}'"
    }
}
