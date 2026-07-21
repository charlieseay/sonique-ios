import Foundation

extension Notification.Name {
    static let speechTranscriptComplete = Notification.Name("speechTranscriptComplete")
}

enum RecognitionError: Error {
    case recognizerUnavailable
}
