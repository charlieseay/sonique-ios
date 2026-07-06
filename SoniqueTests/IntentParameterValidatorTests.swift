import XCTest
@testable import Sonique

final class IntentParameterValidatorTests: XCTestCase {

    // MARK: - Message validation

    func testValidateMessageAcceptsNormalText() {
        XCTAssertNil(IntentParameterValidator.validateMessage("hello team"))
    }

    func testValidateMessageRejectsEmpty() {
        XCTAssertEqual(IntentParameterValidator.validateMessage(""), "Message cannot be empty.")
    }

    func testValidateMessageRejectsWhitespaceOnly() {
        XCTAssertEqual(IntentParameterValidator.validateMessage("   "), "Message cannot be empty.")
    }

    func testValidateMessageRejectsTooLong() {
        let long = String(repeating: "a", count: IntentParameterValidator.maxMessageLength + 1)
        XCTAssertNotNil(IntentParameterValidator.validateMessage(long))
    }

    func testValidateMessageAcceptsMaxLength() {
        let max = String(repeating: "a", count: IntentParameterValidator.maxMessageLength)
        XCTAssertNil(IntentParameterValidator.validateMessage(max))
    }

    // MARK: - Title validation

    func testValidateTitleAcceptsNormalText() {
        XCTAssertNil(IntentParameterValidator.validateTitle("fix microphone echo"))
    }

    func testValidateTitleRejectsEmpty() {
        XCTAssertEqual(IntentParameterValidator.validateTitle(""), "Title cannot be empty.")
    }

    func testValidateTitleRejectsTooLong() {
        let long = String(repeating: "x", count: IntentParameterValidator.maxTitleLength + 1)
        XCTAssertNotNil(IntentParameterValidator.validateTitle(long))
    }

    // MARK: - Channel sanitization

    func testSanitizeChannelStripsHash() {
        XCTAssertEqual(IntentParameterValidator.sanitizeChannel("#sonique"), "sonique")
    }

    func testSanitizeChannelRemovesShellMetacharacters() {
        XCTAssertEqual(IntentParameterValidator.sanitizeChannel("chan;rm -rf"), "chanrm-rf")
    }

    func testSanitizeChannelPreservesDashUnderscore() {
        XCTAssertEqual(IntentParameterValidator.sanitizeChannel("my-channel_1"), "my-channel_1")
    }

    // MARK: - Repo sanitization

    func testSanitizeRepoAcceptsOwnerSlashRepo() {
        XCTAssertEqual(IntentParameterValidator.sanitizeRepo("charlieseay/sonique-ios"), "charlieseay/sonique-ios")
    }

    func testSanitizeRepoStripsInvalidChars() {
        XCTAssertEqual(IntentParameterValidator.sanitizeRepo("owner/repo;drop"), "owner/repo")
    }
}
