import AppIntents
import Foundation

/// Create a Notion database entry via SoniqueBar.
/// Voice: "Create Notion page: weekly standup notes"
@available(iOS 16.0, *)
struct NotionCreateIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Notion Page"
    static var description = IntentDescription("Creates a new page in your Notion database.")

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Body")
    var body: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create Notion page \(\.$title)") {
            \.$body
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        if let error = IntentParameterValidator.validateTitle(title) {
            return .result(value: error, dialog: IntentDialog(stringLiteral: error))
        }

        var params = ["title": title]
        if let body, !body.isEmpty {
            params["body"] = body
        }

        let result = await IntentBarClient.execute(intent: "notion", parameters: params)
        return .result(value: result.message, dialog: IntentDialog(stringLiteral: result.message))
    }
}
