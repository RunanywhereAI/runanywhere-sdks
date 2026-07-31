//
//  AmbientRecordTests.swift
//  RunAnywhereAIUnitTests
//
//  Persistence semantics the notes feature depends on: idempotent upserts,
//  action-item merging, audio-only expiry, and the derived values shown in the
//  UI.
//

import Foundation
import RunAnywhere
import XCTest
@testable import RunAnywhereAI

final class AmbientRecordTests: XCTestCase {

    // MARK: - Idempotent Persistence

    func testUpsertingTheSameSegmentReplacesRatherThanAppends() {
        var session = Self.session()
        let segment = Self.segment(index: 0)

        session.upsert(segment)
        session.upsert(segment)

        XCTAssertEqual(session.segments.count, 1, "A replayed segment event must not duplicate the record")
    }

    func testUpsertingATranscribedSegmentUpdatesInPlace() {
        var session = Self.session()
        var segment = Self.segment(index: 0)
        session.upsert(segment)

        segment.apply(Self.transcript(segmentID: segment.id, text: "hello there"))
        session.upsert(segment)

        XCTAssertEqual(session.segments.count, 1)
        XCTAssertEqual(session.segments[0].transcript, "hello there")
        XCTAssertEqual(session.transcribedSegments.count, 1)
    }

    func testUntranscribedSegmentsAreExcludedFromTheTranscribedSet() {
        var session = Self.session()
        session.upsert(Self.segment(index: 0))

        XCTAssertTrue(session.transcribedSegments.isEmpty)
    }

    func testFullTranscriptJoinsEverySegmentIntoOneBody() {
        var session = Self.session()
        session.upsert(Self.transcribedSegment(index: 0, text: "Ship the beta."))
        session.upsert(Self.transcribedSegment(index: 1, text: "  "))
        session.upsert(Self.transcribedSegment(index: 2, text: "Then tell Ana."))

        XCTAssertEqual(session.fullTranscript, "Ship the beta. Then tell Ana.")
    }

    // MARK: - Action Items

    func testMergingActionItemsDropsRepeatsAcrossChunks() {
        var session = Self.session()

        session.mergeActionItems(["Call the vet", "Book the flight"])
        session.mergeActionItems(["call the vet  ", "Pack a bag"])

        XCTAssertEqual(session.actionItems.map(\.text), ["Call the vet", "Book the flight", "Pack a bag"])
    }

    func testAManualItemSurvivesAReDigest() {
        var session = Self.session()
        session.mergeActionItems(["Call the vet"])
        session.actionItems.append(AmbientActionItem(text: "Water the plants", isManual: true))

        session.replaceMachineActionItems(with: ["Call the vet", "Book the flight"])

        XCTAssertEqual(
            session.actionItems.map(\.text).sorted(),
            ["Book the flight", "Call the vet", "Water the plants"],
            "The merge pass must never erase something the tester typed"
        )
        XCTAssertTrue(try XCTUnwrap(session.actionItems.first { $0.text == "Water the plants" }).isManual)
    }

    func testReDigestKeepsWhatTheTesterAlreadyTickedOff() {
        var session = Self.session()
        session.mergeActionItems(["Call the vet"])
        session.actionItems[0].isDone = true

        session.replaceMachineActionItems(with: ["Call the vet", "Book the flight"])

        XCTAssertTrue(try XCTUnwrap(session.actionItems.first { $0.text == "Call the vet" }).isDone)
        XCTAssertFalse(try XCTUnwrap(session.actionItems.first { $0.text == "Book the flight" }).isDone)
    }

    // MARK: - Derived Values

    func testRealTimeFactorIsNilUntilTheSegmentIsTranscribed() {
        var segment = Self.segment(index: 0, durationMs: 2_000)
        XCTAssertNil(segment.realTimeFactor)

        segment.apply(Self.transcript(segmentID: segment.id, text: "hi", transcriptionMs: 500))
        XCTAssertEqual(try XCTUnwrap(segment.realTimeFactor), 0.25, accuracy: 0.0001)
    }

    func testASegmentWithNaNConfidenceStillJSONEncodes() throws {
        var session = Self.session()
        var segment = AmbientSegmentRecord(
            id: "seg",
            sessionID: session.id,
            index: 0,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1),
            durationMs: 1_000,
            sampleRate: 16_000,
            peakConfidence: Float.nan
        )
        segment.apply(RAAmbientTranscript(
            id: "seg",
            sessionID: session.id,
            segmentID: "seg",
            segmentIndex: 0,
            text: "hello",
            confidence: Float.infinity,
            languageCode: "en",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1),
            audioDurationMs: 1_000,
            transcriptionMs: 50,
            modelID: "parakeet"
        ))
        session.upsert(segment)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertNoThrow(try encoder.encode(session))
        XCTAssertEqual(session.segments[0].peakConfidence, 0)
        XCTAssertNil(session.segments[0].transcriptConfidence)
    }

    func testIncompleteNotesReportZeroDuration() {
        var note = Self.session()
        note.endedAt = nil
        XCTAssertEqual(note.duration, 0)
        note.endedAt = note.startedAt.addingTimeInterval(125)
        XCTAssertEqual(note.duration, 125, accuracy: 0.001)
    }

    func testEmptyOrphanIsDetectedOnlyWhenNothingWasCaptured() {
        var orphan = Self.session()
        orphan.endedAt = nil
        XCTAssertTrue(orphan.isEmptyOrphan)

        orphan.summary = "Said something"
        XCTAssertFalse(orphan.isEmptyOrphan)
    }

    func testTitleFallsBackFromCustomToSummaryToDate() {
        var session = Self.session()
        XCTAssertFalse(session.title.isEmpty, "A note with nothing in it still needs a row title")

        session.summary = "Planned the release. Ana takes the beta."
        XCTAssertEqual(session.title, "Planned the release")

        session.customTitle = "Release sync"
        XCTAssertEqual(session.title, "Release sync", "A renamed note must keep its name")
    }

    // MARK: - Audio Expiry

    func testExpiryWindowsProduceTheExpectedCutoff() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            try XCTUnwrap(AmbientRetentionWindow.oneDay.expiryCutoff(from: now)),
            now.addingTimeInterval(-86_400)
        )
        XCTAssertEqual(
            try XCTUnwrap(AmbientRetentionWindow.thirtyDays.expiryCutoff(from: now)),
            now.addingTimeInterval(-30 * 86_400)
        )
    }

    func testRecordingsNeverExpireByDefault() {
        XCTAssertEqual(AmbientRetentionWindow.default, .keepUntilDeleted)
        XCTAssertNil(AmbientRetentionWindow.keepUntilDeleted.expiryCutoff(from: Date()))
    }

    /// The behavior that was silently wrong before: expiry used to delete whole
    /// notes, so a week-old note lost its text along with its audio.
    func testExpiringAudioKeepsEverythingElseAboutTheNote() async throws {
        let store = AmbientMemoryStore.shared
        var note = Self.session(id: "expiry-\(UUID().uuidString)")
        note.endedAt = Date(timeIntervalSince1970: 0)
        note.summary = "Planned the release."
        note.mergeActionItems(["Ship the beta"])
        note.upsert(Self.transcribedSegment(index: 0, text: "We should ship the beta."))
        note.audioRelativePath = "Audio/\(note.id).wav"
        await store.save(note)

        let expired = await store.expireAudio(olderThan: .oneDay, now: Date())

        XCTAssertTrue(expired.contains(note.id))
        let saved = await store.loadSession(id: note.id)
        let reloaded = try XCTUnwrap(saved, "Expiry must never delete the note")
        XCTAssertNil(reloaded.audioRelativePath)
        XCTAssertEqual(reloaded.summary, "Planned the release.")
        XCTAssertEqual(reloaded.actionItems.map(\.text), ["Ship the beta"])
        XCTAssertEqual(reloaded.fullTranscript, "We should ship the beta.")

        await store.delete(sessionID: note.id)
    }

    func testAudioIsKeptByDefaultForDogfooding() {
        XCTAssertEqual(AmbientRetentionPolicy.default, .retainAudio)
        XCTAssertTrue(AmbientRetentionPolicy.retainAudio.retainsAudio)
        XCTAssertFalse(AmbientRetentionPolicy.transcriptsOnly.retainsAudio)
    }

    // MARK: - Decoding Older Notes

    /// Notes written before summaries existed must still open. Losing a
    /// tester's history to a schema change is worse than a summary-less note.
    func testANoteWrittenBeforeSummariesStillDecodes() throws {
        let legacy = """
        {"id":"old","startedAt":"1970-01-01T00:00:00Z","profileID":"quality",\
        "vadModelID":"silero-vad","sttModelID":"parakeet","retentionPolicy":"retainAudio",\
        "context":{"environment":"","placement":"","note":""},"deviceModel":"iPhone",\
        "osVersion":"18.0","segments":[]}
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let note = try decoder.decode(AmbientSessionRecord.self, from: Data(legacy.utf8))

        XCTAssertEqual(note.id, "old")
        XCTAssertEqual(note.summary, "")
        XCTAssertTrue(note.actionItems.isEmpty)
        XCTAssertTrue(note.partialSummaries.isEmpty)
        XCTAssertFalse(note.summaryPending)
        XCTAssertNil(note.audioRelativePath)
    }

    // MARK: - Search

    func testSearchMatchesSummaryActionItemsAndTranscript() {
        var summarized = Self.session(id: "a")
        summarized.summary = "Planned the vet appointment."
        var withItem = Self.session(id: "b")
        withItem.mergeActionItems(["Book the flight"])
        var spoken = Self.session(id: "c")
        spoken.upsert(Self.transcribedSegment(index: 0, text: "Remember to buy oat milk on the way home."))

        let store = AmbientMemoryStore.shared
        let notes = [summarized, withItem, spoken]

        XCTAssertEqual(store.search("vet", in: notes).map(\.sessionID), ["a"])
        XCTAssertEqual(store.search("flight", in: notes).first?.kind, .actionItem)
        XCTAssertEqual(store.search("oat milk", in: notes).first?.kind, .transcript)
        XCTAssertTrue(store.search("   ", in: notes).isEmpty, "An empty query must not match everything")
    }

    // MARK: - Benchmark Sample

    func testSpeechRatioAndActionItemRateHandleEmptyRuns() {
        let empty = Self.benchmarkSample(sessionSeconds: 0, speechSeconds: 0, items: 0, completed: 0)
        XCTAssertEqual(empty.speechRatio, 0)
        XCTAssertEqual(empty.completedActionItemRate, 0)

        let real = Self.benchmarkSample(sessionSeconds: 600, speechSeconds: 150, items: 4, completed: 3)
        XCTAssertEqual(real.speechRatio, 0.25, accuracy: 0.0001)
        XCTAssertEqual(real.completedActionItemRate, 0.75, accuracy: 0.0001)
    }

    // MARK: - Session Phase

    func testOnlyLiveCapturePhasesCountAsRecording() {
        XCTAssertTrue(AmbientSessionPhase.listening.isRecording)
        XCTAssertTrue(AmbientSessionPhase.capturingSpeech.isRecording)
        XCTAssertTrue(AmbientSessionPhase.transcribing.isRecording)

        XCTAssertFalse(AmbientSessionPhase.preparing.isRecording)
        XCTAssertFalse(AmbientSessionPhase.paused.isRecording)
        XCTAssertFalse(AmbientSessionPhase.idle.isRecording)
    }

    /// The microphone is still ours while preparing, paused, or finishing, so
    /// dictation must not be able to slip in during those phases.
    func testPausedAndPreparingStillHoldTheMicrophone() {
        for phase in [
            AmbientSessionPhase.preparing,
            .listening,
            .capturingSpeech,
            .transcribing,
            .processing,
            .paused
        ] {
            XCTAssertTrue(phase.holdsAudioSession, "\(phase.rawValue) must block a second audio session")
        }

        for phase in [AmbientSessionPhase.idle, .stopped, .failed] {
            XCTAssertFalse(phase.holdsAudioSession, "\(phase.rawValue) must release the microphone")
        }
    }

    // MARK: - Fixtures

    private static func session(id: String = "session") -> AmbientSessionRecord {
        AmbientSessionRecord(
            id: id,
            startedAt: Date(timeIntervalSince1970: 0),
            profileID: "quality",
            vadModelID: "silero-vad",
            sttModelID: "parakeet",
            retentionPolicy: .retainAudio,
            context: .empty,
            deviceModel: "iPhone",
            osVersion: "26.0"
        )
    }

    private static func segment(index: Int, durationMs: Int = 1_000) -> AmbientSegmentRecord {
        AmbientSegmentRecord(from: RAAmbientSegment(
            id: "segment-\(index)",
            sessionID: "session",
            index: index,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: Double(durationMs) / 1000),
            durationMs: durationMs,
            sampleRate: 16_000,
            peakConfidence: 0.9,
            pcm16: nil
        ))
    }

    private static func transcribedSegment(index: Int, text: String) -> AmbientSegmentRecord {
        var stored = segment(index: index)
        stored.apply(transcript(segmentID: stored.id, text: text))
        return stored
    }

    private static func transcript(
        segmentID: String,
        text: String,
        transcriptionMs: Int = 100
    ) -> RAAmbientTranscript {
        RAAmbientTranscript(
            id: segmentID,
            sessionID: "session",
            segmentID: segmentID,
            segmentIndex: 0,
            text: text,
            confidence: 0.8,
            languageCode: "en",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1),
            audioDurationMs: 2_000,
            transcriptionMs: transcriptionMs,
            modelID: "parakeet"
        )
    }

    private static func benchmarkSample(
        sessionSeconds: Double,
        speechSeconds: Double,
        items: Int,
        completed: Int
    ) -> AmbientBenchmarkSample {
        AmbientBenchmarkSample(
            id: UUID(),
            recordedAt: Date(),
            sessionID: "session",
            profileID: "quality",
            deviceModel: "iPhone",
            chipName: "Apple Silicon",
            osVersion: "26.0",
            audioRoute: "MicrophoneBuiltIn",
            environment: "office",
            placement: "desk",
            sessionSeconds: sessionSeconds,
            speechSeconds: speechSeconds,
            segmentCount: 10,
            transcribedSegmentCount: 10,
            droppedSegmentCount: 0,
            actionItemCount: items,
            completedActionItemCount: completed,
            medianTranscriptionMs: 200,
            medianRealTimeFactor: 0.2,
            medianExtractionMs: 900,
            firstTranscriptLatencyMs: 1_500,
            peakMemoryBytes: 1_000,
            batteryDeltaPerHour: 12,
            thermalState: "nominal",
            interruptionCount: 0,
            retainedAudioBytes: 0
        )
    }
}
