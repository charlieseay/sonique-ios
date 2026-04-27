import AppIntents
import Foundation
import UIKit

// MARK: - Send Message Intent

struct SendMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a message"
    static var description = IntentDescription(
        "Open the message composer to send an SMS or iMessage.",
        categoryName: "Messaging"
    )
    static var openAppWhenRun = true

    @Parameter(title: "Recipient phone number")
    var recipientNumber: String

    @Parameter(title: "Message")
    var messageText: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let messageService = MessageService.shared

        guard messageService.canSendSMS() else {
            return .result(dialog: IntentDialog(stringLiteral: "This device cannot send messages."))
        }

        // Get the current window scene's root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return .result(dialog: IntentDialog(stringLiteral: "Could not present message composer."))
        }

        // Present the composer on the main thread
        await MainActor.run {
            messageService.presentSMSComposer(
                from: rootViewController,
                recipients: [recipientNumber],
                messageBody: messageText
            )
        }

        return .result(dialog: IntentDialog(stringLiteral: "Message composer opened."))
    }
}

// MARK: - Check Message Capability Intent

struct CheckMessageCapabilityIntent: AppIntent {
    static var title: LocalizedStringResource = "Can send messages"
    static var description = IntentDescription(
        "Check if this device can send SMS or iMessage.",
        categoryName: "Messaging"
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let messageService = MessageService.shared
        let canSend = messageService.canSendSMS()

        let message = canSend ? "This device can send messages." : "This device cannot send messages."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
