import AutoFrameCore
import Foundation

enum ExtensionBootstrapTrace {
    private static let lock = NSLock()
    private static let fileURL = SharedStorage.containerDirectory()
        .appendingPathComponent("camera-extension-bootstrap.log")

    static func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [pid:\(ProcessInfo.processInfo.processIdentifier)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }

        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }
}
