import Foundation
import AVFoundation

/// TTS provider protocol - ElevenLabs and Kokoro both proxy through macOS SoniqueBar
///
/// Architecture:
/// - iOS requests TTS from macOS :8890/synthesize/kokoro or /synthesize/elevenlabs
/// - macOS handles API keys (ElevenLabs) or MLX models (Kokoro)
/// - macOS returns PCM data (Int16, 24kHz, mono)
/// - iOS plays PCM via AVAudioPlayerNode in VoiceSession
/// - Barge-in works instantly: playerNode.stop() interrupts playback immediately
///
/// Implementations: See ElevenLabsDirectTTS.swift and KokoroTTS.swift
protocol TTSProvider {
    func speak(_ text: String, completion: @escaping () -> Void) async
    func fetchPCM(_ text: String) async -> Data?  // Returns PCM from macOS proxy
    func stop()
}
