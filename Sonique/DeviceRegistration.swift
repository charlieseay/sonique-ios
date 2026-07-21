import Foundation
import UIKit

/// Handles automatic device registration with SoniqueBar
class DeviceRegistration {

    /// Register this device with SoniqueBar and receive auth token
    static func registerIfNeeded() async throws -> String {
        // Check if already registered
        if let existingToken = UserDefaults.standard.string(forKey: "authToken"),
           !existingToken.isEmpty {
            return existingToken
        }

        // Generate unique device ID (persistent across app reinstalls)
        let deviceID = await getOrCreateDeviceID()

        // Get device info
        let deviceName = await UIDevice.current.name
        let deviceModel = await UIDevice.current.model
        let systemVersion = await UIDevice.current.systemVersion

        // Register with SoniqueBar
        let baseURL = Config.commandServerURL
        guard let url = URL(string: "\(baseURL)/register") else {
            throw RegistrationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "deviceID": deviceID,
            "deviceName": deviceName,
            "deviceModel": deviceModel,
            "systemVersion": systemVersion,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RegistrationError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw RegistrationError.serverError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw RegistrationError.invalidResponse
        }

        // Save token
        UserDefaults.standard.set(token, forKey: "authToken")

        return token
    }

    /// Get or create persistent device ID
    private static func getOrCreateDeviceID() async -> String {
        // Check UserDefaults first
        if let existing = UserDefaults.standard.string(forKey: "deviceID") {
            return existing
        }

        // Use identifierForVendor (persists across app reinstalls if same vendor)
        let deviceID = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        UserDefaults.standard.set(deviceID, forKey: "deviceID")
        return deviceID
    }

    enum RegistrationError: Error {
        case invalidURL
        case invalidResponse
        case serverError(Int)
    }
}
