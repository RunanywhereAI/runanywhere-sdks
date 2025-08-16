import Foundation
import Accelerate

/// Simple energy-based voice activity detector
public class SimpleVAD: VoiceActivityDetector {
    /// Sensitivity level for detection
    public var sensitivity: VADSensitivity = .medium

    /// Energy threshold for voice detection
    public var energyThreshold: Float = 0.05

    /// Minimum speech duration in seconds
    public var minSpeechDuration: TimeInterval = 0.3

    /// Maximum silence duration in seconds
    public var maxSilenceDuration: TimeInterval = 1.5

    /// Sample rate for audio processing
    private let sampleRate: Int = 16000

    /// Frame size in samples
    private let frameSize: Int = 512

    /// History of energy levels for smoothing
    private var energyHistory: [Float] = []
    private let historySize: Int = 10

    /// Current speech state
    private var isSpeaking: Bool = false
    private var speechStartTime: TimeInterval?
    private var silenceStartTime: TimeInterval?

    public init(sensitivity: VADSensitivity = .medium) {
        self.sensitivity = sensitivity
        // Apply sensitivity to threshold
        self.energyThreshold = sensitivity.threshold
        print("🔧 VAD Initialized: sensitivity=\(sensitivity), threshold=\(energyThreshold)")
    }

    /// Detect voice activity in audio data
    public func detectActivity(in audio: Data) -> VADResult {
        let samples = convertDataToFloatArray(audio)
        let segments = detectSpeechSegments(in: samples)

        let hasSpeech = !segments.isEmpty
        let totalDuration = Double(samples.count) / Double(sampleRate)
        let speechDuration = segments.reduce(0) { $0 + ($1.endTime - $1.startTime) }
        let silenceRatio = Float(1.0 - (speechDuration / totalDuration))

        let energy = calculateEnergy(samples)
        let zcr = calculateZeroCrossingRate(samples)

        return VADResult(
            hasSpeech: hasSpeech,
            speechSegments: segments,
            silenceRatio: silenceRatio,
            energyLevel: energy,
            zeroCrossingRate: zcr
        )
    }

    /// Detect activity in streaming audio
    public func detectActivityStream(
        audioStream: AsyncStream<VoiceAudioChunk>
    ) -> AsyncStream<VADSegment> {
        AsyncStream { continuation in
            Task {
                for await chunk in audioStream {
                    let samples = chunk.samples
                    let energy = calculateEnergy(samples)

                    // Update energy history
                    energyHistory.append(energy)
                    if energyHistory.count > historySize {
                        energyHistory.removeFirst()
                    }

                    // Smooth energy using moving average
                    let smoothedEnergy = energyHistory.reduce(0, +) / Float(energyHistory.count)

                    // Detect speech state changes
                    let wasSpeeking = isSpeaking
                    isSpeaking = smoothedEnergy > energyThreshold

                    var isStartOfSpeech = false
                    var isEndOfSpeech = false

                    if !wasSpeeking && isSpeaking {
                        // Speech started
                        speechStartTime = chunk.timestamp
                        silenceStartTime = nil
                        isStartOfSpeech = true
                    } else if wasSpeeking && !isSpeaking {
                        // Speech might have ended
                        if silenceStartTime == nil {
                            silenceStartTime = chunk.timestamp
                        } else if let silenceStart = silenceStartTime {
                            let silenceDuration = chunk.timestamp - silenceStart
                            if silenceDuration > maxSilenceDuration {
                                // Confirmed end of speech
                                isEndOfSpeech = true
                                silenceStartTime = nil
                                speechStartTime = nil
                            }
                        }
                    } else if isSpeaking {
                        // Still speaking, reset silence timer
                        silenceStartTime = nil
                    }

                    let segment = VADSegment(
                        isSpeech: isSpeaking,
                        timestamp: chunk.timestamp,
                        energy: smoothedEnergy,
                        isStartOfSpeech: isStartOfSpeech,
                        isEndOfSpeech: isEndOfSpeech
                    )

                    continuation.yield(segment)

                    if chunk.isFinal {
                        continuation.finish()
                        break
                    }
                }
            }
        }
    }

    // MARK: - Simple detection for Data (used by VoiceSessionManager)

    /// Simple detection method that just checks energy level
    public func detectActivity(_ audioData: Data) -> Bool {
        let samples = audioData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        guard !samples.isEmpty else { return false }

        // Calculate RMS energy
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))

        // Debug: Find max amplitude for comparison
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0.0

        // Log detailed energy info occasionally
        if Int.random(in: 1...100) == 1 {  // Random 1% chance for more frequent debugging
            print("🔍 VAD Debug: RMS=\(String(format: "%.6f", rms)), Max=\(String(format: "%.6f", maxAmplitude)), Threshold=\(String(format: "%.6f", energyThreshold)), Result=\(rms > energyThreshold ? "SPEECH" : "SILENCE")")
        }

        return rms > energyThreshold
    }

    // MARK: - Private Methods

    /// Convert Data to float array
    private func convertDataToFloatArray(_ data: Data) -> [Float] {
        // Data is already Float32 from AudioCapture (16kHz, mono, Float32)
        let floatArray = data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        return floatArray
    }

    /// Calculate energy of audio samples
    private func calculateEnergy(_ samples: [Float]) -> Float {
        var energy: Float = 0
        vDSP_measqv(samples, 1, &energy, vDSP_Length(samples.count))
        // Convert mean-square to RMS for better threshold matching
        return sqrt(energy)
    }

    /// Calculate zero crossing rate
    private func calculateZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }

        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i-1] >= 0 && samples[i] < 0) || (samples[i-1] < 0 && samples[i] >= 0) {
                crossings += 1
            }
        }

        return Float(crossings) / Float(samples.count - 1)
    }

    /// Detect speech segments in samples
    private func detectSpeechSegments(in samples: [Float]) -> [SpeechSegment] {
        var segments: [SpeechSegment] = []
        let framesPerSecond = sampleRate / frameSize

        var inSpeech = false
        var speechStart = 0

        for i in stride(from: 0, to: samples.count - frameSize, by: frameSize) {
            let frame = Array(samples[i..<i+frameSize])
            let energy = calculateEnergy(frame)

            if !inSpeech && energy > energyThreshold {
                // Speech started
                inSpeech = true
                speechStart = i
            } else if inSpeech && energy < energyThreshold {
                // Speech ended
                inSpeech = false
                let startTime = Double(speechStart) / Double(sampleRate)
                let endTime = Double(i) / Double(sampleRate)

                // Only add segment if it's long enough
                if endTime - startTime >= minSpeechDuration {
                    segments.append(SpeechSegment(
                        startTime: startTime,
                        endTime: endTime,
                        averageEnergy: energy,
                        confidence: min(1.0, energy / (energyThreshold * 2))
                    ))
                }
            }
        }

        // Handle case where speech continues to end
        if inSpeech {
            let startTime = Double(speechStart) / Double(sampleRate)
            let endTime = Double(samples.count) / Double(sampleRate)

            if endTime - startTime >= minSpeechDuration {
                segments.append(SpeechSegment(
                    startTime: startTime,
                    endTime: endTime,
                    averageEnergy: energyThreshold,
                    confidence: 0.8
                ))
            }
        }

        return segments
    }
}
