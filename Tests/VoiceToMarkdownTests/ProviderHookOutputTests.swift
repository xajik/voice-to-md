import XCTest
@testable import VoiceToMarkdown

final class ProviderHookOutputTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - ClaudeCodeProvider

    func testClaudeSetupVoiceWritesSettingsJSON() throws {
        let provider = ClaudeCodeProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let settingsURL = tmpDir.appendingPathComponent(".claude/settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    func testClaudeSetupVoiceJSONContainsNotificationKey() throws {
        let provider = ClaudeCodeProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".claude/settings.json"))
        XCTAssertNotNil(json["Notification"])
    }

    func testClaudeSetupVoiceJSONContainsCorrectURL() throws {
        let provider = ClaudeCodeProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 8484)

        let raw = try String(contentsOf: tmpDir.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        XCTAssertTrue(raw.contains("8484"), "Port 8484 should appear in the JSON")
        XCTAssertTrue(raw.contains("/hooks/voice-to-md/notification"))
    }

    func testClaudeSetupVoiceHookTypeIsHTTP() throws {
        let provider = ClaudeCodeProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".claude/settings.json"))
        let jsonString = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("\"http\""))
    }

    func testClaudeSetupWritesStopHooks() throws {
        let provider = ClaudeCodeProvider()
        try provider.setup(workDir: tmpDir.path, hooksPort: 7070, agentID: "agent1", taskID: "task1")

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".claude/settings.json"))
        XCTAssertNotNil(json["Stop"])
        XCTAssertNotNil(json["StopFailure"])
    }

    func testClaudeSetupEmbeddsAgentAndTaskID() throws {
        let provider = ClaudeCodeProvider()
        try provider.setup(workDir: tmpDir.path, hooksPort: 7070, agentID: "myAgent", taskID: "myTask")

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".claude/settings.json"))
        let jsonString = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("myAgent"))
        XCTAssertTrue(jsonString.contains("myTask"))
    }

    // MARK: - GeminiProvider

    func testGeminiSetupVoiceWritesSettingsJSON() throws {
        let provider = GeminiProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let settingsURL = tmpDir.appendingPathComponent(".gemini/settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    func testGeminiSetupVoiceJSONContainsAfterAgentKey() throws {
        let provider = GeminiProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".gemini/settings.json"))
        XCTAssertNotNil(json["AfterAgent"])
    }

    func testGeminiSetupVoiceHookTypeIsCommand() throws {
        let provider = GeminiProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".gemini/settings.json"))
        let jsonString = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("\"command\""))
    }

    func testGeminiSetupVoiceCommandContainsCurl() throws {
        let provider = GeminiProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".gemini/settings.json"))
        let jsonString = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("curl"))
    }

    func testGeminiSetupVoiceCommandOutputsJSON() throws {
        let provider = GeminiProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".gemini/settings.json"))
        let jsonString = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("printf '{}'"), "Gemini hook must output valid JSON to stdout")
    }

    func testGeminiSetupVoiceContainsNotificationEndpoint() throws {
        let provider = GeminiProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 9000)

        let raw = try String(contentsOf: tmpDir.appendingPathComponent(".gemini/settings.json"), encoding: .utf8)
        XCTAssertTrue(raw.contains("9000"))
        XCTAssertTrue(raw.contains("/hooks/voice-to-md/notification"))
    }

    func testGeminiEnvContainsTrustWorkspace() {
        let provider = GeminiProvider()
        let env = provider.env(hooksPort: 7070)
        XCTAssertEqual(env["GEMINI_TRUST_WORKSPACE"], "1")
    }

    func testGeminiSetupVoiceHookHasTimeout() throws {
        let provider = GeminiProvider()
        try provider.setupVoice(workDir: tmpDir.path, hooksPort: 7070)

        let json = try loadJSON(at: tmpDir.appendingPathComponent(".gemini/settings.json"))
        let jsonString = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("5000"), "Timeout should be 5000ms")
    }

    // MARK: - OpenCodeProvider

    func testOpenCodeSetupWritesPlugin() throws {
        let provider = OpenCodeProvider()
        try provider.setup(workDir: tmpDir.path, hooksPort: 7070, agentID: "a1", taskID: "t1")

        let pluginPath = tmpDir.appendingPathComponent(".opencode/plugins/tasksquad.ts")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginPath.path))
    }

    func testOpenCodePluginContainsHooksPort() throws {
        let provider = OpenCodeProvider()
        try provider.setup(workDir: tmpDir.path, hooksPort: 8888, agentID: "a1", taskID: "t1")

        let pluginPath = tmpDir.appendingPathComponent(".opencode/plugins/tasksquad.ts")
        let content = try String(contentsOf: pluginPath, encoding: .utf8)
        XCTAssertTrue(content.contains("8888"))
    }

    func testOpenCodePluginIsValidTypeScript() throws {
        let provider = OpenCodeProvider()
        try provider.setup(workDir: tmpDir.path, hooksPort: 7070, agentID: "a1", taskID: "t1")

        let pluginPath = tmpDir.appendingPathComponent(".opencode/plugins/tasksquad.ts")
        let content = try String(contentsOf: pluginPath, encoding: .utf8)
        XCTAssertTrue(content.contains("export const TaskSquadPlugin"))
        XCTAssertTrue(content.contains("async"))
    }

    // MARK: - Helpers

    private func loadJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
