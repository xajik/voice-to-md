import Foundation

struct STMDSession {
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
        self.dirPath = baseDir.appendingPathComponent("speech-to-markdown/\(id)")
    }

    /// Reconstructs a session from an existing on-disk directory (see
    /// `STMDFileManager.listSessions()`) so a prior recording can be resumed.
    /// `modelSize` isn't persisted per session, so the caller passes the
    /// currently resolved whisper model.
    init(restoring listing: SessionListing, modelSize: ModelSize) {
        self.id = listing.id
        self.dirPath = listing.dirPath
        self.modelSize = modelSize
        self.state = .idle
        self.format = listing.format
    }
}
