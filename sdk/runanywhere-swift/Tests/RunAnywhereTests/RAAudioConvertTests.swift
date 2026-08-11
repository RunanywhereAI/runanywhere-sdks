//
//  RAAudioConvertTests.swift
//  RunAnywhere SDK
//
//  Characterization tests for the Swift thin wrappers over commons
//  `rac_audio_*` PCM / WAV / level helpers.
//

import CRACommons
import Foundation
import XCTest

@testable import RunAnywhere

final class RAAudioConvertTests: XCTestCase {

    func testPcm16ToFloat32MatchesCommonsScale() {
        let pcm: [Int16] = [0, Int16.max, Int16.min, 16384]
        let data = pcm.withUnsafeBufferPointer { Data(buffer: $0) }

        let floats = RunAnywhere.pcm16ToFloat32Samples(data)
        XCTAssertEqual(floats.count, 4)
        XCTAssertEqual(floats[0], 0, accuracy: 1e-7)
        XCTAssertEqual(floats[1], Float(Int16.max) / RAC_AUDIO_PCM16_SCALE, accuracy: 1e-7)
        XCTAssertEqual(floats[2], -1.0, accuracy: 1e-7)
        XCTAssertEqual(floats[3], 0.5, accuracy: 1e-7)

        let asData = RunAnywhere.pcm16ToFloat32(data)
        XCTAssertEqual(asData.count, floats.count * MemoryLayout<Float>.size)
        let roundTrip = asData.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
        XCTAssertEqual(roundTrip, floats)
    }

    func testFloat32ToPcm16RoundTripsNearFullScale() {
        let samples: [Float] = [0, 0.5, -1.0, Float(Int16.max) / RAC_AUDIO_PCM16_SCALE]
        let floatData = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        let pcmData = RunAnywhere.float32ToPcm16(floatData)
        XCTAssertEqual(pcmData.count, samples.count * MemoryLayout<Int16>.size)

        let pcm = pcmData.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(pcm[0], 0)
        XCTAssertEqual(pcm[1], 16384)
        XCTAssertEqual(pcm[2], Int16.min)
        XCTAssertEqual(pcm[3], Int16.max)
    }

    func testPcm16ToWavUsesCommonsHeader() {
        let pcm = Data(repeating: 0, count: 320) // 160 mono Int16 frames
        let wav = RunAnywhere.pcm16ToWav(pcm, sampleRate: 16_000)

        XCTAssertEqual(wav.count, Int(rac_audio_wav_header_size()) + pcm.count)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(wav.subdata(in: Int(rac_audio_wav_header_size())..<wav.count), pcm)
    }

    func testPcm16ToWavEmptyOrInvalidReturnsEmpty() {
        XCTAssertTrue(RunAnywhere.pcm16ToWav(Data(), sampleRate: 16_000).isEmpty)
        XCTAssertTrue(RunAnywhere.pcm16ToWav(Data([0, 1]), sampleRate: 0).isEmpty)
    }

    func testComputeLevelNormalizedMatchesCaptureMeterContract() {
        // Silence → 0. Full-scale sine-ish peak → near 1 after −60 dB floor.
        let silence = [Float](repeating: 0, count: 256)
        var silenceLevel: Float = -1
        XCTAssertEqual(
            rac_audio_compute_level_normalized(
                silence, silence.count, RAC_AUDIO_LEVEL_FLOOR_DB, &silenceLevel
            ),
            RAC_SUCCESS
        )
        XCTAssertEqual(silenceLevel, 0, accuracy: 1e-6)

        let peak = [Float](repeating: 1.0, count: 256)
        var peakLevel: Float = -1
        XCTAssertEqual(
            rac_audio_compute_level_normalized(
                peak, peak.count, RAC_AUDIO_LEVEL_FLOOR_DB, &peakLevel
            ),
            RAC_SUCCESS
        )
        XCTAssertEqual(peakLevel, 1.0, accuracy: 1e-6)
    }
}
