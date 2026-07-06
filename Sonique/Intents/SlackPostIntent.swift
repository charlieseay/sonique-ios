import AppIntents
import Foundation

/// Post a message to Slack via SoniqueBar.
/// Voice: "Post to Slack: hello team"
@available(iOS 16.0, *)
struct SlackPostIntent: AppIntent {
    static var title: LocalizedStringResource = "Post to Slack"
    static var description = IntentDescription("Posts a message to a Slack channel.")

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Channel", default: "sonique")
    var channel: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Post \(\.$message) to Slack") {
            \.$channel
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        if let error = IntentParameterValidator.validateMessage(message) {
            return .result(value: error, dialog: IntentDialog(stringLiteral: error))
        }

        var params = ["message": message]
        if let channel, !channel.isEmpty {
            params["channel"] = IntentParameterValidator.sanitizeChannel(channel)
        }

        let result = await IntentBarClient.execute(intent: "slack", parameters: params)
        return .result(value: result.message, dialog: IntentDialog(stringLiteral: result.message))
    }
}
