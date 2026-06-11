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

    static func healthCheck() async throws -> Bool {
        let url = URL(string: "\(Config.commandServerURL)/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "ok" else { return false }
        return true
    }
}

enum HTTPError: Error {
    case badResponse
    case invalidJSON
}
