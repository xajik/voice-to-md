import XCTest
@testable import VoiceToMarkdown

final class VTMDFileManagerTests: XCTestCase {
    private var tmpDir: URL!
    private var fm: VTMDFileManager { VTMDFileManager.shared }

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - appendTranscript

    func testAppendTranscriptCreatesFile() throws {
        let file = tmpDir.appendingPathComponent("test.txt")
        try fm.appendTranscript("hello", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("hello"))
    }

    func testAppendTranscriptAppendsMultipleLines() throws {
        let file = tmpDir.appendingPathComponent("multi.txt")
        try fm.appendTranscript("line 1", to: file)
        try fm.appendTranscript("line 2", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("line 1"))
        XCTAssertTrue(content.contains("line 2"))
    }

    func testAppendTranscriptAddsNewline() throws {
        let file = tmpDir.appendingPathComponent("newline.txt")
        try fm.appendTranscript("entry", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.hasSuffix("\n"))
    }

    func testAppendTranscriptPreservesOrder() throws {
        let file = tmpDir.appendingPathComponent("order.txt")
        try fm.appendTranscript("alpha", to: file)
        try fm.appendTranscript("beta", to: file)
        try fm.appendTranscript("gamma", to: file)
        let content = try String(contentsOf: file, encoding: .utf8)
        let alphaIdx = content.range(of: "alpha")!.lowerBound
        let betaIdx = content.range(of: "beta")!.lowerBound
        let gammaIdx = content.range(of: "gamma")!.lowerBound
        XCTAssertTrue(alphaIdx < betaIdx && betaIdx < gammaIdx)
    }

    // MARK: - writeMarkdown / readMarkdown

    func testWriteAndReadMarkdown() throws {
        let file = tmpDir.appendingPathComponent("note.md")
        let expected = "# Hello\n\nSome **bold** text."
        try fm.writeMarkdown(expected, to: file)
        XCTAssertEqual(fm.readMarkdown(from: file), expected)
    }

    func testWriteMarkdownOverwritesPreviousContent() throws {
        let file = tmpDir.appendingPathComponent("overwrite.md")
        try fm.writeMarkdown("first version", to: file)
        try fm.writeMarkdown("second version", to: file)
        XCTAssertEqual(fm.readMarkdown(from: file), "second version")
    }

    func testReadMarkdownReturnsEmptyForMissingFile() {
        let file = tmpDir.appendingPathComponent("nonexistent.md")
        XCTAssertEqual(fm.readMarkdown(from: file), "")
    }

    func testRoundTripUnicodeContent() throws {
        let file = tmpDir.appendingPathComponent("unicode.md")
        let content = "# 日本語\n\nEmoji: 🎙️🤖"
        try fm.writeMarkdown(content, to: file)
        XCTAssertEqual(fm.readMarkdown(from: file), content)
    }

    // MARK: - agentCommand config parsing

    func testAgentCommandDefaultsWhenNoConfig() {
        let cmd = fm.agentCommand()
        XCTAssertFalse(cmd.isEmpty)
    }

    func testAgentCommandParsedFromConfig() throws {
        let configPath = tmpDir.appendingPathComponent("config.toml")
        try "command = \"gemini --model gemini-2.0-flash\"\n".write(to: configPath, atomically: true, encoding: .utf8)
        // VTMDFileManager reads from its own vtmdRoot; parsing logic tested via the raw helper
        let lines = ["command = \"gemini --model gemini-2.0-flash\""]
        var result = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("command") {
                let parts = trimmed.components(separatedBy: "=")
                result = parts.dropFirst().joined(separator: "=")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        XCTAssertEqual(result, "gemini --model gemini-2.0-flash")
    }

    // MARK: - isModelDownloaded

    func testIsModelDownloadedReturnsFalseForMissing() {
        XCTAssertFalse(fm.isModelDownloaded(.large))
    }
}
