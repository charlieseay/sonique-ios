import Foundation
import os.log

/// Discovers SoniqueBar backend via Bonjour (_sonique._tcp.local)
/// and updates Config.commandServerURL automatically.
@MainActor
class BonjourDiscovery: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.seayniclabs.sonique", category: "Bonjour")

    @Published var discoveredURL: String?
    @Published var isSearching = false

    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []

    /// Start browsing for SoniqueBar backend
    func start() {
        guard !isSearching else { return }

        isSearching = true
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_sonique._tcp.", inDomain: "local.")

        logger.info("[Bonjour] Started browsing for _sonique._tcp.local")
        NSLog("[Bonjour] 🔍 Started browsing for _sonique._tcp.local")

        // Fallback: try iCloud-synced URL after 5 seconds
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if discoveredURL == nil {
                NSLog("[Bonjour] ⏱️ 5s timeout, trying iCloud-synced URL from SoniqueBrain")
                let prefs = SoniqueBrain.shared.loadSharedPreferences()
                if let syncedURL = prefs.serverURL {
                    NSLog("[Bonjour] ✅ Found iCloud URL: \(syncedURL)")
                    self.discoveredURL = syncedURL
                    Config.commandServerURL = syncedURL
                    stop()
                } else {
                    NSLog("[Bonjour] ❌ No serverURL in iCloud preferences")
                }
            }
        }
    }

    /// Stop browsing
    func stop() {
        browser?.stop()
        browser = nil
        isSearching = false

        logger.info("[Bonjour] Stopped browsing")
    }
}

// MARK: - NetServiceBrowserDelegate
extension BonjourDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        logger.info("[Bonjour] Found service: \(service.name)")
        NSLog("[Bonjour] 🎯 Found service: \(service.name)")

        // Resolve the service to get IP and port
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        logger.info("[Bonjour] Service removed: \(service.name)")
        NSLog("[Bonjour] ⬇️ Service removed: \(service.name)")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        logger.error("[Bonjour] ❌ Failed to search: \(errorDict)")
        NSLog("[Bonjour] ❌ Failed to search: \(errorDict)")
        isSearching = false
    }
}

// MARK: - NetServiceDelegate
extension BonjourDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        // Extract IP and port from resolved service
        guard let addresses = sender.addresses, !addresses.isEmpty else {
            logger.warning("[Bonjour] No addresses found for \(sender.name)")
            return
        }

        // Try to extract IPv4 address
        for addressData in addresses {
            let address = addressData.withUnsafeBytes { ptr -> String? in
                let sockaddr = ptr.bindMemory(to: sockaddr.self).baseAddress

                guard let addr = sockaddr else { return nil }

                // Check if IPv4
                if addr.pointee.sa_family == AF_INET {
                    let ipv4 = ptr.bindMemory(to: sockaddr_in.self).baseAddress
                    guard let ipv4Addr = ipv4 else { return nil }

                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )

                    if result == 0 {
                        return String(cString: hostname)
                    }
                }

                return nil
            }

            if let ipAddress = address {
                let port = sender.port
                let url = "http://\(ipAddress):\(port)"

                logger.info("[Bonjour] ✅ Discovered SoniqueBar at \(url)")

                DispatchQueue.main.async {
                    self.discoveredURL = url
                    // Update Config default
                    Config.commandServerURL = url
                }

                // Stop browsing once we found one
                stop()
                return
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        logger.error("[Bonjour] ❌ Failed to resolve \(sender.name): \(errorDict)")

        // Remove from resolving list
        resolvingServices.removeAll { $0 === sender }
    }
}
