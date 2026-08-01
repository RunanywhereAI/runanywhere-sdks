//
//  AmbientMemorySurfaceTests.swift
//  RunAnywhereTests
//
//  Covers the parts of the ambient-memory solution that are pure: the
//  configuration derivations that set segment boundaries, and the extraction
//  response parser, which has to survive whatever shape a small local model
//  decides to emit.
//

import XCTest
@testable import RunAnywhere

final class AmbientMemorySurfaceTests: XCTestCase {

    // MARK: - Configuration

    func testDefaultsUseCataloguedVADAndSuppliedSTT() {
        let config = RAAmbientConfiguration.defaults(sttModelID: "parakeet")

        XCTAssertEqual(config.sttModelID, "parakeet")
        XCTAssertEqual(config.vadModelID, RunAnywhere.defaultVADModelID)
        XCTAssertEqual(config.sampleRate, 16_000)
        XCTAssertFalse(config.retainSegmentAudio, "Retaining raw audio must be opt-in")
    }

    func testVADFrameIs32MillisecondsAtTheConfiguredRate() {
        var config = RAAmbientConfiguration.defaults(sttModelID: "stt")
        XCTAssertEqual(config.vadFrameSampleCount, 512)

        config.sampleRate = 8_000
        XCTAssertEqual(config.vadFrameSampleCount, 256)
    }

    func testVADFrameNeverDropsBelowTheDetectorFloor() {
        var config = RAAmbientConfiguration.defaults(sttModelID: "stt")
        config.sampleRate = 1_000

        XCTAssertEqual(config.vadFrameSampleCount, 160, "A tiny rate must still produce a usable frame")
    }

    func testAudioBufferDepthScalesWithSegmentQueueDepth() {
        var config = RAAmbientConfiguration.defaults(sttModelID: "stt")
        config.maxQueuedSegments = 1
        XCTAssertEqual(config.maxQueuedAudioChunks, 16, "A shallow segment queue keeps a usable audio floor")

        config.maxQueuedSegments = 8
        XCTAssertEqual(config.maxQueuedAudioChunks, 128)
    }

    // MARK: - Transcript

    func testRealTimeFactorComparesTranscriptionAgainstAudioLength() {
        let transcript = Self.transcript(audioDurationMs: 4_000, transcriptionMs: 1_000)
        XCTAssertEqual(transcript.realTimeFactor, 0.25, accuracy: 0.0001)
    }

    func testRealTimeFactorIsZeroForEmptyAudio() {
        let transcript = Self.transcript(audioDurationMs: 0, transcriptionMs: 900)
        XCTAssertEqual(transcript.realTimeFactor, 0)
    }

    // MARK: - Digest Parsing

    func testParsesCleanJSONResponse() {
        let response = """
        {"summary":"Planned the release","actionItems":[
          "Ship the beta on Friday",
          "Switch the build to the quality profile"
        ]}
        """

        let parsed = AmbientDigestPrompt.parse(response, fallbackText: "transcript")

        XCTAssertEqual(parsed.summary, "Planned the release")
        XCTAssertEqual(parsed.actionItems.map(\.text), [
            "Ship the beta on Friday",
            "Switch the build to the quality profile",
        ])
    }

    func testParsesJSONWrappedInFencesAndCommentary() {
        let response = """
        Sure! Here is the JSON you asked for:
        ```json
        {"summary":"Grocery list","actionItems":["Buy oat milk"]}
        ```
        Let me know if you need anything else.
        """

        let parsed = AmbientDigestPrompt.parse(response, fallbackText: "transcript")

        XCTAssertEqual(parsed.summary, "Grocery list")
        XCTAssertEqual(parsed.actionItems.map(\.text), ["Buy oat milk"])
    }

    func testActionItemObjectsAreUnwrappedToText() {
        let response = #"{"summary":"s","actionItems":[{"text":"Water the plants"},{"action":"Call Ana"}]}"#

        let parsed = AmbientDigestPrompt.parse(response, fallbackText: "transcript")

        XCTAssertEqual(parsed.actionItems.map(\.text), ["Water the plants", "Call Ana"])
    }

    func testBlankAndDuplicateActionItemsAreDropped() {
        let response = #"{"summary":"s","actionItems":["  ","Call Ana","call ana",{"note":"x"}]}"#

        let parsed = AmbientDigestPrompt.parse(response, fallbackText: "transcript")

        XCTAssertEqual(
            parsed.actionItems.map(\.text),
            ["Call Ana"],
            "A merge pass must not restate the same task twice"
        )
    }

    func testParsesStructuredSectionsAndCitations() {
        let response = """
        {"title":"Advisor sync","sections":[{"heading":"Partners","bullets":[\
        {"lead":"Qualcomm","text":"Joint GTM planned","sourceSegmentIndices":[3]}\
        ]}],"actionItems":[{"text":"Send deck","sourceSegmentIndices":[3,4]}]}
        """
        let parsed = AmbientDigestPrompt.parse(response, fallbackText: "fallback")
        XCTAssertEqual(parsed.title, "Advisor sync")
        XCTAssertEqual(parsed.sections.count, 1)
        XCTAssertEqual(parsed.sections[0].bullets[0].lead, "Qualcomm")
        XCTAssertEqual(parsed.sections[0].bullets[0].sourceSegmentIndices, [3])
        XCTAssertEqual(parsed.actionItems[0].sourceSegmentIndices, [3, 4])
    }

    func testNonJSONResponseDegradesToTheTranscriptSummary() {
        let parsed = AmbientDigestPrompt.parse(
            "I could not find anything worth summarizing.",
            fallbackText: "We talked about the roadmap."
        )

        XCTAssertTrue(parsed.actionItems.isEmpty)
        XCTAssertEqual(parsed.summary, "We talked about the roadmap.")
    }

    func testEmptySummaryFallsBackToTheTranscript() {
        let parsed = AmbientDigestPrompt.parse(
            #"{"summary":"  ","actionItems":[]}"#,
            fallbackText: "Standup notes."
        )

        XCTAssertEqual(parsed.summary, "Standup notes.")
    }

    func testMergePromptAsksForDeduplication() {
        let system = AmbientDigestPrompt.system(mode: .merge, maxActionItems: 8)

        XCTAssertTrue(system.contains("merge"))
        XCTAssertTrue(system.contains("duplicate"))
        XCTAssertTrue(AmbientDigestPrompt.user(text: "a", mode: .merge).contains("Partial summaries:"))
        XCTAssertTrue(AmbientDigestPrompt.user(text: "a", mode: .chunk).contains("Transcript:"))
    }

    // MARK: - Helpers

    private static func transcript(audioDurationMs: Int, transcriptionMs: Int) -> RAAmbientTranscript {
        RAAmbientTranscript(
            id: "segment",
            sessionID: "session",
            segmentID: "segment",
            segmentIndex: 0,
            text: "hello",
            confidence: 0.9,
            languageCode: "en",
            startedAt: Date(),
            endedAt: Date(),
            audioDurationMs: audioDurationMs,
            transcriptionMs: transcriptionMs,
            modelID: "stt"
        )
    }
}
