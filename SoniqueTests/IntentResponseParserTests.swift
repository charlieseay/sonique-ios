import XCTest
@testable import Sonique

final class IntentResponseParserTests: XCTestCase {

    func testParseSuccessResponse() throws {
        let json = """
        {"success":true,"message":"Posted to #sonique","error":null,"data":{"channel":"sonique"}}
        """.data(using: .utf8)!
        let response = IntentResponseParser.parse(json)
        XCTAssertEqual(response?.success, true)
        XCTAssertEqual(response?.message, "Posted to #sonique")
        XCTAssertNil(response?.error)
        XCTAssertEqual(response?.data?["channel"], "sonique")
    }

    func testParseFailureResponse() throws {
        let json = """
        {"success":false,"message":"Slack token missing.","error":"slack_token_missing","data":null}
        """.data(using: .utf8)!
        let response = IntentResponseParser.parse(json)
        XCTAssertEqual(response?.success, false)
        XCTAssertEqual(response?.error, "slack_token_missing")
    }

    func testParseFallbackWithLegacyResponseField() {
        let json = """
        {"response":"Task created.","success":true}
        """.data(using: .utf8)!
        let response = IntentResponseParser.parseFallback(json)
        XCTAssertEqual(response?.message, "Task created.")
        XCTAssertEqual(response?.success, true)
    }

    func testParseFallbackReturnsNilForInvalidJSON() {
        let json = "not json".data(using: .utf8)!
        XCTAssertNil(IntentResponseParser.parse(json))
        XCTAssertNil(IntentResponseParser.parseFallback(json))
    }

    func testParseUnreachableErrorCode() {
        let result = IntentBarResult.unreachable
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorCode, "unreachable")
        XCTAssertTrue(result.message.contains("brain"))
    }

    func testIntentAPIResponseEquality() {
        let a = IntentAPIResponse(success: true, message: "ok")
        let b = IntentAPIResponse(success: true, message: "ok")
        XCTAssertEqual(a, b)
    }
}
