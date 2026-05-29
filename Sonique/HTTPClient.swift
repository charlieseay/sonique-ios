import Foundation

/// HTTP client for sending commands to SoniqueBar on Mac Mini
struct HTTPClient {
    static func sendCommand(_ text: String) async throws -> String {
        let url = URL(string: "\(Config.commandServerURL)/command")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HTTPError.badResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw HTTPError.invalidJSON
        }

        return responseText
    }

    static func healthCheck() async throws -> Bool {
        let url = URL(string: "\(Config.commandServerURL)/health")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return false
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "ok" else {
            return false
        }

        return true
    }
}

enum HTTPError: Error {
    case badResponse
    case invalidJSON
}
