import Foundation
import AVFoundation
import LiveKit

@MainActor
class SessionManager: NSObject, ObservableObject {
    @Published var sessionState: SessionState = .idle
    @Published var agentState: AgentState = .idle
    @Published var serverHealth: ServerHealth = .init()
    @Published var agentAudioLevel: Float = 0.0
    @Published var userAudioLevel: Float = 0.0
    @Published var profile: AssistantProfile?
    @Published var avatarData: Data?

    private var room: Room?
    private var healthCheckTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        observeAudioInterruptions()
    }

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            Task { @MainActor in
                switch type {
                case .began:
                    // Audio session was interrupted (e.g., phone call, Siri)
                    // Pause the microphone during interruption
                    do {
                        try await self.room?.localParticipant.setMicrophone(enabled: false)
                    } catch {
                        // Silent failure on interruption
                    }

                case .ended:
                    // Audio session interruption ended — resume if still active
                    guard self.sessionState == .active else { return }

                    // Re-activate the audio session with proper options
                    let audioSession = AVAudioSession.sharedInstance()
                    do {
                        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                        // Re-enable microphone to resume LiveKit audio
                        try await self.room?.localParticipant.setMicrophone(enabled: true)
                    } catch {
                        print("Failed to resume audio session after interruption: \(error)")
                    }

                @unknown default:
                    break
                }
            }
        }
    }

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
        Task { await fetchProfile(settings: settings) }
    }

    func fetchProfile(settings: SoniqueSettings) async {
        guard settings.isConfigured else { return }
        let base = await resolveActiveURL(settings: settings)
        guard let url = URL(string: "\(base)/api/assistant/profile") else { return }
        var req = URLRequest(url: url, timeoutInterval: 5)
        if !settings.apiKey.isEmpty { req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key") }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let p = try JSONDecoder().decode(AssistantProfile.self, from: data)
            profile = p
            if let avatarPath = p.avatarUrl,
               let avatarURL = URL(string: "\(base)\(avatarPath)") {
                var avatarReq = URLRequest(url: avatarURL, timeoutInterval: 5)
                if !settings.apiKey.isEmpty { avatarReq.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key") }
                let (imgData, _) = try await URLSession.shared.data(for: avatarReq)
                avatarData = imgData
            }
        } catch {}
    }

    func updateProfile(settings: SoniqueSettings, name: String? = nil, imageData: Data? = nil, imageExt: String? = nil) async throws {
        let base = await resolveActiveURL(settings: settings)
        guard let url = URL(string: "\(base)/api/assistant/profile") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty { req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key") }
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let imageData, let imageExt {
            body["avatar_b64"] = imageData.base64EncodedString()
            body["avatar_ext"] = imageExt
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let p = try JSONDecoder().decode(AssistantProfile.self, from: data)
        profile = p
        if imageData != nil { avatarData = imageData }
    }

    func stopHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    // MARK: - Private

    // Returns the local URL if reachable within 2s, otherwise the external URL.
    // External fallback is premium-only — free tier always uses local URL.
    private func resolveActiveURL(settings: SoniqueSettings) async -> String {
        let local = settings.normalizedServerURL
        let external = settings.normalizedExternalURL
        let isPremium = PremiumManager.shared?.isPremium ?? false
        guard isPremium, !external.isEmpty else { return local }

        if let url = URL(string: "\(local)/api/settings") {
            var req = URLRequest(url: url, timeoutInterval: 2)
            if !settings.apiKey.isEmpty { req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key") }
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let code = (resp as? HTTPURLResponse)?.statusCode,
               code == 200 || code == 401 {
                return local
            }
        }
        return external
    }

    private func fetchConnectionDetails(settings: SoniqueSettings) async throws -> ConnectionDetails {
        let base = await resolveActiveURL(settings: settings)
        guard let url = URL(string: "\(base)/api/connection-details") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty {
            request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        }
        // Task #284: when CAAL accepts client routing hints, merge keys matching
        // `LLMRoutingCAALKeys` + raw values from `SoniqueSettings` into this POST body.
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
            let base = await resolveActiveURL(settings: settings)
            guard let url = URL(string: "\(base)/api/settings") else {
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
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor in
            let agentSpeaking = participants.contains { $0 is RemoteParticipant }
            self.agentState = agentSpeaking ? .speaking : .listening
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
