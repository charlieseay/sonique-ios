import AppIntents
import Foundation

/// Search GitHub pull requests via SoniqueBar.
/// Voice: "Search GitHub for pull requests labeled bug"
@available(iOS 16.0, *)
struct GitHubSearchIntent: AppIntent {
    static var title: LocalizedStringResource = "Search GitHub"
    static var description = IntentDescription("Searches open pull requests on GitHub.")

    @Parameter(title: "Query")
    var query: String

    @Parameter(title: "Repository", default: "charlieseay/sonique-ios")
    var repository: String?

    @Parameter(title: "Label")
    var label: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Search GitHub for \(\.$query)") {
            \.$repository
            \.$label
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let msg = "Search query cannot be empty."
            return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
        }

        var params = ["query": trimmed]
        if let repository, !repository.isEmpty {
            params["repo"] = IntentParameterValidator.sanitizeRepo(repository)
        }
        if let label, !label.isEmpty {
            params["label"] = label.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let result = await IntentBarClient.execute(intent: "github", parameters: params)
        return .result(value: result.message, dialog: IntentDialog(stringLiteral: result.message))
    }
}
