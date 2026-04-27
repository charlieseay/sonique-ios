import Foundation
import MessageUI
import UIKit

@MainActor
class MessageService: NSObject {
    static let shared = MessageService()

    // MARK: - Public API

    /// Check if device can send SMS messages
    func canSendSMS() -> Bool {
        return MFMessageComposeViewController.canSendText()
    }

    /// Present SMS compose view controller from a given view controller
    /// - Parameters:
    ///   - viewController: The view controller to present from
    ///   - recipients: Phone numbers to send to
    ///   - messageBody: Pre-populated message text
    ///   - delegate: Delegate to handle compose result (optional)
    func presentSMSComposer(
        from viewController: UIViewController,
        recipients: [String] = [],
        messageBody: String = "",
        delegate: MFMessageComposeViewControllerDelegate? = nil
    ) {
        guard MFMessageComposeViewController.canSendText() else {
            print("SMS composer not available on this device")
            return
        }

        let composer = MFMessageComposeViewController()
        composer.recipients = recipients
        composer.body = messageBody

        if let delegate = delegate {
            composer.messageComposeDelegate = delegate
        } else {
            composer.messageComposeDelegate = self
        }

        viewController.present(composer, animated: true)
    }
}

// MARK: - MFMessageComposeViewControllerDelegate

extension MessageService: MFMessageComposeViewControllerDelegate {
    nonisolated func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        controller.dismiss(animated: true) {
            switch result {
            case .cancelled:
                print("Message composition cancelled")
            case .failed:
                print("Message composition failed")
            case .sent:
                print("Message sent successfully")
            @unknown default:
                print("Unknown message composition result")
            }
        }
    }
}
