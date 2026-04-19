import Foundation

struct DownloadProgress {
    let modelSize: ModelSize
    let bytesDownloaded: Int64
    let bytesTotal: Int64
    let isComplete: Bool
    let error: Error?

    var fraction: Double {
        guard bytesTotal > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(bytesTotal)
    }

    var percentage: Int { Int(fraction * 100) }
}
