import Foundation
import LiveKit

@MainActor
class SessionManager: NSObject, ObservableObject {
    @Published var sessionState: SessionState = .idle
    @Published var agentState: AgentState = .idle
    @Published var serverHealth: ServerHealth = .init()
    @Published var agentAudioLevel: Float = 0.0
    @Published var userAudioLevel: Float = 0.0

    private var room: Room?
    private var healthCheckTask: Task<Void, Never>?

    // MARK: - Public API

    func connect(settings: SoniqueSettings, fromShortcut: Bool = false) async {
        guard sessionState == .idle else { return }
        sessionState = .connecting

        do {
            let details = try await fetchConnectionDetails(settings: settings)

            let newRoom = Room()
            newRoom.add(delegate: self)
            self.room = newRoom

            let connectOptions = ConnectOptions(autoSubscribe: true)
            try await newRoom.connect(
                url: details.serverUrl,
                token: details.participantToken,
                connectOptions: connectOptions
            )

            try await newRoom.localParticipant.setMicrophone(enabled: true)
            sessionState = .active
        } catch {
            sessionState = .error(error.localizedDescription)
            self.room = nil
        }
    }

    func disconnect() async {
        guard sessionState == .active || sessionState == .connecting else { return }
        sessionState = .disconnecting
        await room?.disconnect()
        room = nil
        sessionState = .idle
        agentState = .idle
        agentAudioLevel = 0
        userAudioLevel = 0
    }

    func startHealthChecks(settings: SoniqueSettings) {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                await checkHealth(settings: settings)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stopHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    // MARK: - Private

    private func fetchConnectionDetails(settings: SoniqueSettings) async throws -> ConnectionDetails {
        guard let url = URL(string: "\(settings.normalizedServerURL)/api/connection-details") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty {
            request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        }
        let body: [String: Any] = [
            "extended_session": settings.extendedSession
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 {
            throw SoniqueError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ConnectionDetails.self, from: data)
    }

    private func checkHealth(settings: SoniqueSettings) async {
        guard settings.isConfigured else {
            serverHealth.status = .offline
            return
        }
        serverHealth.status = .checking
        do {
            guard let url = URL(string: "\(settings.normalizedServerURL)/api/settings") else {
                serverHealth.status = .offline
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            if !settings.apiKey.isEmpty {
                request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
            }
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            serverHealth.status = (code == 200 || code == 401) ? .online : .offline
        } catch {
            serverHealth.status = .offline
        }
    }
}

// MARK: - RoomDelegate

extension SessionManager: RoomDelegate {
    nonisolated func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsSpeaking speaking: Bool) {
        Task { @MainActor in
            if participant is RemoteParticipant {
                self.agentState = speaking ? .speaking : .listening
            }
        }
    }

    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldValue: ConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .disconnected:
                if case .disconnecting = self.sessionState { return }
                if case .idle = self.sessionState { return }
                self.sessionState = .error("Connection lost")
                self.room = nil
                self.agentState = .idle
            default:
                break
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.agentState = .listening
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.agentState = .idle
        }
    }
}

// MARK: - Errors

enum SoniqueError: LocalizedError {
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Invalid API key. Check your Sonique settings."
        }
    }
}
