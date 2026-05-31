//
//  RAAudioConvert.swift
//  RunAnywhere SDK
//
//  Public PCM conversion helpers for example apps and host integrations.
//  Mirrors the commons `rac_audio_pcm16_to_float32` inline routine so callers
//  feeding raw Int16 microphone PCM into `RunAnywhere.detectVoiceActivity(...)`
//  / `transcribe(...)` do not need to reimplement the divide-by-32768.0
//  normalisation, matching the canonical commons audio normalisation contract.
//

import Foundation

public extension RunAnywhere {

    /// Convert a buffer of Int16 PCM samples to Float32 samples in the range
    /// `[-1.0, 1.0]`. Matches commons `rac_audio_pcm16_to_float32` (divides
    /// each sample by `32768.0`).
    ///
    /// - Parameter int16Data: Raw Int16 PCM samples encoded as `Data`
    ///   (little-endian on every Apple platform; the bit pattern is preserved
    ///   verbatim).
    /// - Returns: `Data` holding IEEE-754 single-precision floats. The byte
    ///   layout matches what `RunAnywhere.detectVoiceActivity(_:)` and the
    ///   STT/VAD streaming APIs accept as input.
    static func pcm16ToFloat32(_ int16Data: Data) -> Data {
        let int16Count = int16Data.count / MemoryLayout<Int16>.size
        guard int16Count > 0 else { return Data() }
        var floats = [Float](repeating: 0, count: int16Count)
        int16Data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<int16Count {
                floats[i] = Float(int16Buffer[i]) / 32768.0
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Convenience overload that returns the normalised samples as a
    /// `[Float]` array when callers want to inspect samples directly without
    /// going through the SDK's `Data`-based audio surface.
    static func pcm16ToFloat32Samples(_ int16Data: Data) -> [Float] {
        let int16Count = int16Data.count / MemoryLayout<Int16>.size
        guard int16Count > 0 else { return [] }
        return int16Data.withUnsafeBytes { rawBuffer -> [Float] in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            return (0..<int16Count).map { Float(int16Buffer[$0]) / 32768.0 }
        }
    }
}
