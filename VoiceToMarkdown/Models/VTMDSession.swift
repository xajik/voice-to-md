import Foundation

struct VTMDSession {
    let id: String
    let dirPath: URL
    var state: SessionState
    let modelSize: ModelSize

    var txtPath: URL { dirPath.appendingPathComponent("\(id).txt") }
    var mdPath: URL { dirPath.appendingPathComponent("\(id).md") }

    init(modelSize: ModelSize, baseDir: URL) {
        self.id = "\(Int(Date().timeIntervalSince1970 * 1000))"
        self.modelSize = modelSize
        self.state = .idle
        self.dirPath = baseDir.appendingPathComponent("voice-to-markdown/\(id)")
    }
}
