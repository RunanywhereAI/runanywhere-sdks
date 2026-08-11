//
//  RAAudioConvert.swift
//  RunAnywhere SDK
//
//  Public PCM conversion helpers for example apps and host integrations.
//  Thin wrappers over commons `rac_audio_*` so callers feeding raw Int16
//  microphone PCM into `RunAnywhere.detectVoiceActivity(...)` /
//  `transcribe(...)` do not reimplement PCM16↔float32 or RIFF/WAV math.
//

import CRACommons
import Foundation

public extension RunAnywhere {

    /// Convert a buffer of Int16 PCM samples to Float32 samples in the range
    /// `[-1.0, 1.0]` via commons `rac_audio_pcm16_to_float32` (divides each
    /// sample by `RAC_AUDIO_PCM16_SCALE` / 32768.0).
    ///
    /// - Parameter int16Data: Raw Int16 PCM samples encoded as `Data`
    ///   (little-endian on every Apple platform; the bit pattern is preserved
    ///   verbatim).
    /// - Returns: `Data` holding IEEE-754 single-precision floats. The byte
    ///   layout matches what `RunAnywhere.detectVoiceActivity(_:)` and the
    ///   STT/VAD streaming APIs accept as input.
    static func pcm16ToFloat32(_ int16Data: Data) -> Data {
        let samples = pcm16ToFloat32Samples(int16Data)
        guard !samples.isEmpty else { return Data() }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Convenience overload that returns the normalised samples as a
    /// `[Float]` array when callers want to inspect samples directly without
    /// going through the SDK's `Data`-based audio surface.
    static func pcm16ToFloat32Samples(_ int16Data: Data) -> [Float] {
        let int16Count = int16Data.count / MemoryLayout<Int16>.size
        guard int16Count > 0 else { return [] }

        var floats = [Float](repeating: 0, count: int16Count)
        let rc = int16Data.withUnsafeBytes { rawBuffer -> rac_result_t in
            guard let int16Base = rawBuffer.bindMemory(to: Int16.self).baseAddress else {
                return RAC_ERROR_NULL_POINTER
            }
            return floats.withUnsafeMutableBufferPointer { outBuffer in
                rac_audio_pcm16_to_float32(int16Base, int16Count, outBuffer.baseAddress)
            }
        }
        guard rc == RAC_SUCCESS else { return [] }
        return floats
    }

    /// Quantize Float32 samples in `[-1.0, 1.0]` to Int16 PCM via commons
    /// `rac_audio_float32_to_pcm16`.
    ///
    /// - Parameter float32Data: IEEE-754 single-precision samples as `Data`.
    /// - Returns: Raw little-endian Int16 PCM bytes, or empty `Data` when the
    ///   input is empty / not a whole number of floats.
    static func float32ToPcm16(_ float32Data: Data) -> Data {
        let floatCount = float32Data.count / MemoryLayout<Float>.size
        guard floatCount > 0 else { return Data() }

        var pcm = [Int16](repeating: 0, count: floatCount)
        let rc = float32Data.withUnsafeBytes { rawBuffer -> rac_result_t in
            guard let floatBase = rawBuffer.bindMemory(to: Float.self).baseAddress else {
                return RAC_ERROR_NULL_POINTER
            }
            return pcm.withUnsafeMutableBufferPointer { outBuffer in
                rac_audio_float32_to_pcm16(floatBase, floatCount, outBuffer.baseAddress)
            }
        }
        guard rc == RAC_SUCCESS else { return Data() }
        return pcm.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Wrap raw 16-bit mono PCM samples in a canonical WAV (RIFF) container
    /// via commons `rac_audio_int16_to_wav`. Matches Kotlin / Web
    /// `pcm16ToWav` helpers.
    ///
    /// Use this when a consumer needs a self-describing audio container
    /// rather than headerless PCM — e.g. cloud STT providers that upload the
    /// bytes as an `audio/wav` file part.
    ///
    /// - Parameters:
    ///   - int16Data: Raw Int16 mono PCM samples encoded as `Data`
    ///     (little-endian).
    ///   - sampleRate: Capture sample rate in Hz (e.g. 16000).
    /// - Returns: WAV bytes owned by the caller, or empty `Data` when the
    ///   input is empty or commons rejects the arguments.
    static func pcm16ToWav(_ int16Data: Data, sampleRate: Int) -> Data {
        guard !int16Data.isEmpty, sampleRate > 0 else { return Data() }

        var wavDataPtr: UnsafeMutableRawPointer?
        var wavSize = 0
        let result = int16Data.withUnsafeBytes { pcmPtr in
            rac_audio_int16_to_wav(
                pcmPtr.baseAddress,
                int16Data.count,
                Int32(sampleRate),
                &wavDataPtr,
                &wavSize
            )
        }

        guard result == RAC_SUCCESS, let ptr = wavDataPtr, wavSize > 0 else {
            return Data()
        }
        defer { rac_free(ptr) }
        return Data(bytes: ptr, count: wavSize)
    }
}
