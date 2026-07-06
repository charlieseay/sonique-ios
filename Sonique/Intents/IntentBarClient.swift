import Foundation

/// Dispatches App Intent parameters to SoniqueBar POST /intent/<name>.
enum IntentBarClient {
    static let intentTimeout: TimeInterval = 10

    static func execute(intent name: String, parameters: [String: String]) async -> IntentBarResult {
        let connection = await HTTPClient.probeConnection()
        guard connection.reachable else {
            logIntentError(intent: name, code: "unreachable", detail: "SoniqueBar offline")
            return .unreachable
        }

        guard let url = URL(string: "\(HTTPClient.activeBaseURL)/intent/\(name)") else {
            return IntentBarResult(success: false, message: "Invalid server URL.", errorCode: "bad_url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = intentTimeout

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                logIntentError(intent: name, code: "bad_response", detail: "Not HTTP")
                return IntentBarResult(success: false, message: "Unexpected server response.", errorCode: "bad_response")
            }

            if http.statusCode == 503 {
                return IntentBarResult(success: false, message: "I can't reach the brain right now.", errorCode: "unreachable")
            }

            let parsed = IntentResponseParser.parse(data) ?? IntentResponseParser.parseFallback(data)
            guard let api = parsed else {
                logIntentError(intent: name, code: "invalid_json", detail: String(data: data, encoding: .utf8) ?? "")
                return IntentBarResult(success: false, message: "Couldn't read the server response.", errorCode: "invalid_json")
            }

            if !api.success {
                logIntentError(intent: name, code: api.error ?? "failed", detail: api.message)
            }

            return IntentBarResult(success: api.success, message: api.message, errorCode: api.error)
        } catch {
            logIntentError(intent: name, code: "network_error", detail: error.localizedDescription)
            if (error as NSError).code == NSURLErrorTimedOut {
                return IntentBarResult(success: false, message: "That took too long. Try again.", errorCode: "timeout")
            }
            return IntentBarResult(success: false, message: "I can't reach the brain right now.", errorCode: "network_error")
        }
    }

    private static func logIntentError(intent: String, code: String, detail: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] intent=\(intent) code=\(code) \(detail)\n"
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let logURL = dir.appendingPathComponent("intent-errors.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
