//
//  SecurityLoggingTests.swift
//  RunAnywhere SDK
//
//  Verifies that sensitive values (API keys, tokens, passwords) are redacted
//  before they reach any log destination — both from message strings and
//  metadata dictionaries. Regression guard for issue #246.
//

import XCTest
@testable import RunAnywhere

// MARK: - Capturing Destination

/// Test-only LogDestination that records every LogEntry written to it.
private final class CapturingDestination: LogDestination, @unchecked Sendable {
    static let destinationID = "test.security.capturing"

    var identifier: String { Self.destinationID }
    var isAvailable: Bool { true }

    private(set) var captured: [LogEntry] = []

    func write(_ entry: LogEntry) { captured.append(entry) }
    func flush() {}
    func reset() { captured.removeAll() }
}

// MARK: - SecurityLoggingTests

final class SecurityLoggingTests: XCTestCase {

    private var destination: CapturingDestination!

    override func setUp() {
        super.setUp()
        destination = CapturingDestination()

        var config = Logging.shared.configuration
        config.enableLocalLogging = false   // suppress os.Logger output in CI
        config.enableSentryLogging = false
        config.minLogLevel = .debug
        Logging.shared.configure(config)
        Logging.shared.addDestination(destination)
    }

    override func tearDown() {
        Logging.shared.removeDestination(destination)
        super.tearDown()
    }

    // MARK: - Message string sanitization

    func testApiKeyEqualsInMessageIsRedacted() {
        Logging.shared.log(level: .info, category: "Test",
                           message: "Configured with apiKey=sk-prod-abc123")
        let msg = destination.captured.first?.message ?? ""
        XCTAssertFalse(msg.contains("sk-prod-abc123"), "API key value must not appear in log")
        XCTAssertTrue(msg.contains("[REDACTED]"), "Redaction marker must be present")
    }

    func testApiKeyColonInMessageIsRedacted() {
        Logging.shared.log(level: .info, category: "Test",
                           message: "api_key: supersecret")
        let msg = destination.captured.first?.message ?? ""
        XCTAssertFalse(msg.contains("supersecret"))
        XCTAssertTrue(msg.contains("[REDACTED]"))
    }

    func testPasswordInMessageIsRedacted() {
        Logging.shared.log(level: .warning, category: "Test",
                           message: "Login attempt password=hunter2 failed")
        let msg = destination.captured.first?.message ?? ""
        XCTAssertFalse(msg.contains("hunter2"))
        XCTAssertTrue(msg.contains("[REDACTED]"))
    }

    func testBearerTokenInMessageIsRedacted() {
        Logging.shared.log(level: .error, category: "Test",
                           message: "Request rejected — Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig")
        let msg = destination.captured.first?.message ?? ""
        XCTAssertFalse(msg.contains("eyJhbGciOiJIUzI1NiJ9.payload.sig"))
        XCTAssertTrue(msg.contains("[REDACTED]"))
    }

    func testSecretInMessageIsRedacted() {
        Logging.shared.log(level: .debug, category: "Test",
                           message: "secret=xyzTopSecret")
        let msg = destination.captured.first?.message ?? ""
        XCTAssertFalse(msg.contains("xyzTopSecret"))
        XCTAssertTrue(msg.contains("[REDACTED]"))
    }

    func testTokenColonInMessageIsRedacted() {
        Logging.shared.log(level: .info, category: "Test",
                           message: "Stored token: abc.def.ghi")
        let msg = destination.captured.first?.message ?? ""
        XCTAssertFalse(msg.contains("abc.def.ghi"))
        XCTAssertTrue(msg.contains("[REDACTED]"))
    }

    func testNonSensitiveMessagePassesThroughUnchanged() {
        let plain = "Model qwen3-0.6b loaded in 340ms"
        Logging.shared.log(level: .info, category: "Test", message: plain)
        XCTAssertEqual(destination.captured.first?.message, plain)
    }

    func testEmptyMessagePassesThroughUnchanged() {
        Logging.shared.log(level: .info, category: "Test", message: "")
        XCTAssertEqual(destination.captured.first?.message, "")
    }

    // MARK: - Metadata sanitization (regression)

    func testApiKeyInMetadataIsRedacted() {
        Logging.shared.log(level: .info, category: "Test", message: "Init",
                           metadata: ["apiKey": "sk-supersecret"])
        let meta = destination.captured.first?.metadata ?? [:]
        XCTAssertEqual(meta["apiKey"], "[REDACTED]", "apiKey metadata value must be redacted")
    }

    func testPasswordInMetadataIsRedacted() {
        Logging.shared.log(level: .info, category: "Test", message: "Auth",
                           metadata: ["password": "letmein"])
        let meta = destination.captured.first?.metadata ?? [:]
        XCTAssertEqual(meta["password"], "[REDACTED]")
    }

    func testNonSensitiveMetadataPassesThroughUnchanged() {
        Logging.shared.log(level: .info, category: "Test", message: "Info",
                           metadata: ["modelId": "qwen3-0.6b", "duration_ms": 200])
        let meta = destination.captured.first?.metadata ?? [:]
        XCTAssertEqual(meta["modelId"], "qwen3-0.6b")
    }

    // MARK: - logError call-site sanitization

    func testLogErrorWithSensitiveAdditionalInfoIsRedacted() {
        struct FakeError: Error, LocalizedError {
            var errorDescription: String? { "Request failed" }
        }
        let logger = SDKLogger(category: "Test")
        logger.logError(FakeError(), additionalInfo: "token=leaked-value-xyz")
        let msg = destination.captured.first?.message ?? ""
        XCTAssertFalse(msg.contains("leaked-value-xyz"),
                       "Sensitive value in additionalInfo must be redacted via sanitizeMessage")
        XCTAssertTrue(msg.contains("[REDACTED]"))
    }

    func testLogErrorWithCleanAdditionalInfoPassesThrough() {
        struct FakeError: Error, LocalizedError {
            var errorDescription: String? { "Timeout" }
        }
        let logger = SDKLogger(category: "Test")
        logger.logError(FakeError(), additionalInfo: "retrying request")
        let msg = destination.captured.first?.message ?? ""
        XCTAssertTrue(msg.contains("retrying request"))
        XCTAssertFalse(msg.contains("[REDACTED]"))
    }
}
