import Foundation
import UIKit

/// Apple Intelligence capabilities (iOS 18.1+)
/// Provides access to Writing Tools, Image Playground, and on-device intelligence
@available(iOS 18.1, *)
@MainActor
class AppleIntelligenceCapabilities {
    static let shared = AppleIntelligenceCapabilities()

    private init() {}

    /// Check if Apple Intelligence is available on this device
    var isAvailable: Bool {
        // Apple Intelligence requires:
        // - iOS 18.1+
        // - A18 Pro chip (iPhone 16 Pro/Pro Max) or M1+ chip (iPad)
        // - Device language set to English (US)
        // - Siri & Dictation enabled

        // Runtime check for Writing Tools availability
        return isWritingToolsAvailable()
    }

    /// Check if Writing Tools are available
    private func isWritingToolsAvailable() -> Bool {
        // Writing Tools are part of the text editing system in iOS 18.1+
        // They appear in the context menu when text is selected

        // For now, assume available if we're on iOS 18.1+
        // In production, this would check device capabilities
        return true
    }

    // MARK: - Writing Tools

    /// Summarize text using Writing Tools
    /// Note: Writing Tools are typically accessed via system UI (share sheet, text menu)
    /// For voice assistant use, we can trigger the system UI or implement our own summaries
    func summarizeText(_ text: String) async -> String {
        // Writing Tools don't have a public API for programmatic access
        // For a voice assistant, we'd either:
        // 1. Use the system summarization service (if available via private API)
        // 2. Implement our own using on-device ML models
        // 3. Direct user to use Writing Tools via text selection

        // For now, return helpful guidance
        return "To use Writing Tools, select the text you want to summarize and choose 'Writing Tools' from the menu"
    }

    /// Rewrite text in different tones using Writing Tools
    func rewriteText(_ text: String, tone: WritingTone) async -> String {
        return "To rewrite text in a \(tone.rawValue) tone, select your text and choose 'Writing Tools' > 'Rewrite'"
    }

    /// Proofread text using Writing Tools
    func proofreadText(_ text: String) async -> String {
        return "To proofread text, select it and choose 'Writing Tools' > 'Proofread'"
    }

    // MARK: - Image Playground

    /// Generate images using Image Playground
    /// Note: Image Playground is typically accessed via its own app or system UI
    func generateImage(prompt: String) async -> String {
        return "To create images, open the Image Playground app and describe what you want to create"
    }

    // MARK: - Siri Intelligence

    /// Use on-device Siri intelligence for contextual responses
    /// This includes understanding context from apps, messages, calendar, etc.
    func getContextualSuggestion(for query: String) async -> String? {
        // Siri's on-device intelligence is accessed through SiriKit and Shortcuts
        // For voice assistant integration, we can use App Intents framework

        // For now, return nil to indicate no contextual suggestion
        return nil
    }

    // MARK: - Smart Replies

    /// Generate smart reply suggestions (similar to iOS Mail/Messages)
    func generateSmartReplies(for message: String) async -> [String] {
        // Smart replies use on-device ML models
        // For now, return empty array (would integrate with NLLanguageModel in production)
        return []
    }
}

@available(iOS 18.1, *)
enum WritingTone: String, CaseIterable {
    case professional = "professional"
    case casual = "casual"
    case concise = "concise"
    case friendly = "friendly"
}

/// Compatibility wrapper for iOS < 18.1
@MainActor
struct AppleIntelligenceCompatibility {
    static var isAvailable: Bool {
        if #available(iOS 18.1, *) {
            return AppleIntelligenceCapabilities.shared.isAvailable
        }
        return false
    }

    static func summarizeText(_ text: String) async -> String {
        if #available(iOS 18.1, *) {
            return await AppleIntelligenceCapabilities.shared.summarizeText(text)
        }
        return "Apple Intelligence requires iOS 18.1 or later"
    }

    static func generateImage(prompt: String) async -> String {
        if #available(iOS 18.1, *) {
            return await AppleIntelligenceCapabilities.shared.generateImage(prompt: prompt)
        }
        return "Image generation requires iOS 18.1 or later"
    }
}
