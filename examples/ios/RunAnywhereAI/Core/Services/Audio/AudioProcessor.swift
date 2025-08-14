import Foundation
import AVFoundation
import Accelerate

/// Audio processor for preprocessing audio data for transcription
public class AudioProcessor {

    /// Target sample rate for processing (16kHz for Whisper)
    public static let targetSampleRate: Double = 16000.0

    /// Process audio buffer for transcription
    /// - Parameters:
    ///   - buffer: AVAudioPCMBuffer to process
    ///   - targetSampleRate: Target sample rate (default 16kHz)
    /// - Returns: Processed audio data
    public static func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        targetSampleRate: Double = targetSampleRate
    ) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        // Convert to mono if stereo
        var monoSamples: [Float]
        if channelCount == 2 {
            monoSamples = [Float](repeating: 0, count: frameLength)
            // Mix stereo to mono
            for i in 0..<frameLength {
                monoSamples[i] = (channelData[0][i] + channelData[1][i]) / 2.0
            }
        } else {
            // Already mono
            monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        // Resample if needed
        let inputSampleRate = buffer.format.sampleRate
        if inputSampleRate != targetSampleRate {
            monoSamples = resample(
                samples: monoSamples,
                fromRate: inputSampleRate,
                toRate: targetSampleRate
            )
        }

        // Normalize audio
        monoSamples = normalize(monoSamples)

        // Convert to Data
        return floatArrayToData(monoSamples)
    }

    /// Resample audio from one sample rate to another
    /// - Parameters:
    ///   - samples: Input samples
    ///   - fromRate: Source sample rate
    ///   - toRate: Target sample rate
    /// - Returns: Resampled audio samples
    public static func resample(
        samples: [Float],
        fromRate: Double,
        toRate: Double
    ) -> [Float] {
        guard fromRate != toRate else { return samples }

        let ratio = toRate / fromRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        // Simple linear interpolation resampling
        for i in 0..<outputLength {
            let sourceIndex = Double(i) / ratio
            let lowerIndex = Int(sourceIndex)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourceIndex - Double(lowerIndex))

            if lowerIndex < samples.count {
                let lowerValue = samples[lowerIndex]
                let upperValue = samples[upperIndex]
                output[i] = lowerValue + (upperValue - lowerValue) * fraction
            }
        }

        return output
    }

    /// Normalize audio samples to [-1, 1] range
    /// - Parameter samples: Input samples
    /// - Returns: Normalized samples
    public static func normalize(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var maxValue: Float = 0
        vDSP_maxmgv(samples, 1, &maxValue, vDSP_Length(samples.count))

        guard maxValue > 0 else { return samples }

        var normalizedSamples = samples
        var scale = Float(0.95) / maxValue // Scale to 95% to avoid clipping
        vDSP_vsmul(normalizedSamples, 1, &scale, &normalizedSamples, 1, vDSP_Length(samples.count))

        return normalizedSamples
    }

    /// Apply pre-emphasis filter to audio
    /// - Parameters:
    ///   - samples: Input samples
    ///   - coefficient: Pre-emphasis coefficient (default 0.97)
    /// - Returns: Filtered samples
    public static func applyPreEmphasis(
        _ samples: [Float],
        coefficient: Float = 0.97
    ) -> [Float] {
        guard samples.count > 1 else { return samples }

        var filtered = [Float](repeating: 0, count: samples.count)
        filtered[0] = samples[0]

        for i in 1..<samples.count {
            filtered[i] = samples[i] - coefficient * samples[i - 1]
        }

        return filtered
    }

    /// Remove DC offset from audio
    /// - Parameter samples: Input samples
    /// - Returns: DC-removed samples
    public static func removeDCOffset(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))

        var output = samples
        var negativeMean = -mean
        vDSP_vsadd(output, 1, &negativeMean, &output, 1, vDSP_Length(samples.count))

        return output
    }

    /// Apply noise gate to audio
    /// - Parameters:
    ///   - samples: Input samples
    ///   - threshold: Gate threshold (default 0.01)
    /// - Returns: Gated samples
    public static func applyNoiseGate(
        _ samples: [Float],
        threshold: Float = 0.01
    ) -> [Float] {
        return samples.map { abs($0) < threshold ? 0 : $0 }
    }

    /// Convert float array to Data
    /// - Parameter samples: Float samples
    /// - Returns: Data representation
    public static func floatArrayToData(_ samples: [Float]) -> Data {
        // Convert to Int16 for compact representation
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        return int16Samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Convert Data to float array
    /// - Parameter data: Audio data
    /// - Returns: Float samples
    public static func dataToFloatArray(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Int16>.size
        var samples = [Float](repeating: 0, count: count)

        data.withUnsafeBytes { buffer in
            guard let int16Pointer: UnsafePointer<Int16> = buffer.bindMemory(to: Int16.self).baseAddress else { return }

            for i in 0..<count {
                samples[i] = Float(int16Pointer[i]) / Float(Int16.max)
            }
        }

        return samples
    }

    /// Calculate RMS (Root Mean Square) of audio
    /// - Parameter samples: Input samples
    /// - Returns: RMS value
    public static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        return rms
    }

    /// Apply band-pass filter for voice frequencies
    /// - Parameters:
    ///   - samples: Input samples
    ///   - sampleRate: Sample rate
    ///   - lowFreq: Low cutoff frequency (default 80Hz)
    ///   - highFreq: High cutoff frequency (default 8000Hz)
    /// - Returns: Filtered samples
    public static func applyBandPassFilter(
        _ samples: [Float],
        sampleRate: Double,
        lowFreq: Double = 80.0,
        highFreq: Double = 8000.0
    ) -> [Float] {
        // Simple high-pass filter to remove low frequencies
        var filtered = samples
        let rcLow = 1.0 / (2.0 * .pi * lowFreq)
        let dtLow = 1.0 / sampleRate
        let alphaLow = Float(dtLow / (rcLow + dtLow))

        for i in 1..<filtered.count {
            filtered[i] = alphaLow * (filtered[i] - filtered[i-1]) + alphaLow * filtered[i-1]
        }

        // Simple low-pass filter to remove high frequencies
        let rcHigh = 1.0 / (2.0 * .pi * highFreq)
        let dtHigh = 1.0 / sampleRate
        let alphaHigh = Float(dtHigh / (rcHigh + dtHigh))

        for i in 1..<filtered.count {
            filtered[i] = alphaHigh * filtered[i] + (1.0 - alphaHigh) * filtered[i-1]
        }

        return filtered
    }

    /// Prepare audio for WhisperKit processing
    /// - Parameter buffer: Input audio buffer
    /// - Returns: Processed audio data ready for transcription
    public static func prepareForWhisperKit(_ buffer: AVAudioPCMBuffer) -> Data? {
        // Process buffer to 16kHz mono
        guard var processedData = processBuffer(buffer, targetSampleRate: 16000) else {
            return nil
        }

        // Convert to float array for additional processing
        var samples = dataToFloatArray(processedData)

        // Apply preprocessing pipeline
        samples = removeDCOffset(samples)
        samples = applyPreEmphasis(samples, coefficient: 0.97)
        samples = normalize(samples)

        // Convert back to data
        return floatArrayToData(samples)
    }
}
