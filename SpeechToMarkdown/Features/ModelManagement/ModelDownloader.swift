import Foundation

@MainActor
final class ModelDownloader: ObservableObject {
    @Published var progress: DownloadProgress?
    @Published var isDownloading = false

    private var downloadTask: URLSessionDownloadTask?
    private let fileManager = STMDFileManager.shared

    func download(_ size: ModelSize) async {
        guard !isDownloading else { return }
        isDownloading = true
        stmdLog("DOWNLOAD", "Starting download: \(size.rawValue)")

        let destination = size.localPath(in: fileManager.modelsDir)
        let tmpPath = destination.deletingPathExtension().appendingPathExtension("bin.tmp")

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)

        do {
            let (asyncBytes, response) = try await session.bytes(from: size.huggingFaceURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw DownloadError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard !contentType.contains("text/html") else {
                throw DownloadError.htmlResponse
            }
            let total = response.expectedContentLength

            FileManager.default.createFile(atPath: tmpPath.path, contents: nil)
            guard let handle = FileHandle(forWritingAtPath: tmpPath.path) else {
                throw DownloadError.fileCreationFailed
            }

            var downloaded: Int64 = 0
            var chunk = Data(capacity: 65536)

            for try await byte in asyncBytes {
                chunk.append(byte)
                if chunk.count >= 65536 {
                    try handle.write(contentsOf: chunk)
                    downloaded += Int64(chunk.count)
                    chunk.removeAll(keepingCapacity: true)
                    progress = DownloadProgress(modelSize: size, bytesDownloaded: downloaded, bytesTotal: total, isComplete: false, error: nil)
                }
            }

            if !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
                downloaded += Int64(chunk.count)
            }
            try handle.close()

            guard downloaded > 1_000_000 else {
                throw DownloadError.tooSmall(downloaded)
            }
            try FileManager.default.moveItem(at: tmpPath, to: destination)
            stmdLog("DOWNLOAD", "Completed: \(size.rawValue) \(downloaded) bytes → \(destination.path)")
            progress = DownloadProgress(modelSize: size, bytesDownloaded: downloaded, bytesTotal: downloaded, isComplete: true, error: nil)
        } catch {
            stmdLog("DOWNLOAD", "Error: \(size.rawValue) — \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tmpPath)
            progress = DownloadProgress(modelSize: size, bytesDownloaded: 0, bytesTotal: 0, isComplete: false, error: error)
        }

        isDownloading = false
    }

    func cancel() {
        downloadTask?.cancel()
        isDownloading = false
        progress = nil
    }
}

enum DownloadError: Error, LocalizedError {
    case fileCreationFailed
    case badResponse(Int)
    case htmlResponse
    case tooSmall(Int64)

    var errorDescription: String? {
        switch self {
        case .fileCreationFailed: return "Failed to create temporary download file."
        case .badResponse(let code): return "Server returned HTTP \(code)."
        case .htmlResponse: return "Server returned an HTML page instead of the model file. The HuggingFace URL may require authentication or the file has moved."
        case .tooSmall(let bytes): return "Downloaded file is too small (\(bytes) bytes) — not a valid model."
        }
    }
}
