//
//  AmbientModelProfileTests.swift
//  RunAnywhereAIUnitTests
//
//  Device-aware profile routing. The resolver is pure, so these cover the
//  decisions that would otherwise only show up on a hot phone: degrading to a
//  smaller stack, refusing a profile the catalog cannot satisfy, and never
//  proposing a stack that cannot actually start capture.
//

import Foundation
import RunAnywhere
import XCTest
@testable import RunAnywhereAI

final class AmbientModelProfileTests: XCTestCase {

    private let resolver = AmbientModelProfileResolver()

    // MARK: - Resolution

    func testResolveKeepsTheFirstCandidatePresentInTheCatalog() {
        let selection = resolver.resolve(
            profile: .quality,
            available: Self.models([
                "silero-vad",
                "sherpa-onnx-whisper-tiny.en",
                "sherpa-nemo-parakeet-tdt-0.6b-v3-int8",
                "lfm2-350m-q4_k_m",
                "qwen3-1.7b-q4_k_m",
            ])
        )

        XCTAssertEqual(selection.asrModelID, "sherpa-nemo-parakeet-tdt-0.6b-v3-int8")
        XCTAssertNil(selection.digestModelID, "Digester must stay unset until the user picks one")
        XCTAssertTrue(selection.canStartCapture)
        XCTAssertFalse(selection.supportsDigest)
    }

    func testSuggestedDigestIsNotAppliedToSelection() {
        let models = Self.models([
            "silero-vad",
            "sherpa-nemo-parakeet-tdt-0.6b-v3-int8",
            "lfm2-350m-q4_k_m",
        ])
        XCTAssertEqual(
            resolver.suggestedDigestID(for: .quality, available: models),
            "lfm2-350m-q4_k_m"
        )
        XCTAssertNil(resolver.resolve(profile: .quality, available: models).digestModelID)
        XCTAssertEqual(
            AmbientModelProfile.highEnd.digestCandidateIDs.first,
            "nemotron-mini-4b-instruct-ane"
        )
    }

    func testStreamingDiarizationRequiresHeadroomAndHighEnd() {
        var settings = AmbientCapturePerformanceSettings()
        settings.streamDiarDuringCapture = true
        XCTAssertFalse(settings.canStreamDiarization(
            availableMemoryBytes: 500_000_000,
            tier: .highEnd
        ))
        XCTAssertFalse(settings.canStreamDiarization(
            availableMemoryBytes: 3_000_000_000,
            tier: .midRange
        ))
        XCTAssertTrue(settings.canStreamDiarization(
            availableMemoryBytes: 3_000_000_000,
            tier: .highEnd
        ))
    }

    func testResolveFallsBackWhenThePreferredASRIsMissing() {
        let selection = resolver.resolve(
            profile: .quality,
            available: Self.models(["silero-vad", "sherpa-onnx-whisper-tiny.en"])
        )

        XCTAssertEqual(selection.asrModelID, "sherpa-onnx-whisper-tiny.en")
        XCTAssertNil(selection.digestModelID)
        XCTAssertTrue(selection.canStartCapture, "Capture only needs a detector and a transcriber")
        XCTAssertFalse(selection.supportsDigest)
    }

    func testCaptureIsBlockedWithoutADetector() {
        let selection = resolver.resolve(
            profile: .quality,
            available: Self.models(["sherpa-onnx-whisper-tiny.en"])
        )

        XCTAssertTrue(selection.vadModelID.isEmpty)
        XCTAssertFalse(selection.canStartCapture)
    }

    // MARK: - Background Safety

    /// Dogfooding allows GPU ASR so limits can be tested. The resolver still
    /// flags `isASRBackgroundSafe` so the UI can soft-warn without blocking.
    func testAnMLXASRIsAcceptedButFlaggedAsNotBackgroundSafe() {
        let selection = resolver.resolve(
            profile: .quality,
            available: Self.models(["silero-vad"])
                + Self.models(
                    ["sherpa-nemo-parakeet-tdt-0.6b-v3-int8", "sherpa-onnx-whisper-tiny.en"],
                    framework: .mlx
                )
        )

        XCTAssertEqual(selection.asrModelID, "sherpa-nemo-parakeet-tdt-0.6b-v3-int8")
        XCTAssertFalse(selection.isASRBackgroundSafe)
        XCTAssertTrue(selection.canStartCapture)
    }

    /// Digester is opt-in; resolving a profile must not force a GPU (or any)
    /// summarizer into the selection.
    func testResolveNeverAutoSelectsADigestModel() {
        let selection = resolver.resolve(
            profile: .compatibility,
            available: Self.models(["silero-vad", "sherpa-onnx-whisper-tiny.en"])
                + Self.models(["qwen3-0.6b-q4_k_m", "mlx-qwen3-0.6b-4bit"], framework: .mlx)
        )

        XCTAssertNil(selection.digestModelID)
        XCTAssertTrue(selection.canStartCapture, "Missing digester must not block recording")
    }

    func testIsBackgroundSafeIsFalseForMetalBackendsAndTrueForSherpa() {
        XCTAssertFalse(RAInferenceFramework.mlx.isBackgroundSafe)
        XCTAssertFalse(RAInferenceFramework.llamaCpp.isBackgroundSafe, "llama.cpp uses ggml-metal here")
        XCTAssertTrue(RAInferenceFramework.sherpa.isBackgroundSafe)
    }

    // MARK: - Recommendation

    func testAHealthyHighEndDeviceGetsTheBestViableProfile() {
        let profile = resolver.recommendedProfile(
            for: Self.conditions(tier: .highEnd, availableMemoryBytes: 6_000_000_000),
            available: Self.fullCatalog
        )

        XCTAssertEqual(profile.id, AmbientModelProfile.highEnd.id)
    }

    func testThermalPressureStepsDownToTheLightestViableProfile() {
        let profile = resolver.recommendedProfile(
            for: Self.conditions(
                tier: .highEnd,
                availableMemoryBytes: 6_000_000_000,
                thermalState: .serious
            ),
            available: Self.fullCatalog
        )

        XCTAssertEqual(profile.id, AmbientModelProfile.compatibility.id)
    }

    func testLowPowerModeAlsoStepsDown() {
        let profile = resolver.recommendedProfile(
            for: Self.conditions(
                tier: .highEnd,
                availableMemoryBytes: 6_000_000_000,
                isLowPowerModeEnabled: true
            ),
            available: Self.fullCatalog
        )

        XCTAssertEqual(profile.id, AmbientModelProfile.compatibility.id)
    }

    func testAProfileIsRejectedWhenItCannotFitInAvailableMemory() {
        let profile = resolver.recommendedProfile(
            for: Self.conditions(tier: .highEnd, availableMemoryBytes: 1_500_000_000),
            available: Self.fullCatalog
        )

        XCTAssertEqual(profile.id, AmbientModelProfile.compatibility.id)
    }

    func testAnEmptyCatalogStillReturnsAProfileRatherThanFailing() {
        let profile = resolver.recommendedProfile(
            for: Self.conditions(tier: .highEnd, availableMemoryBytes: 6_000_000_000),
            available: []
        )

        XCTAssertEqual(profile.id, AmbientModelProfile.compatibility.id)
        XCTAssertFalse(
            resolver.resolve(profile: profile, available: []).canStartCapture,
            "The UI must still be told capture is impossible"
        )
    }

    // MARK: - Conditions

    func testSummarizingIsSuspendedUnderPressureButCaptureContinues() {
        let hot = Self.conditions(tier: .highEnd, availableMemoryBytes: 0, thermalState: .serious)
        XCTAssertTrue(hot.shouldSuspendDerivedWork)
        XCTAssertFalse(hot.shouldStopCapture)

        let critical = Self.conditions(tier: .highEnd, availableMemoryBytes: 0, thermalState: .critical)
        XCTAssertTrue(critical.shouldStopCapture)
    }

    // MARK: - Fixtures

    private static let fullCatalog: [RAModelInfo] = models([
        "silero-vad",
        "sherpa-onnx-whisper-tiny.en",
        "sherpa-nemo-parakeet-tdt-0.6b-v3-int8",
        "lfm2-350m-q4_k_m",
        "qwen3-0.6b-q4_k_m",
        "qwen3-1.7b-q4_k_m",
        "qwen3-4b-q4_k_m",
    ])

    private static func models(
        _ ids: [String],
        framework: RAInferenceFramework = .sherpa
    ) -> [RAModelInfo] {
        ids.map { id in
            var model = RAModelInfo()
            model.id = id
            model.name = id
            model.framework = framework
            return model
        }
    }

    private static func conditions(
        tier: HardwareTier,
        availableMemoryBytes: Int64,
        thermalState: ProcessInfo.ThermalState = .nominal,
        isLowPowerModeEnabled: Bool = false
    ) -> AmbientDeviceConditions {
        AmbientDeviceConditions(
            tier: tier,
            availableMemoryBytes: availableMemoryBytes,
            thermalState: thermalState,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            batteryLevel: 0.8
        )
    }
}
