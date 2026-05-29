import Foundation

enum Config {
    /// ElevenLabs API key for STT/TTS streaming
    static let elevenlabsAPIKey = "534f60fb2e52d41c88f518c4cf0d6cf14788f34c565c8ecf46dbe5b56c82054e"

    /// SoniqueBar command server endpoint
    /// Local Mac Mini on same WiFi network
    static let commandServerURL = "http://192.168.0.221:8890"

    /// Character limit tracking (50,000/month)
    static let characterLimit = 50_000

    /// UserDefaults key for selected voice
    static let voiceKey = "selectedVoice"

    /// Get selected voice from UserDefaults
    static var selectedVoice: ElevenLabsVoice {
        get {
            if let raw = UserDefaults.standard.string(forKey: voiceKey),
               let voice = ElevenLabsVoice(rawValue: raw) {
                return voice
            }
            return .josh  // Default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: voiceKey)
        }
    }
}
