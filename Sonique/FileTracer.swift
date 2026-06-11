import Foundation

/// Appends timestamped trace lines to Documents/trace.log so they can be pulled
/// off-device in real time via `xcrun devicectl device copy from ...`.
/// This is the wired-debugging channel — iOS 26 iPads don't expose os_log to
/// idevicesyslog, but devicectl can read the app data container.
enum FileTracer {
    private static let queue = DispatchQueue(label: "com.seayniclabs.sonique.tracer")
    private static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("trace.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Truncate the log at the start of a fresh listening session.
    static func reset() {
        queue.async {
            try? "".data(using: .utf8)?.write(to: url)
        }
    }
}
