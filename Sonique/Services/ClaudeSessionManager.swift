import Foundation
import os.log

/// Manages Claude.ai session authentication and queries
@MainActor
class ClaudeSessionManager {
    static let shared = ClaudeSessionManager()

    private let keychainService = "com.seayniclabs.sonique.claude"
    private let logger = Logger(subsystem: "com.seayniclabs.soniquebar", category: "ClaudeSession")

    /// Check if session is valid (has cookies and not expired)
    var isValid: Bool {
        guard let cookies = loadCookies() else {
            logger.info("[ClaudeSession] No cookies found")
            return false
        }

        // Check if session cookie exists and hasn't expired
        guard let sessionCookie = cookies.first(where: { $0.name.contains("session") || $0.name.contains("sessionKey") }) else {
            logger.info("[ClaudeSession] No session cookie found")
            return false
        }

        if let expiresDate = sessionCookie.expiresDate, expiresDate < Date() {
            logger.info("[ClaudeSession] Session cookie expired")
            return false
        }

        logger.info("[ClaudeSession] Session is valid")
        return true
    }

    /// Save session cookies after successful auth
    func saveSession(cookies: [HTTPCookie]) throws {
        logger.info("[ClaudeSession] Saving \(cookies.count) cookies")

        let encoder = JSONEncoder()

        // Convert HTTPCookie to codable format
        let cookieData: [[String: Any]] = cookies.map { cookie in
            var data: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
            ]

            if let expiresDate = cookie.expiresDate {
                data["expiresDate"] = expiresDate.timeIntervalSince1970
            }

            data["isSecure"] = cookie.isSecure
            data["isHTTPOnly"] = cookie.isHTTPOnly

            return data
        }

        let jsonData = try JSONSerialization.data(withJSONObject: cookieData)

        try KeychainHelper.save(jsonData, service: keychainService, account: "session")
        logger.info("[ClaudeSession] Session saved successfully")
    }

    /// Load saved session cookies
    func loadCookies() -> [HTTPCookie]? {
        do {
            let data = try KeychainHelper.load(service: keychainService, account: "session")

            guard let cookieData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                logger.error("[ClaudeSession] Invalid cookie data format")
                return nil
            }

            let cookies = cookieData.compactMap { dict -> HTTPCookie? in
                var properties: [HTTPCookiePropertyKey: Any] = [:]

                if let name = dict["name"] as? String {
                    properties[.name] = name
                }
                if let value = dict["value"] as? String {
                    properties[.value] = value
                }
                if let domain = dict["domain"] as? String {
                    properties[.domain] = domain
                }
                if let path = dict["path"] as? String {
                    properties[.path] = path
                }
                if let expiresInterval = dict["expiresDate"] as? TimeInterval {
                    properties[.expires] = Date(timeIntervalSince1970: expiresInterval)
                }
                if let isSecure = dict["isSecure"] as? Bool, isSecure {
                    properties[.secure] = "TRUE"
                }

                return HTTPCookie(properties: properties)
            }

            logger.info("[ClaudeSession] Loaded \(cookies.count) cookies")
            return cookies

        } catch {
            logger.error("[ClaudeSession] Failed to load cookies: \(error.localizedDescription)")
            return nil
        }
    }

    /// Clear saved session
    func clearSession() {
        do {
            try KeychainHelper.delete(service: keychainService, account: "session")
            logger.info("[ClaudeSession] Session cleared")
        } catch {
            logger.error("[ClaudeSession] Failed to clear session: \(error.localizedDescription)")
        }
    }

    // Session monitoring
    private var sessionMonitorTask: Task<Void, Never>?
    private var onSessionExpired: (() -> Void)?

    /// Query Claude with saved session
    func query(_ prompt: String) async throws -> String {
        guard let cookies = loadCookies() else {
            throw SessionError.notAuthenticated
        }

        logger.info("[ClaudeSession] Querying with \(cookies.count) cookies")

        // TODO: Implement iOS-specific query mechanism
        // (ClaudeWebClient is macOS-only)
        throw SessionError.queryFailed("iOS query not yet implemented")
    }

    /// Start monitoring session validity
    /// - Parameter onExpired: Callback when session expires
    func startSessionMonitoring(onExpired: @escaping () -> Void) {
        self.onSessionExpired = onExpired

        // Cancel existing monitor
        sessionMonitorTask?.cancel()

        sessionMonitorTask = Task { @MainActor in
            while !Task.isCancelled {
                // Check every hour
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)

                if !isValid {
                    logger.warning("[ClaudeSession] Session expired, triggering re-auth")
                    onExpired()
                    break
                }
            }
        }

        logger.info("[ClaudeSession] Session monitoring started")
    }

    /// Stop session monitoring
    func stopSessionMonitoring() {
        sessionMonitorTask?.cancel()
        sessionMonitorTask = nil
        logger.info("[ClaudeSession] Session monitoring stopped")
    }
}

enum SessionError: LocalizedError {
    case notAuthenticated
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in to Claude."
        case .queryFailed(let message):
            return "Query failed: \(message)"
        }
    }
}
