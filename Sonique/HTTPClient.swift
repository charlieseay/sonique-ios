import Foundation
import CryptoKit
#if os(iOS)
import UIKit
#endif

/// HTTP client for Sonique iOS — communicates with SoniqueBar (Mac CommandServer).
///
/// ## Security Notes
///
/// **Current Setup (Tailscale):** All communication is over HTTP on local/Tailscale networks.
/// Tailscale provides end-to-end encryption via WireGuard tunnel (see https://tailscale.com/security),
/// so HTTP over Tailscale is secure. On-device TLS validation is not required.
///
/// **Future Enhancement (HTTPS):** To support HTTPS, implement:
/// 1. Self-signed certificates on SoniqueBar or CA-signed via LetsEncrypt
/// 2. URLSessionDelegate.urlSession(_:didReceive:completionHandler:) for cert pinning
/// 3. Configuration to switch between "http://LAN" and "https://external"
///
/// **Request Signing:** All sensitive endpoints sign requests with HMAC-SHA256 derived
/// from the authToken. Server must verify signatures to prevent tampering.
///
/// **Auth Token Handling:**
/// - Cached locally with 1-hour TTL, automatically refreshed when expired
/// - Derived from server and stored in iCloud Keychain via SoniqueBrain
/// - Used for Bearer auth + request signing

struct StreamChunk {
    let text: String
    let isFinal: Bool
    var artifactURL: String? = nil   // image to display (ephemeral), if any
}

struct HTTPClient {
    // MARK: - Request Signing for Sensitive Endpoints

    /// Compute HMAC-SHA256 signature for request signing (prevents tampering with sensitive commands).
    /// Uses device-specific secret derived from authToken.
    private static func signRequest(_ body: Data, with authToken: String) -> String? {
        guard let keyData = authToken.data(using: .utf8) else { return nil }
        let signature = HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: keyData))
        return Data(signature).base64EncodedString()
    }

    /// Add authentication headers to request: Bearer token + request signature for integrity
    private static func addAuthHeaders(to request: inout URLRequest, authToken: String?, body: Data? = nil) {
        if let token = authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add signature for sensitive endpoints (config, /command/stream, /synthesize)
        if let body = body, let token = authToken, !token.isEmpty {
            if let signature = signRequest(body, with: token) {
                request.setValue(signature, forHTTPHeaderField: "X-Request-Signature")
            }
        }
    }
    static func sendCommand(_ text: String) async throws -> String {
        let url = URL(string: "\(HTTPClient.activeBaseURL)/command")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        #if os(iOS)
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let batteryLevel = await MainActor.run { Int(UIDevice.current.batteryLevel * 100) }
        let batteryState = await MainActor.run { UIDevice.current.batteryState }
        let isCharging = (batteryState == .charging || batteryState == .full)
        let conversationHistory = await MainActor.run {
            SoniqueBrain.shared.getRecentConversations(limit: 10)
        }
        let payload: [String: Any] = [
            "text": text,
            "conversation_history": conversationHistory,
            "device": [
                "battery_percent": batteryLevel,
                "is_charging": isCharging
            ]
        ]
        #else
        let conversationHistory = await MainActor.run {
            SoniqueBrain.shared.getRecentConversations(limit: 10)
        }
        let payload: [String: Any] = [
            "text": text,
            "conversation_history": conversationHistory
        ]
        #endif

        let body = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = body

        // Add authentication + request signature
        let authToken = await MainActor.run { SoniqueBrain.shared.loadPreferences().authToken }
        addAuthHeaders(to: &request, authToken: authToken, body: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HTTPError.badResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw HTTPError.invalidJSON
        }
        return responseText
    }

    static func sendCommandWithImage(_ text: String, imageBase64: String) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "\(HTTPClient.activeBaseURL)/command/stream")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    #if os(iOS)
                    await MainActor.run {
                        UIDevice.current.isBatteryMonitoringEnabled = true
                    }
                    let batteryLevel = await MainActor.run { Int(UIDevice.current.batteryLevel * 100) }
                    let batteryState = await MainActor.run { UIDevice.current.batteryState }
                    let isCharging = (batteryState == .charging || batteryState == .full)

                    let profile = await MainActor.run { AssistantProfile.shared }
                    let conversationHistory = await MainActor.run {
                        SoniqueBrain.shared.getRecentConversations(limit: 10)
                    }
                    let payload: [String: Any] = [
                        "text": text,
                        "image": imageBase64,  // Base64 encoded image
                        "conversation_history": conversationHistory,
                        "device": [
                            "battery_percent": batteryLevel,
                            "is_charging": isCharging
                        ],
                        "identity": [
                            "name": await profile.name,
                            "wake_word": await profile.wakeWord,
                            "skills": await profile.skills
                        ]
                    ]
                    #else
                    let profile = await MainActor.run { AssistantProfile.shared }
                    let payload: [String: Any] = [
                        "text": text,
                        "image": imageBase64,
                        "identity": [
                            "name": await profile.name,
                            "wake_word": await profile.wakeWord,
                            "skills": await profile.skills
                        ]
                    ]
                    #endif

                    let body = try JSONSerialization.data(withJSONObject: payload)
                    request.httpBody = body

                    let authToken = await MainActor.run { SoniqueBrain.shared.loadPreferences().authToken }
                    addAuthHeaders(to: &request, authToken: authToken, body: body)
                    request.timeoutInterval = 90

                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 90
                    config.timeoutIntervalForResource = 120
                    let session = URLSession(configuration: config)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: HTTPError.badResponse)
                        return
                    }

                    var lastDataTime = Date()
                    let watchdogTask = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            let elapsed = Date().timeIntervalSince(lastDataTime)
                            if elapsed > 30 {
                                continuation.finish(throwing: HTTPError.streamTimeout)
                                return
                            }
                        }
                    }

                    var chunkBuffer = [UInt8]()
                    chunkBuffer.reserveCapacity(512)

                    for try await byte in bytes {
                        lastDataTime = Date()

                        if byte == UInt8(ascii: "\n") {
                            if !chunkBuffer.isEmpty {
                                if let line = String(bytes: chunkBuffer, encoding: .utf8) {
                                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                                    chunkBuffer.removeAll(keepingCapacity: true)
                                    guard !trimmed.isEmpty else { continue }

                                    guard let data = trimmed.data(using: .utf8),
                                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                        continue
                                    }

                                    if json["done"] as? Bool == true {
                                        watchdogTask.cancel()
                                        continuation.finish()
                                        return
                                    }

                                    if let chunk = json["chunk"] as? String {
                                        let isFinal = json["is_final"] as? Bool ?? false
                                        continuation.yield(StreamChunk(text: chunk, isFinal: isFinal))
                                    }
                                }
                            }
                        } else {
                            chunkBuffer.append(byte)
                        }
                    }
                    watchdogTask.cancel()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    static func sendCommandStreaming(_ text: String) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "\(HTTPClient.activeBaseURL)/command/stream")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    // Include device battery level
                    #if os(iOS)
                    await MainActor.run {
                        UIDevice.current.isBatteryMonitoringEnabled = true
                    }
                    let batteryLevel = await MainActor.run { Int(UIDevice.current.batteryLevel * 100) }
                    let batteryState = await MainActor.run { UIDevice.current.batteryState }
                    let isCharging = (batteryState == .charging || batteryState == .full)

                    let profile = await MainActor.run { AssistantProfile.shared }
                    let payload: [String: Any] = [
                        "text": text,
                        "device": [
                            "battery_percent": batteryLevel,
                            "is_charging": isCharging
                        ],
                        "identity": [
                            "name": await profile.name,
                            "wake_word": await profile.wakeWord,
                            "skills": await profile.skills
                        ]
                    ]
                    #else
                    let profile = await MainActor.run { AssistantProfile.shared }
                    let payload: [String: Any] = [
                        "text": text,
                        "identity": [
                            "name": await profile.name,
                            "wake_word": await profile.wakeWord,
                            "skills": await profile.skills
                        ]
                    ]
                    #endif

                    let body = try JSONSerialization.data(withJSONObject: payload)
                    request.httpBody = body

                    // Add authentication + request signature
                    let authToken = await MainActor.run { SoniqueBrain.shared.loadPreferences().authToken }
                    addAuthHeaders(to: &request, authToken: authToken, body: body)
                    // Agentic LLM calls run tool calls and can take 15-40s with no bytes
                    // flowing — give the request + resource a generous window.
                    request.timeoutInterval = 90

                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 90
                    config.timeoutIntervalForResource = 120
                    let session = URLSession(configuration: config)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        // Fall back to non-streaming
                        let result = try await sendCommand(text)
                        continuation.yield(StreamChunk(text: result, isFinal: true))
                        continuation.finish()
                        return
                    }

                    // Track streaming response metrics
                    let streamStartTime = Date()
                    var chunkCount = 0
                    var totalBytesReceived = 0

                    // Stream watchdog: if no data received for 30s, abort and recover
                    var lastDataTime = Date()
                    let watchdogTask = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5s
                            let elapsed = Date().timeIntervalSince(lastDataTime)
                            if elapsed > 30 {
                                FileTracer.log("[http] stream watchdog: no data for 30s, aborting")
                                continuation.finish(throwing: HTTPError.streamTimeout)
                                return
                            }
                        }
                    }

                    var lineBuffer = ""
                    var chunkBuffer = [UInt8]()
                    chunkBuffer.reserveCapacity(512)  // Pre-allocate for typical line size

                    FileTracer.log("[http] starting buffered stream read")
                    for try await byte in bytes {
                        lastDataTime = Date() // Reset watchdog timer

                        if byte == UInt8(ascii: "\n") {
                            // Line complete - process accumulated buffer
                            if !chunkBuffer.isEmpty {
                                if let line = String(bytes: chunkBuffer, encoding: .utf8) {
                                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                                    chunkBuffer.removeAll(keepingCapacity: true)
                                    guard !trimmed.isEmpty else { continue }

                                    FileTracer.log("[http] received line: \(trimmed.prefix(100))")

                                    guard let data = trimmed.data(using: .utf8),
                                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                        FileTracer.log("[http] failed to parse JSON")
                                        continue
                                    }

                                    if json["done"] as? Bool == true {
                                        FileTracer.log("[http] stream complete (done:true)")
                                        watchdogTask.cancel()
                                        continuation.finish()
                                        return
                                    }
                                    // Artifact line → an image to display on the device.
                                    if let artifact = json["artifact"] as? [String: Any],
                                       artifact["type"] as? String == "image",
                                       let id = artifact["id"] as? String {
                                        let url = "\(HTTPClient.activeBaseURL)/artifact/\(id)"
                                        FileTracer.log("[http] yielding artifact: \(id)")
                                        continuation.yield(StreamChunk(text: "", isFinal: false, artifactURL: url))
                                        continue
                                    }
                                    if let chunk = json["chunk"] as? String {
                                        let isFinal = json["is_final"] as? Bool ?? false
                                        chunkCount += 1
                                        totalBytesReceived += chunk.count
                                        FileTracer.log("[http] yielding chunk: '\(chunk)' final=\(isFinal)")
                                        continuation.yield(StreamChunk(text: chunk, isFinal: isFinal))
                                    }
                                }
                            }
                        } else {
                            // Accumulate byte in buffer (more efficient than string concatenation)
                            chunkBuffer.append(byte)
                        }
                    }
                    watchdogTask.cancel()

                    // Report stream completion metrics
                    let streamDuration = Date().timeIntervalSince(streamStartTime)
                    let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://192.168.68.80:8890"
                    if let feedbackURL = URL(string: "\(serverURL)/feedback") {
                        var feedbackRequest = URLRequest(url: feedbackURL)
                        feedbackRequest.httpMethod = "POST"
                        feedbackRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        feedbackRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                        let feedbackPayload: [String: Any] = [
                            "type": "performance",
                            "message": "HTTP stream completed",
                            "metadata": [
                                "chunks_received": chunkCount,
                                "total_bytes": totalBytesReceived,
                                "stream_duration_seconds": String(format: "%.2f", streamDuration),
                                "request_text": String(text.prefix(100))
                            ]
                        ]
                        if let jsonData = try? JSONSerialization.data(withJSONObject: feedbackPayload) {
                            feedbackRequest.httpBody = jsonData
                            _ = try? await URLSession.shared.data(for: feedbackRequest)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// The endpoint that last responded to a health check. The command/stream paths use
    /// this so we keep talking to whichever endpoint (LAN or Tailscale) is reachable.
    private(set) static var activeBaseURL: String = Config.commandServerURL

    /// Result of a connection probe — for friendly UX.
    struct ConnectionResult {
        let reachable: Bool
        let endpoint: String?       // which endpoint answered
        let triedEndpoints: [String]
    }

    /// Try each configured endpoint (LAN, then Tailscale) and remember the first that
    /// answers /health. Returns a structured result for the UI to explain failures.
    static func probeConnection() async -> ConnectionResult {
        let endpoints = Config.endpointsToTry
        for base in endpoints {
            FileTracer.log("[conn] Trying \(base)...")
            if await isHealthy(base) {
                activeBaseURL = base
                FileTracer.log("[conn] SUCCESS: \(base)")
                return ConnectionResult(reachable: true, endpoint: base, triedEndpoints: endpoints)
            } else {
                FileTracer.log("[conn] FAILED: \(base)")
            }
        }
        return ConnectionResult(reachable: false, endpoint: nil, triedEndpoints: endpoints)
    }

    private static func isHealthy(_ base: String) async -> Bool {
        guard let url = URL(string: "\(base)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10   // Longer timeout for Tailscale over cellular

        // Add auth token to health check (required by SoniqueBar)
        let authToken = await MainActor.run { SoniqueBrain.shared.loadPreferences().authToken }
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                FileTracer.log("[conn] Health check failed: not HTTP response")
                return false
            }
            guard http.statusCode == 200 else {
                FileTracer.log("[conn] Health check failed: status=\(http.statusCode)")
                return false
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String,
                  status == "ready" || status == "ok" else {
                FileTracer.log("[conn] Health check failed: invalid JSON or status not ready/ok")
                return false
            }
            return true
        } catch {
            FileTracer.log("[conn] Health check error: \(error.localizedDescription)")
            return false
        }
    }

    static func healthCheck() async throws -> Bool {
        return await probeConnection().reachable
    }
}

enum HTTPError: Error {
    case badResponse
    case invalidJSON
    case streamTimeout
}
