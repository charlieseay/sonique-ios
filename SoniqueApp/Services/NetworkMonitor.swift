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
    }

    private func apply(_ path: NWPath) {
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
            connection = next
            isExpensive = nextIsExpensive
            isConstrained = nextIsConstrained
            let status = qualityAssessment()
            let timestamp = lastTransitionAt
            Task {
                await postNetworkState(status: status, timestamp: timestamp)
            }
            return
        }
        isExpensive = nextIsExpensive
        isConstrained = nextIsConstrained
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

    private func postNetworkState(status: QualityStatus, timestamp: Date) async {
        let baseURL = settings.normalizedServerURL
        guard !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/api/network-state") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty {
            request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        }

        let payload: [String: Any] = [
            "connection": status.connection.apiValue,
            "isExpensive": status.isExpensive,
            "isConstrained": status.isConstrained,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            NSLog("[NetworkMonitor][debug] Failed POST /api/network-state: %@", error.localizedDescription)
        }
    }
}
