import Foundation
import AVFoundation

/// TTS provider protocol - ElevenLabs and VoiceBox both proxy through macOS SoniqueBar
///
/// Architecture:
/// - iOS requests TTS from macOS :8890/synthesize/voicebox or /synthesize/elevenlabs
/// - macOS handles VoiceBox (local server on :17493) and ElevenLabs API (BYO-AI)
/// - macOS returns PCM data (Int16, 24kHz, mono)
/// - iOS plays PCM via AVAudioPlayerNode in VoiceSession
/// - Barge-in works instantly: playerNode.stop() interrupts playback immediately
///
/// Implementations: See ElevenLabsDirectTTS.swift and VoiceBoxTTS.swift
protocol TTSProvider {
    func speak(_ text: String, completion: @escaping () -> Void) async
    func fetchPCM(_ text: String) async -> Data?  // Returns PCM from macOS proxy
    func stop()
}
