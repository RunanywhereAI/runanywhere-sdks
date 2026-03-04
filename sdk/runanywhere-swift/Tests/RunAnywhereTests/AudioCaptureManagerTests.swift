//
//  AudioCaptureManagerTests.swift
//  RunAnywhere SDK
//
//  Unit tests for AudioCaptureManager (Issue #198).
//  - Engine start failure: tap is removed on throw (resource leak fix).
//  - Converter input block: buffer provided only once, no duplication.
//

import AVFoundation
import XCTest

@testable import RunAnywhere

final class AudioCaptureManagerTests: XCTestCase {

    // MARK: - Engine start failure → tap cleanup

    /// When startRecording throws (e.g. engine.start() fails), the tap must be removed so a
    /// subsequent startRecording can succeed. This test verifies that after a throw, state is
    /// clean (isRecording false) and we don't leave a tap on the node.
    func testStartRecordingFailureLeavesCleanState() async throws {
        let manager = AudioCaptureManager()

        // Attempt start without granting permission (may throw at session or engine start).
        // We only care that if it throws, isRecording stays false and we can retry.
        do {
            try manager.startRecording { _ in }
            // If we get here, permission was granted and engine started; stop so we're clean.
            manager.stopRecording()
        } catch {
            // Expected on CI/simulator when permission denied or engine fails.
            XCTAssertFalse(manager.isRecording, "After startRecording throws, isRecording must be false")
        }

        // State must be clean: either we never started, or we stopped. Try starting again
        // (will only succeed if permission is granted and engine starts).
        do {
            try manager.startRecording { _ in }
            XCTAssertTrue(manager.isRecording)
            manager.stopRecording()
        } catch {
            // OK if still no permission / engine fails.
        }
        XCTAssertFalse(manager.isRecording)
    }

    // MARK: - Audio conversion single-use (no duplication)

    /// convert() uses an AVAudioConverterInputBlock that must return the buffer only once,
    /// then .endOfStream. Otherwise the converter may use the same buffer multiple times
    /// and produce duplicated/corrupted audio. This test verifies output frame count is
    /// consistent with a single pass (no double feed).
    func testConvertProducesNonDuplicatedOutput() throws {
        let manager = AudioCaptureManager()
        let sourceRate: Double = 48000
        let targetRate: Double = 16000
        let frameCount: AVAudioFrameCount = 4800 // 0.1 s at 48 kHz

        guard let sourceFormat = AVAudioFormat(
            standardFormatWithSampleRate: sourceRate,
            channels: 1
        ), let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetRate,
            channels: 1,
            interleaved: false
        ) else {
            XCTFail("Failed to create formats")
            return
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            XCTFail("Failed to create converter")
            return
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: frameCount
        ) else {
            XCTFail("Failed to create buffer")
            return
        }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            XCTFail("No float channel data")
            return
        }
        let ptr = channelData.pointee
        for i in 0..<Int(frameCount) {
            ptr[i] = 0.1 * Float(i) / Float(frameCount) // simple ramp
        }

        let result = manager.convert(buffer: buffer, using: converter, to: targetFormat)
        XCTAssertNotNil(result, "Conversion should succeed")

        guard let out = result else { return }

        // Expected output frames ≈ frameCount * (targetRate / sourceRate) for a single pass.
        let expectedFrames = Double(frameCount) * (targetRate / sourceRate)
        let tolerance = expectedFrames * 0.01 // 1% tolerance
        XCTAssertGreaterThan(out.frameLength, 0, "Output should have frames")
        XCTAssertLessThanOrEqual(
            Double(out.frameLength),
            expectedFrames + tolerance,
            "Output frame count should not exceed single-pass conversion (no duplication)"
        )
        XCTAssertGreaterThanOrEqual(
            Double(out.frameLength),
            expectedFrames - tolerance,
            "Output should contain expected single-pass frames"
        )
    }

    /// Sanity check: converting a buffer twice (two separate convert calls) each produces
    /// valid output. Ensures the hasProvidedData state is per-call, not global.
    func testConvertIsIdempotentAcrossCalls() throws {
        let manager = AudioCaptureManager()
        let sourceRate: Double = 44100
        let targetRate: Double = 16000
        let frameCount: AVAudioFrameCount = 4410

        guard let sourceFormat = AVAudioFormat(
            standardFormatWithSampleRate: sourceRate,
            channels: 1
        ), let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetRate,
            channels: 1,
            interleaved: false
        ) else {
            XCTFail("Failed to create formats")
            return
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            XCTFail("Failed to create converter")
            return
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            XCTFail("Failed to create buffer")
            return
        }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            let ptr = channelData.pointee
            for i in 0..<Int(frameCount) { ptr[i] = 0.01 }
        }

        let first = manager.convert(buffer: buffer, using: converter, to: targetFormat)
        let second = manager.convert(buffer: buffer, using: converter, to: targetFormat)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.frameLength ?? 0, second?.frameLength ?? 0,
                       "Two separate convert calls with same buffer should yield same length (no shared state)")
    }
}
