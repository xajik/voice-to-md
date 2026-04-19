import Foundation

final class VTMDLogger {
    static let shared = VTMDLogger()

    private let queue = DispatchQueue(label: "com.vtmd.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    func configure(logsDir: URL) {
        queue.async {
            let nameFormatter = DateFormatter()
            nameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let name = "vtmd_\(nameFormatter.string(from: Date())).log"
            let url = logsDir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            self.fileHandle = try? FileHandle(forWritingTo: url)
            self.write("APP", "Logger started → \(url.path)")
        }
    }

    func log(_ category: String, _ message: String) {
        queue.async { self.write(category, message) }
    }

    private func write(_ category: String, _ message: String) {
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        try? fileHandle?.write(contentsOf: data)
    }
}

func vtmdLog(_ category: String, _ message: String) {
    VTMDLogger.shared.log(category, message)
}
