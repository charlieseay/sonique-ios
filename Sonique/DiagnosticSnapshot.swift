import Foundation
#if os(iOS)
import UIKit
import Network
#endif

/// Diagnostic snapshot capturing error context for analysis
struct DiagnosticSnapshot: Codable {
    let timestamp: Date
    let errorType: String
    let errorCode: Int?
    let errorDescription: String
    let networkType: String?
    let tailscaleActive: Bool?
    let lastSuccessfulConnection: Date?
    let endpointsTried: [String]
    let deviceInfo: [String: String]?
    let systemState: [String: String]?

    /// Create snapshot from URLError
    static func fromURLError(_ error: Error, endpointsTried: [String], lastSuccess: Date?) -> DiagnosticSnapshot {
        let nsError = error as NSError
        let errorCode = nsError.code
        let errorDescription = error.localizedDescription

        #if os(iOS)
        let deviceModel = UIDevice.current.model
        let deviceName = UIDevice.current.name
        let osVersion = UIDevice.current.systemVersion
        let idiom = UIDevice.current.userInterfaceIdiom

        let deviceInfo: [String: String] = [
            "model": deviceModel,
            "name": deviceName,
            "iOS": osVersion,
            "idiom": idiom == .pad ? "iPad" : idiom == .phone ? "iPhone" : "other"
        ]
        #else
        let deviceInfo: [String: String]? = nil
        #endif

        return DiagnosticSnapshot(
            timestamp: Date(),
            errorType: nsError.domain,
            errorCode: errorCode,
            errorDescription: errorDescription,
            networkType: detectNetworkType(),
            tailscaleActive: detectTailscaleActive(),
            lastSuccessfulConnection: lastSuccess,
            endpointsTried: endpointsTried,
            deviceInfo: deviceInfo,
            systemState: nil
        )
    }

    /// Detect current network type
    private static func detectNetworkType() -> String? {
        #if os(iOS)
        // Check reachability via NWPathMonitor
        let monitor = NWPathMonitor()
        var networkType: String = "unknown"

        let semaphore = DispatchSemaphore(value: 0)

        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) {
                    networkType = "wifi"
                } else if path.usesInterfaceType(.cellular) {
                    networkType = "cellular"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    networkType = "ethernet"
                } else {
                    networkType = "other"
                }
            } else {
                networkType = "offline"
            }
            semaphore.signal()
        }

        let queue = DispatchQueue(label: "com.seayniclabs.sonique.network")
        monitor.start(queue: queue)

        // Wait up to 1 second for network detection
        _ = semaphore.wait(timeout: .now() + 1.0)
        monitor.cancel()

        return networkType
        #else
        return nil
        #endif
    }

    /// Detect if Tailscale is active
    private static func detectTailscaleActive() -> Bool? {
        #if os(iOS)
        // Check if there's a network interface with a 100.x.x.x address
        // This is a proxy for "Tailscale is connected"
        var addresses = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr else { continue }
            let addrFamily = interface.pointee.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.pointee.ifa_addr, socklen_t(interface.pointee.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, socklen_t(0), NI_NUMERICHOST)
                let address = String(cString: hostname)
                addresses.append(address)

                // Check if this is a Tailscale address (100.x.x.x)
                if address.hasPrefix("100.") {
                    return true
                }
            }
        }

        return false
        #else
        return nil
        #endif
    }
}

/// Diagnostic response from SoniqueBar
struct DiagnosticResponse: Codable {
    let diagnosis: Diagnosis
    let remediation: RemediationResult?

    struct Diagnosis: Codable {
        let diagnosis: String
        let confidence: Double
        let evidence: [String]
        let rootCause: String
        let remediation: Remediation
        let technicalDetails: String?
    }

    struct Remediation: Codable {
        let autoFixable: Bool
        let requires: String?
        let userAction: String?
        let workaround: String?
        let autoFixSteps: [String]?
    }

    struct RemediationResult: Codable {
        let success: Bool
        let actionsTaken: [String]
        let message: String
        let error: String?
    }
}
