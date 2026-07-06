import AppIntents
import Foundation

/// Create a Linear issue via SoniqueBar.
/// Voice: "Create Linear task: fix barge-in latency"
@available(iOS 16.0, *)
struct LinearCreateIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Linear Task"
    static var description = IntentDescription("Creates a new task in Linear.")

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Description")
    var taskDescription: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create Linear task \(\.$title)") {
            \.$taskDescription
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        if let error = IntentParameterValidator.validateTitle(title) {
            return .result(value: error, dialog: IntentDialog(stringLiteral: error))
        }

        var params = ["title": title]
        if let taskDescription, !taskDescription.isEmpty {
            params["description"] = taskDescription
        }

        let result = await IntentBarClient.execute(intent: "linear", parameters: params)
        return .result(value: result.message, dialog: IntentDialog(stringLiteral: result.message))
    }
}
