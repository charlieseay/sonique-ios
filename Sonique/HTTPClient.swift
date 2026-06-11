import Foundation

struct StreamChunk {
    let text: String
    let isFinal: Bool
}

struct HTTPClient {
    static func sendCommand(_ text: String) async throws -> String {
        let url = URL(string: "\(Config.commandServerURL)/command")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

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
                    let url = URL(string: "\(Config.commandServerURL)/command/stream")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
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

                    var lineBuffer = ""
                    for try await byte in bytes {
                        let char = String(bytes: [byte], encoding: .utf8) ?? ""
                        if char == "\n" {
                            let line = lineBuffer.trimmingCharacters(in: .whitespaces)
                            lineBuffer = ""
                            guard !line.isEmpty,
                                  let data = line.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                            if json["done"] as? Bool == true {
                                continuation.finish()
                                return
                            }
                            if let chunk = json["chunk"] as? String {
                                let isFinal = json["is_final"] as? Bool ?? false
                                continuation.yield(StreamChunk(text: chunk, isFinal: isFinal))
                            }
                        } else {
                            lineBuffer += char
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
            if await isHealthy(base) {
                activeBaseURL = base
                return ConnectionResult(reachable: true, endpoint: base, triedEndpoints: endpoints)
            }
        }
        return ConnectionResult(reachable: false, endpoint: nil, triedEndpoints: endpoints)
    }

    private static func isHealthy(_ base: String) async -> Bool {
        guard let url = URL(string: "\(base)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4   // fast probe — don't hang the UI on a dead endpoint
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "ok" else { return false }
            return true
        } catch { return false }
    }

    static func healthCheck() async throws -> Bool {
        return await probeConnection().reachable
    }
}

enum HTTPError: Error {
    case badResponse
    case invalidJSON
}
