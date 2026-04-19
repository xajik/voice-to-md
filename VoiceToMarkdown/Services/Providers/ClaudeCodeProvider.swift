import Foundation

final class ClaudeCodeProvider: Provider {
    let name = "claude-code"
    let supportsVoiceHooks = true

    func setup(workDir: String, hooksPort: Int, agentID: String, taskID: String) throws {
        let settingsPath = "\(workDir)/.claude/settings.json"
        let hooks: [String: Any] = [
            "Stop": [[
                "matcher": "*",
                "hooks": [[
                    "type": "http",
                    "url": "http://localhost:\(hooksPort)/hooks/stop?agent=\(agentID)&task_id=\(taskID)"
                ]]
            ]],
            "StopFailure": [[
                "hooks": [[
                    "type": "http",
                    "url": "http://localhost:\(hooksPort)/hooks/stop?agent=\(agentID)&task_id=\(taskID)&failure=true"
                ]]
            ]]
        ]
        try writeJSON(to: settingsPath, object: hooks)
    }

    func setupVoice(workDir: String, hooksPort: Int) throws {
        let settingsPath = "\(workDir)/.claude/settings.json"
        let hooks: [String: Any] = [
            "Notification": [[
                "matcher": "*",
                "hooks": [[
                    "type": "http",
                    "url": "http://localhost:\(hooksPort)/hooks/voice-to-md/notification"
                ]]
            ]]
        ]
        try writeJSON(to: settingsPath, object: hooks)
    }
}
