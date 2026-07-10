import Foundation

/// Lightweight summary of a session directory on disk, for the recent-sessions
/// list. Distinct from `STMDSession`, which models a live/restorable session.
struct SessionListing: Identifiable, Equatable {
    let id: String
    let dirPath: URL
    let format: OutputFormat
    let createdAt: Date
    let preview: String

    var txtPath: URL { dirPath.appendingPathComponent("\(id).txt") }
    var docPath: URL { dirPath.appendingPathComponent("\(id).\(format.fileExtension)") }
}
