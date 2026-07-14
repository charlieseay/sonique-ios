import Foundation
#if os(iOS)
import UIKit
#endif

struct StreamChunk {
    let text: String
    let isFinal: Bool
    var artifactURL: String? = nil   // image to display (ephemeral), if any
}

struct HTTPClient {
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
        let payload: [String: Any] = [
            "text": text,
            "device": [
                "battery_percent": batteryLevel,
                "is_charging": isCharging
            ]
        ]
        #else
        let payload: [String: Any] = ["text": text]
        #endif

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

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

                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
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
                    FileTracer.log("[http] starting byte stream read")
                    for try await byte in bytes {
                        lastDataTime = Date() // Reset watchdog timer
                        let char = String(bytes: [byte], encoding: .utf8) ?? ""
                        if char == "\n" {
                            let line = lineBuffer.trimmingCharacters(in: .whitespaces)
                            lineBuffer = ""
                            guard !line.isEmpty else { continue }

                            FileTracer.log("[http] received line: \(line.prefix(100))")

                            guard let data = line.data(using: .utf8),
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
                                FileTracer.log("[http] yielding chunk: '\(chunk)' final=\(isFinal)")
                                continuation.yield(StreamChunk(text: chunk, isFinal: isFinal))
                            }
                        } else {
                            lineBuffer += char
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
                  json["status"] as? String == "ok" else {
                FileTracer.log("[conn] Health check failed: invalid JSON or status != ok")
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
