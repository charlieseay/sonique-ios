import Foundation
import Network

/// Tracks the current network path (WiFi / cellular / wired / none) and logs
/// transitions so mid-session handoffs are visible to the rest of the app.
///
/// iOS doesn't expose signal strength or bandwidth to third-party apps, so
/// "quality assessment" is limited to what NWPath reports — interface type,
/// expensiveness (cellular / hotspot), and whether the path is usable at all.
/// That's enough for a voice assistant to answer "what's my connection?" and
/// to notice when the user moves between networks mid-call.
@MainActor
final class NetworkMonitor: ObservableObject {
    struct QualityStatus {
        let connection: Connection
        let isExpensive: Bool
        let isConstrained: Bool
        let summary: String
    }

    enum Connection: Equatable {
        case wifi
        case cellular
        case wired
        case other
        case none

        var spoken: String {
            switch self {
            case .wifi:     return "Wi-Fi"
            case .cellular: return "cellular"
            case .wired:    return "wired Ethernet"
            case .other:    return "a limited connection"
            case .none:     return "no network"
            }
        }

        var apiValue: String {
            switch self {
            case .wifi: return "wifi"
            case .cellular: return "cellular"
            case .wired: return "wired"
            case .other: return "other"
            case .none: return "none"
            }
        }
    }

    static let shared = NetworkMonitor()

    /// Same base URL as `/api/connection-details` for the active voice session. When set, every automatic POST (path changes, etc.) tries this host first so CAAL ingests state on the machine handling LiveKit.
    var sessionPreferredBaseURL: String?

    @Published private(set) var connection: Connection = .none
    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var isConstrained: Bool = false
    @Published private(set) var lastTransitionAt: Date = .distantPast

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.seayniclabs.sonique.netmon")
    private let settings = SoniqueSettings()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.apply(path) }
        }
        monitor.start(queue: queue)
        Task { @MainActor in
            self.apply(self.monitor.currentPath)
        }
    }

    private func apply(_ path: NWPath) {
        let previous = connection
        let next: Connection
        if path.status != .satisfied {
            next = .none
        } else if path.usesInterfaceType(.wifi) {
            next = .wifi
        } else if path.usesInterfaceType(.cellular) {
            next = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            next = .wired
        } else {
            next = .other
        }

        let nextIsExpensive = path.isExpensive
        let nextIsConstrained = path.isConstrained
        let transitioned = next != connection

        if transitioned {
            lastTransitionAt = Date()
            NSLog("[NetworkMonitor] %@ → %@", connection.spoken, next.spoken)
        }
        let recoveredFromOffline =
            previous == .none && next != .none && path.status == .satisfied
        connection = next
        isExpensive = nextIsExpensive
        isConstrained = nextIsConstrained
        if recoveredFromOffline {
            NotificationCenter.default.post(name: .soniqueNetworkBecameReachable, object: nil)
        }
        reportCurrentState(preferredBaseURL: sessionPreferredBaseURL)
    }

    func reportCurrentState(preferredBaseURL: String? = nil) {
        let status = qualityAssessment()
        let preferred = preferredBaseURL ?? sessionPreferredBaseURL
        Task {
            await postNetworkState(status: status, timestamp: Date(), preferredBaseURL: preferred)
        }
    }

    func qualityAssessment() -> QualityStatus {
        QualityStatus(
            connection: connection,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            summary: summary
        )
    }

    /// One-line status string suitable for voice ("You're on Wi-Fi. Signal looks healthy.").
    var summary: String {
        switch connection {
        case .none:
            return "No network connection right now."
        case .wifi:
            let hint = isConstrained ? " — but the OS says it's constrained" : ""
            return "You're on Wi-Fi\(hint)."
        case .cellular:
            let hint = isExpensive ? " — carrier marks it as high-cost data" : ""
            return "You're on cellular\(hint)."
        case .wired:
            return "You're on wired Ethernet."
        case .other:
            return "You're on a limited connection (tethering or captive network)."
        }
    }

    private func postNetworkState(status: QualityStatus, timestamp: Date, preferredBaseURL: String?) async {
        let payload: [String: Any] = [
            "connection": status.connection.apiValue,
            "isExpensive": status.isExpensive,
            "isConstrained": status.isConstrained,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        let body = try? JSONSerialization.data(withJSONObject: payload)
        let retries = [0.0, 0.8]
        let baseURLs = candidateBaseURLs(preferredBaseURL: preferredBaseURL)
        for baseURL in baseURLs {
            guard let url = URL(string: "\(baseURL)/api/network-state") else { continue }
            for delay in retries {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !settings.apiKey.isEmpty {
                    request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
                }
                request.httpBody = body
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if (200..<300).contains(code) {
                        return
                    }
                    NSLog("[NetworkMonitor][debug] POST /api/network-state returned status %d for %@", code, baseURL)
                } catch {
                    NSLog("[NetworkMonitor][debug] Failed POST /api/network-state to %@: %@", baseURL, error.localizedDescription)
                }
            }
        }
    }

    private func candidateBaseURLs(preferredBaseURL: String?) -> [String] {
        let local = settings.normalizedServerURL
        let external = settings.normalizedExternalURL
        let isPremium = PremiumManager.shared?.isPremium ?? false
        var urls: [String] = []
        if let preferredBaseURL {
            let preferred = preferredBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !preferred.isEmpty {
                urls.append(preferred)
            }
        }
        if !local.isEmpty {
            urls.append(local)
        }
        if isPremium, !external.isEmpty, external != local {
            urls.append(external)
        }
        var deduped: [String] = []
        for url in urls where !deduped.contains(url) {
            deduped.append(url)
        }
        return deduped
    }
}

extension Notification.Name {
    /// Posted when NWPath returns from offline/unusable to a satisfied route (e.g. after airplane mode).
    static let soniqueNetworkBecameReachable = Notification.Name("net.seayniclabs.sonique.networkReachable")
}
