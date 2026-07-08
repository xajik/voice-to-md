import Foundation

struct VTMDSession {
    let id: String
    let dirPath: URL
    var state: SessionState
    let modelSize: ModelSize
    /// Output format at session start; may change mid-session (the coordinator
    /// migrates the document file to the new extension).
    var format: OutputFormat

    var txtPath: URL { dirPath.appendingPathComponent("\(id).txt") }
    var docPath: URL { dirPath.appendingPathComponent("\(id).\(format.fileExtension)") }

    init(modelSize: ModelSize, baseDir: URL, format: OutputFormat) {
        self.id = "\(Int(Date().timeIntervalSince1970 * 1000))"
        self.modelSize = modelSize
        self.state = .idle
        self.format = format
        self.dirPath = baseDir.appendingPathComponent("voice-to-markdown/\(id)")
    }
}
