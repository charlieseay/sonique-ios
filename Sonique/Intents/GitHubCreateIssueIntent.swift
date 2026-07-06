import AppIntents
import Foundation

/// Create a GitHub issue via SoniqueBar.
/// Voice: "Create GitHub issue: fix microphone echo"
@available(iOS 16.0, *)
struct GitHubCreateIssueIntent: AppIntent {
    static var title: LocalizedStringResource = "Create GitHub Issue"
    static var description = IntentDescription("Creates a new issue in a GitHub repository.")

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Repository", default: "charlieseay/sonique-ios")
    var repository: String?

    @Parameter(title: "Body")
    var body: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create GitHub issue \(\.$title)") {
            \.$repository
            \.$body
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        if let error = IntentParameterValidator.validateTitle(title) {
            return .result(value: error, dialog: IntentDialog(stringLiteral: error))
        }

        var params = ["action": "create_issue", "title": title]
        if let repository, !repository.isEmpty {
            params["repo"] = IntentParameterValidator.sanitizeRepo(repository)
        }
        if let body, !body.isEmpty {
            params["body"] = body
        }

        let result = await IntentBarClient.execute(intent: "github", parameters: params)
        return .result(value: result.message, dialog: IntentDialog(stringLiteral: result.message))
    }
}
