import Foundation

struct VTMDSession {
    let id: String
    let dirPath: URL
    var state: SessionState
    let agentName: String
    let modelSize: ModelSize
    var notesPath: URL?

    var txtPath: URL { dirPath.appendingPathComponent("\(id).txt") }
    var mdPath: URL { dirPath.appendingPathComponent("\(id).md") }
    var tmuxSessionName: String { "tsq-vtm-\(String(id.prefix(8)))" }

    init(agentName: String, modelSize: ModelSize, baseDir: URL) {
        self.id = "\(Int(Date().timeIntervalSince1970 * 1000))"
        self.agentName = agentName
        self.modelSize = modelSize
        self.state = .idle
        self.dirPath = baseDir.appendingPathComponent("voice-to-markdown/\(id)")
    }
}
