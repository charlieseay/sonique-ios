import Foundation
import AVFoundation
import AudioToolbox
import LiveKit
import os
import UIKit

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
    private var lastDisconnectAt: Date?
    private var connectWatchdogTask: Task<Void, Never>?
    private var firstAudioWatchdogTask: Task<Void, Never>?
    private var disconnectRecoveryTask: Task<Void, Never>?
    private var lastSettings: SoniqueSettings?
    private var autoRecoverAttempts = 0
    private var hasRemoteParticipant = false
    private var hasReceivedFirstAudio = false
    private var firstUserSpeechAt: Date?
    private var didPlayReadyChime = false
    private var lastBackendReadyChimeAt: Double = 0
    private var activeBackendBaseURL: String?
    private var micEnabledBeforeInterruption = true
    private var readyChimePlayer: AVAudioPlayer?
    private var networkRecoveryObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.seayniclabs.sonique", category: "SessionManager")

    override init() {
        super.init()
        observeAudioInterruptions()
        networkRecoveryObserver = NotificationCenter.default.addObserver(
            forName: .soniqueNetworkBecameReachable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.kickAudioAfterNetworkRecovery()
            }
        }
    }

    deinit {
        if let networkRecoveryObserver {
            NotificationCenter.default.removeObserver(networkRecoveryObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
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
                        self.micEnabledBeforeInterruption = true
                        try await self.room?.localParticipant.setMicrophone(enabled: false)
                    } catch {
                        self.logger.error("audio_interruption_began_mute_failed: \(error.localizedDescription)")
                    }

                case .ended:
                    // Audio session interruption ended — resume if still active
                    guard self.sessionState == .active else { return }

                    // Re-activate the audio session with proper options
                    let audioSession = AVAudioSession.sharedInstance()
                    do {
                        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                        try await self.room?.localParticipant.setMicrophone(enabled: self.micEnabledBeforeInterruption)
                    } catch {
                        self.logger.error("audio_interruption_end_resume_failed: \(error.localizedDescription)")
                        self.sessionState = .error("Audio interrupted. Tap to reconnect.")
                    }

                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Public API

    func connect(settings: SoniqueSettings, fromShortcut: Bool = false) async {
        guard sessionState == .idle || isErrorState else { return }
        if isErrorState {
            await forceResetToIdle()
        }
        sessionState = .connecting
        agentState = .thinking
        lastSettings = settings
        hasRemoteParticipant = false
        hasReceivedFirstAudio = false
        firstUserSpeechAt = nil
        didPlayReadyChime = false
        activeBackendBaseURL = nil
        NetworkMonitor.shared.sessionPreferredBaseURL = nil
        logger.info("connect_start")

        // Give the previous room a moment to fully drain on the server side.
        if let lastDisconnectAt {
            let elapsed = Date().timeIntervalSince(lastDisconnectAt)
            if elapsed < 2.5 {
                let remaining = 2.5 - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }

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
            micEnabledBeforeInterruption = true
            hasRemoteParticipant = !newRoom.remoteParticipants.isEmpty
            if hasRemoteParticipant {
                logger.info("participant_seen_bootstrap")
            }
            sessionState = .active
            NetworkMonitor.shared.reportCurrentState(preferredBaseURL: activeBackendBaseURL)
            playReadyChimeIfNeeded()
            startConnectWatchdogs(settings: settings)
            logger.info("connect_ok")
        } catch {
            sessionState = .error(error.localizedDescription)
            self.room = nil
            logger.error("connect_failed: \(error.localizedDescription)")
        }
    }

    func disconnect() async {
        guard sessionState == .active || sessionState == .connecting || isErrorState else { return }
        sessionState = .disconnecting
        await performFullDisconnect()
        autoRecoverAttempts = 0
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

    private var isErrorState: Bool {
        if case .error = sessionState { return true }
        return false
    }

    private func forceResetToIdle() async {
        await performFullDisconnect()
        sessionState = .idle
        agentState = .idle
    }

    private func performFullDisconnect() async {
        connectWatchdogTask?.cancel()
        firstAudioWatchdogTask?.cancel()
        disconnectRecoveryTask?.cancel()
        await room?.disconnect()
        lastDisconnectAt = Date()
        room = nil
        sessionState = .idle
        agentState = .idle
        agentAudioLevel = 0
        userAudioLevel = 0
        hasRemoteParticipant = false
        hasReceivedFirstAudio = false
        firstUserSpeechAt = nil
        didPlayReadyChime = false
        activeBackendBaseURL = nil
        NetworkMonitor.shared.sessionPreferredBaseURL = nil
    }

    private func startConnectWatchdogs(settings: SoniqueSettings) {
        connectWatchdogTask?.cancel()
        firstAudioWatchdogTask?.cancel()

        connectWatchdogTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard self.sessionState == .active else { return }
            if !self.hasRemoteParticipant, self.hasLiveRemoteParticipant() {
                self.hasRemoteParticipant = true
                self.logger.info("participant_seen_watchdog_probe")
            }
            guard !self.hasRemoteParticipant else { return }
            self.logger.error("connect_watchdog_timeout_no_remote_participant")
            self.agentState = .listening
        }

        firstAudioWatchdogTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline {
                guard self.sessionState == .active else { return }
                if self.hasRemoteParticipant,
                   let startedSpeakingAt = self.firstUserSpeechAt {
                    let waited = Date().timeIntervalSince(startedSpeakingAt)
                    if !self.hasReceivedFirstAudio && waited >= 12 {
                        self.logger.error("first_audio_watchdog_timeout_no_audio_response")
                        self.agentState = .listening
                        return
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func hasLiveRemoteParticipant() -> Bool {
        guard let room else { return false }
        return !room.remoteParticipants.isEmpty
    }

    private func playReadyChimeIfNeeded() {
        guard !didPlayReadyChime else { return }
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.success)

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .defaultToSpeaker,
                    .duckOthers,
                    .allowBluetoothA2DP,
                    .allowBluetoothHFP,
                ]
            )
            try audioSession.setActive(true, options: [])
        } catch {
            logger.error("ready_chime_session_activate_failed: \(error.localizedDescription)")
        }

        if let data = makeReadyChimeWav(),
           let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) {
            player.volume = 1.0
            player.prepareToPlay()
            _ = player.play()
            readyChimePlayer = player
        } else {
            AudioServicesPlaySystemSound(1117)
        }
        didPlayReadyChime = true
        logger.info("ready_chime_played")
    }

    private func kickAudioAfterNetworkRecovery() async {
        guard sessionState == .active, let room else { return }
        logger.info("kick_audio_after_network_recovery")
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
        do {
            try await room.localParticipant.setMicrophone(enabled: false)
            try await Task.sleep(for: .milliseconds(200))
            try await room.localParticipant.setMicrophone(enabled: true)
        } catch {
            logger.error("kick_audio_mic_toggle_failed: \(error.localizedDescription)")
        }
        NetworkMonitor.shared.reportCurrentState(preferredBaseURL: activeBackendBaseURL)
    }

    private func triggerRecovery(_ reason: String) async {
        logger.error("recovery_triggered: \(reason, privacy: .public)")
        if autoRecoverAttempts < 1, let settings = lastSettings {
            autoRecoverAttempts += 1
            await performFullDisconnect()
            try? await Task.sleep(for: .milliseconds(700))
            await connect(settings: settings)
            return
        }
        sessionState = .error(reason)
        agentState = .idle
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
        activeBackendBaseURL = base
        NetworkMonitor.shared.sessionPreferredBaseURL = base
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
            if serverHealth.status == .online {
                NetworkMonitor.shared.reportCurrentState(preferredBaseURL: activeBackendBaseURL ?? base)
                await fetchBackendReadyChime(settings: settings, base: base)
            }
        } catch {
            serverHealth.status = .offline
        }
    }

    private struct ReadyChimeStatus: Decodable {
        let status: String
        let readyChimeAt: Double
        enum CodingKeys: String, CodingKey {
            case status
            case readyChimeAt = "ready_chime_at"
        }
    }

    private func fetchBackendReadyChime(settings: SoniqueSettings, base: String) async {
        guard let url = URL(string: "\(base)/api/chime/ready") else { return }
        var req = URLRequest(url: url, timeoutInterval: 2)
        if !settings.apiKey.isEmpty {
            req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let status = try JSONDecoder().decode(ReadyChimeStatus.self, from: data)
            guard status.readyChimeAt > 0 else { return }
            if status.readyChimeAt > lastBackendReadyChimeAt {
                lastBackendReadyChimeAt = status.readyChimeAt
                if sessionState == .active || sessionState == .connecting {
                    playReadyChimeIfNeeded()
                }
            }
        } catch {
            return
        }
    }
}

private extension SessionManager {
    func makeReadyChimeWav() -> Data? {
        let sampleRate = 44_100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let noteDuration = 0.14
        let gapDuration = 0.04
        let frequencies: [Double] = [740.0, 880.0]
        var samples: [Int16] = []

        func appendSilence(_ duration: Double) {
            let count = max(0, Int(Double(sampleRate) * duration))
            samples.append(contentsOf: repeatElement(0, count: count))
        }

        func appendNote(_ freq: Double, duration: Double) {
            let count = max(1, Int(Double(sampleRate) * duration))
            let attack = Int(Double(sampleRate) * 0.01)
            let release = Int(Double(sampleRate) * 0.03)
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                var env = 1.0
                if i < attack { env = Double(i) / Double(max(1, attack)) }
                if i > count - release { env = min(env, Double(count - i) / Double(max(1, release))) }
                let value = sin(2.0 * .pi * freq * t) * env * 0.8
                samples.append(Int16(max(-1.0, min(1.0, value)) * Double(Int16.max)))
            }
        }

        for idx in frequencies.indices {
            appendNote(frequencies[idx], duration: noteDuration)
            if idx < frequencies.count - 1 { appendSilence(gapDuration) }
        }

        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * (bitsPerSample / 8)
        let riffChunkSize = 36 + dataSize
        var data = Data(capacity: Int(44 + dataSize))
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(riffChunkSize)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(channels)
        data.appendLE(UInt32(sampleRate))
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)
        data.append("data".data(using: .ascii)!)
        data.appendLE(dataSize)
        for sample in samples {
            data.appendLE(UInt16(bitPattern: sample))
        }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}

// MARK: - RoomDelegate

extension SessionManager: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor in
            let userSpeaking = participants.contains { $0 is LocalParticipant }
            let agentSpeaking = participants.contains { $0 is RemoteParticipant }
            if userSpeaking && self.firstUserSpeechAt == nil {
                self.firstUserSpeechAt = Date()
                self.logger.info("user_speech_detected")
            }
            if agentSpeaking {
                self.hasReceivedFirstAudio = true
                self.logger.info("first_audio_received")
            }
            self.agentState = agentSpeaking ? .speaking : .listening
        }
    }

    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldValue: ConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .disconnected:
                if case .disconnecting = self.sessionState { return }
                if case .idle = self.sessionState { return }
                self.lastDisconnectAt = Date()
                self.agentState = .idle
                self.connectWatchdogTask?.cancel()
                self.firstAudioWatchdogTask?.cancel()
                self.disconnectRecoveryTask?.cancel()
                self.disconnectRecoveryTask = Task { @MainActor in
                    // Grace window for transient transport blips.
                    try? await Task.sleep(for: .seconds(2))
                    guard self.sessionState != .disconnecting else { return }
                    if let settings = self.lastSettings, self.autoRecoverAttempts < 1 {
                        self.autoRecoverAttempts += 1
                        await self.performFullDisconnect()
                        self.sessionState = .connecting
                        await self.connect(settings: settings)
                        return
                    }
                    self.sessionState = .error("Connection lost. Tap to retry.")
                }
            case .connected:
                self.disconnectRecoveryTask?.cancel()
                if self.sessionState != .active {
                    self.sessionState = .active
                }
                NetworkMonitor.shared.reportCurrentState(preferredBaseURL: self.activeBackendBaseURL)
            default:
                break
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.hasRemoteParticipant = true
            self.agentState = .listening
            self.playReadyChimeIfNeeded()
            self.logger.info("participant_seen")
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
