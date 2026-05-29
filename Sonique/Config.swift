import Foundation

enum Config {
    /// ElevenLabs API key for STT/TTS streaming
    static let elevenlabsAPIKey = "534f60fb2e52d41c88f518c4cf0d6cf14788f34c565c8ecf46dbe5b56c82054e"

    /// ElevenLabs conversational AI agent ID
    /// Default agent handles generic conversation
    static let elevenlabsAgentID = "default"

    /// SoniqueBar command server endpoint
    /// Local Mac Mini on same WiFi network
    static let commandServerURL = "http://192.168.0.221:8890"

    /// Character limit tracking (50,000/month)
    static let characterLimit = 50_000
}
