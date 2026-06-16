import Foundation

/// Posts log messages to SoniqueBar's /log endpoint so they're visible on the Mac
/// for debugging voice loop issues, barge-in, etc. without needing device access.
enum RemoteLogger {
    private static let backendURL = "http://192.168.0.221:8890/log"

    static func log(_ message: String, source: String = "VoiceLoop") {
        // Also write to local FileTracer
        FileTracer.log(message)

        // Post to backend asynchronously (fire and forget)
        Task {
            await postLog(message, source: source)
        }
    }

    private static func postLog(_ message: String, source: String) async {
        guard let url = URL(string: backendURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "message": message,
            "source": source,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = jsonData

        _ = try? await URLSession.shared.data(for: request)
    }
}
