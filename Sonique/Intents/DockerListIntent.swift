import AppIntents
import Foundation

/// List Docker containers via SoniqueBar.
/// Voice: "List Docker containers"
@available(iOS 16.0, *)
struct DockerListIntent: AppIntent {
    static var title: LocalizedStringResource = "List Docker Containers"
    static var description = IntentDescription("Lists running Docker containers.")

    @Parameter(title: "Show All", default: false)
    var showAll: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("List Docker containers") {
            \.$showAll
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let params = ["all": showAll ? "true" : "false"]
        let result = await IntentBarClient.execute(intent: "docker", parameters: params)
        return .result(value: result.message, dialog: IntentDialog(stringLiteral: result.message))
    }
}
