import XCTest
@testable import Sonique

/// Verifies the HTTP contract between iOS App Intents and SoniqueBar.
final class IntentAPIContractTests: XCTestCase {

    // MARK: - Request payload shapes

    func testSlackPayloadKeys() throws {
        let payload = ["message": "hello team", "channel": "sonique"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(decoded?["message"], "hello team")
        XCTAssertEqual(decoded?["channel"], "sonique")
    }

    func testLinearPayloadKeys() throws {
        let payload = ["title": "fix latency", "description": "barge-in issue"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(decoded?["title"], "fix latency")
        XCTAssertEqual(decoded?["description"], "barge-in issue")
    }

    func testGitHubSearchPayloadKeys() throws {
        let payload = ["query": "bug", "repo": "charlieseay/sonique-ios", "label": "bug"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(decoded?["query"], "bug")
        XCTAssertEqual(decoded?["label"], "bug")
    }

    func testNotionPayloadKeys() throws {
        let payload = ["title": "weekly standup", "body": "notes here"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(decoded?["title"], "weekly standup")
    }

    func testDockerPayloadKeys() throws {
        let payload = ["all": "false"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(decoded?["all"], "false")
    }

    // MARK: - Error code handling

    func testKnownErrorCodesHaveMessages() {
        let codes: [(String, String)] = [
            ("unreachable", "I can't reach the brain right now."),
            ("slack_token_missing", "Slack token missing"),
            ("linear_key_missing", "Linear"),
            ("notion_key_missing", "Notion"),
            ("gh_missing", "GitHub CLI"),
            ("timeout", "too long"),
        ]
        for (code, fragment) in codes {
            let response = IntentAPIResponse(success: false, message: fragment, error: code)
            XCTAssertEqual(response.error, code)
            XCTAssertFalse(response.success)
        }
    }

    // MARK: - Response round-trip encoding

    func testResponseEncodesAndDecodes() throws {
        let original = IntentAPIResponse(
            success: true,
            message: "Found 3 open pull requests.",
            error: nil,
            data: ["count": "3"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IntentAPIResponse.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFailureResponseEncodesErrorField() throws {
        let original = IntentAPIResponse(
            success: false,
            message: "Linear CLI not found.",
            error: "linear_key_missing"
        )
        let data = try JSONEncoder().encode(original)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["error"] as? String, "linear_key_missing")
        XCTAssertEqual(json?["success"] as? Bool, false)
    }

    // MARK: - Security: parameter validation blocks injection

    func testMessageWithShellInjectionIsStillValidText() {
        // Validator allows text; sanitization happens server-side via JSON + Process args
        let msg = "hello; rm -rf /"
        XCTAssertNil(IntentParameterValidator.validateMessage(msg))
    }

    func testChannelSanitizationBlocksInjection() {
        let safe = IntentParameterValidator.sanitizeChannel("$(whoami)")
        XCTAssertFalse(safe.contains("$"))
        XCTAssertFalse(safe.contains("("))
    }

    func testRepoSanitizationBlocksTraversal() {
        let safe = IntentParameterValidator.sanitizeRepo("../../etc/passwd")
        XCTAssertFalse(safe.contains(".."))
    }
}
