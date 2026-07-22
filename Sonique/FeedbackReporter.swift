import Foundation

/// Automatically reports performance issues and errors to SoniqueBar for diagnostics
@MainActor
class FeedbackReporter {
    static let shared = FeedbackReporter()

    private var serverURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? Config.defaultLANURL
    }

    private var authToken: String {
        UserDefaults.standard.string(forKey: "authToken") ?? "5FA5EE09-442D-4969-B091-9AC331E1C39C"
    }

    private init() {}

    /// Report an issue to SoniqueBar for Claude to see in diagnostics
    func report(type: FeedbackType, message: String, metadata: [String: Any] = [:]) {
        Task {
            await sendFeedback(type: type, message: message, metadata: metadata)
        }
    }

    /// Report timeout with query details
    func reportTimeout(query: String, timeoutDuration: TimeInterval) {
        var metadata: [String: Any] = [
            "query": String(query.prefix(100)),
            "timeout_seconds": timeoutDuration,
            "device": UIDevice.current.model
        ]
        report(type: .timeout, message: "Query timed out after \(Int(timeoutDuration))s", metadata: metadata)
    }

    /// Report audio playback issue
    func reportAudioIssue(description: String, audioFormat: String? = nil, bufferSize: Int? = nil) {
        var metadata: [String: Any] = [
            "device": UIDevice.current.model,
            "ios_version": UIDevice.current.systemVersion
        ]
        if let format = audioFormat {
            metadata["audio_format"] = format
        }
        if let size = bufferSize {
            metadata["buffer_size"] = size
        }
        report(type: .audioIssue, message: description, metadata: metadata)
    }

    /// Report connection failure
    func reportConnectionFailure(error: Error, endpoint: String) {
        let metadata: [String: Any] = [
            "endpoint": endpoint,
            "error": error.localizedDescription,
            "device": UIDevice.current.model
        ]
        report(type: .connectionFailure, message: "Failed to connect to \(endpoint)", metadata: metadata)
    }

    /// Report TTS latency
    func reportTTSLatency(provider: String, latencyMs: Int, textLength: Int) {
        let metadata: [String: Any] = [
            "provider": provider,
            "latency_ms": latencyMs,
            "text_length": textLength,
            "device": UIDevice.current.model
        ]

        // Only report if latency is abnormally high
        if latencyMs > 3000 {
            report(type: .performance, message: "TTS latency high: \(latencyMs)ms for \(provider)", metadata: metadata)
        }
    }

    /// Report STT recognition issue
    func reportSTTIssue(description: String, confidence: Float? = nil) {
        var metadata: [String: Any] = [
            "device": UIDevice.current.model
        ]
        if let conf = confidence {
            metadata["confidence"] = conf
        }
        report(type: .sttIssue, message: description, metadata: metadata)
    }

    /// Report barge-in detection
    func reportBargeIn(interrupted: Bool, confidence: Double, transcript: String) {
        let metadata: [String: Any] = [
            "interrupted": interrupted,
            "confidence": confidence,
            "transcript": String(transcript.prefix(50)),
            "device": UIDevice.current.model
        ]
        report(type: .bargeIn, message: interrupted ? "User interrupted successfully" : "Barge-in attempt ignored", metadata: metadata)
    }

    // MARK: - Private

    private func sendFeedback(type: FeedbackType, message: String, metadata: [String: Any]) async {
        guard let url = URL(string: "\(serverURL)/feedback") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let payload: [String: Any] = [
            "type": type.rawValue,
            "message": message,
            "metadata": metadata
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                NSLog("[FeedbackReporter] Sent: [\(type.rawValue)] \(message)")
            }
        } catch {
            // Silent failure - don't want feedback reporting to interfere with normal operation
            NSLog("[FeedbackReporter] Failed to send feedback: \(error.localizedDescription)")
        }
    }
}

enum FeedbackType: String {
    case timeout = "timeout"
    case audioIssue = "audio_issue"
    case connectionFailure = "connection_failure"
    case performance = "performance"
    case sttIssue = "stt_issue"
    case bargeIn = "barge_in"
    case error = "error"
}
