import Foundation
import HomeKit

/// Discovers available capabilities (HomeKit, MCP servers, APIs) and stores them in the brain
@MainActor
class CapabilityDiscovery {

    /// Run capability discovery and update preferences
    static func discover() async {
        var capabilities = SoniqueBrain.Preferences.DiscoveredCapabilities()

        // Discover HomeKit devices
        capabilities.homeKitDevices = await discoverHomeKit()

        // Discover MCP servers (check common endpoints)
        capabilities.mcpServers = await discoverMCPServers()

        // Save to preferences
        var prefs = SoniqueBrain.shared.loadPreferences()
        prefs.discoveredCapabilities = capabilities
        prefs.lastCapabilityDiscovery = ISO8601DateFormatter().string(from: Date())
        SoniqueBrain.shared.savePreferences(prefs)

        print("[Discovery] Found \(capabilities.homeKitDevices?.count ?? 0) HomeKit devices, \(capabilities.mcpServers?.count ?? 0) MCP servers")
    }

    // MARK: - HomeKit Discovery

    private static func discoverHomeKit() async -> [String]? {
        // Note: HomeKit discovery requires user permission and may take time
        // For now, return nil - implement full HomeKit integration later
        // This would use HMHomeManager to discover accessories
        return nil
    }

    // MARK: - MCP Server Discovery

    private static func discoverMCPServers() async -> [SoniqueBrain.Preferences.MCPServerInfo]? {
        var servers: [SoniqueBrain.Preferences.MCPServerInfo] = []

        // Check if backend exposes MCP capabilities endpoint
        guard let serverURL = Config.commandServerURL else { return nil }
        guard let url = URL(string: "\(serverURL)/capabilities") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let mcpList = json["mcp_servers"] as? [[String: Any]] {

                for serverInfo in mcpList {
                    if let name = serverInfo["name"] as? String,
                       let endpoint = serverInfo["endpoint"] as? String,
                       let capabilities = serverInfo["capabilities"] as? [String] {

                        servers.append(SoniqueBrain.Preferences.MCPServerInfo(
                            name: name,
                            endpoint: endpoint,
                            capabilities: capabilities
                        ))
                    }
                }
            }
        } catch {
            // Backend doesn't expose capabilities endpoint yet
        }

        return servers.isEmpty ? nil : servers
    }
}
