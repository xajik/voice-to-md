import Foundation

@MainActor
final class ModelDownloader: ObservableObject {
    @Published var progress: DownloadProgress?
    @Published var isDownloading = false

    private var downloadTask: URLSessionDownloadTask?
    private let fileManager = VTMDFileManager.shared

    func download(_ size: ModelSize) async {
        guard !isDownloading else { return }
        isDownloading = true

        let destination = size.localPath(in: fileManager.modelsDir)
        let tmpPath = destination.deletingPathExtension().appendingPathExtension("bin.tmp")

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)

        do {
            let (asyncBytes, response) = try await session.bytes(from: size.huggingFaceURL)
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

            try FileManager.default.moveItem(at: tmpPath, to: destination)
            progress = DownloadProgress(modelSize: size, bytesDownloaded: downloaded, bytesTotal: downloaded, isComplete: true, error: nil)
        } catch {
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

    var errorDescription: String? { "Failed to create temporary download file." }
}
