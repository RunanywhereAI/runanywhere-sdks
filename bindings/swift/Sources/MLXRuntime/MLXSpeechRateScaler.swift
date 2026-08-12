//
//  MLXSpeechRateScaler.swift
//  MLXRuntime Module
//
//  Applies TTSOptions.speed to MLX-synthesized speech.
//

import Accelerate
import Foundation

/// Stretches or compresses synthesized speech along the time axis only, so a
/// requested rate changes tempo without moving pitch.
///
/// `TTSOptions.speed` reaches every engine as `rac_tts_options_t.rate`, and the
/// engines that own a duration model apply it during synthesis — sherpa hands
/// it straight to Piper as `speed_rate`. The MLX speech models cannot: Soprano
/// is an autoregressive LLM whose `generateStream` takes only sampling
/// parameters (`GenerateParameters`, i.e. temperature/topP/penalties), so a
/// 0.5x request and a 2.0x request emit the same audio tokens at the same
/// tempo. The rate was accepted by the UI, validated, carried the whole way
/// down the C ABI, and then dropped — a labelled control that did nothing.
///
/// Rather than let the control lie, the runtime applies the rate to the samples
/// the model produced. This is WSOLA (waveform-similarity overlap-add): frames
/// are re-spaced by the requested factor, and before each one is overlap-added
/// it is slid within a short search window to the position that best continues
/// the previous frame's waveform. Keeping successive frames phase-aligned is
/// what preserves periodicity, and with it pitch and timbre. A plain linear
/// resample would have been ten lines but would have dragged the formants along
/// with the tempo — that is the chipmunk artifact, not a speed control.
///
/// The scaler is stateful so a chunked synthesis stream can be scaled without a
/// seam at every chunk boundary: `consume(_:)` takes whatever it can and keeps
/// the remainder, `finish()` releases the trailing partial frame.
struct MLXSpeechRateScaler {
    /// 32 ms analysis frames at 50% overlap — long enough to span a full pitch
    /// period for any adult voice, short enough that a phoneme boundary is not
    /// smeared across the overlap.
    private static let frameSeconds: Float = 0.032

    /// The similarity search has to be able to slide a whole pitch period for
    /// the alignment to mean anything; 10 ms covers a 100 Hz fundamental, below
    /// the bottom of an adult speaking range.
    private static let searchSeconds: Float = 0.010

    /// Below this the stretch is inaudible and a WSOLA pass would only
    /// contribute its own artifacts, so the samples are handed back untouched.
    private static let audibleRateDelta: Float = 0.01

    /// `TTSOptions.speed` is validated to 0.5...2.0 before it leaves Swift, but
    /// this type also sees whatever an engine-level default carries. Clamping
    /// keeps a zero or a NaN from producing a zero-length analysis hop.
    private static let rateBounds: ClosedRange<Float> = 0.25...4.0

    private let frameLength: Int
    private let hop: Int
    private let analysisHop: Float
    private let searchRadius: Int
    private let window: [Float]
    private let passthrough: Bool

    /// Sliding view of the input stream. `pendingOrigin` is the absolute index
    /// of `pending[0]`, so frame positions stay in one coordinate space even as
    /// consumed samples are dropped off the front.
    private var pending: [Float] = []
    private var pendingOrigin = 0
    /// Real samples received. Silence appended by `finish()` is counted in
    /// `availableCount` only, so a padded frame is never mistaken for audio.
    private var realCount = 0
    private var availableCount = 0
    private var frameIndex = 0
    /// The fading-out second half of the last emitted frame, waiting to be
    /// overlap-added with the first half of the next one.
    private var tail: [Float]
    /// The samples that would have followed the previous frame had nothing been
    /// re-spaced — the reference the next frame is aligned against.
    private var natural: [Float] = []

    init(rate: Float, sampleRate: Int) {
        let requested = rate.isFinite ? min(max(rate, Self.rateBounds.lowerBound), Self.rateBounds.upperBound) : 1.0
        passthrough = sampleRate <= 0 || abs(requested - 1.0) < Self.audibleRateDelta

        var length = Int((Float(sampleRate) * Self.frameSeconds).rounded())
        length = max(64, length - (length % 2))
        frameLength = length
        hop = length / 2
        analysisHop = Float(length / 2) * requested
        searchRadius = max(1, Int((Float(sampleRate) * Self.searchSeconds).rounded()))
        // Periodic Hann: at a half-frame hop two adjacent windows sum to exactly
        // 1, so the overlap-add needs no normalization pass.
        window = (0..<length).map { 0.5 * (1.0 - cos(2.0 * Float.pi * Float($0) / Float(length))) }
        tail = [Float](repeating: 0, count: length / 2)
    }

    /// Scale a complete buffer in one call.
    static func scaled(_ samples: [Float], rate: Float, sampleRate: Int) -> [Float] {
        var scaler = MLXSpeechRateScaler(rate: rate, sampleRate: sampleRate)
        guard !scaler.passthrough else { return samples }
        var output = scaler.consume(samples)
        output.append(contentsOf: scaler.finish())
        return output
    }

    /// Feed the next chunk and take back whatever is fully resolved.
    mutating func consume(_ samples: [Float]) -> [Float] {
        guard !passthrough else { return samples }
        guard !samples.isEmpty else { return [] }
        pending.append(contentsOf: samples)
        realCount += samples.count
        availableCount += samples.count
        return emit(draining: false)
    }

    /// Close the stream: emit the last frame that still starts inside real audio
    /// and release the trailing overlap, which fades the utterance out over half
    /// a frame instead of ending on a step.
    mutating func finish() -> [Float] {
        guard !passthrough else { return [] }
        var output = emit(draining: true)
        output.append(contentsOf: tail)
        tail = [Float](repeating: 0, count: hop)
        pending.removeAll()
        natural.removeAll()
        return output
    }

    // MARK: - Frame loop

    private mutating func emit(draining: Bool) -> [Float] {
        var output: [Float] = []
        while true {
            let ideal = Int((Float(frameIndex) * analysisHop).rounded())
            // Upper bound of everything the search plus the frame copy may read.
            let needed = ideal + searchRadius + frameLength
            if needed > availableCount {
                // Mid-stream this just means "come back with more audio". While
                // draining it means the utterance ended inside this frame, so
                // the frame is completed with silence — but only if it starts in
                // real audio, otherwise the output would grow a silent tail.
                guard draining, ideal < realCount else { break }
                pending.append(contentsOf: repeatElement(0, count: needed - availableCount))
                availableCount = needed
            }

            let start = alignedStart(ideal: ideal)
            let frame = windowedFrame(at: start)
            output.append(contentsOf: (0..<hop).map { tail[$0] + frame[$0] })
            tail = Array(frame[hop..<frameLength])
            natural = slice(from: start + hop, count: hop)

            frameIndex += 1
            let nextIdeal = Int((Float(frameIndex) * analysisHop).rounded())
            trim(before: max(0, min(start, nextIdeal - searchRadius)))
        }
        return output
    }

    /// Slide the analysis frame within ±`searchRadius` of its ideal position and
    /// keep the offset whose waveform best continues the previous frame.
    private func alignedStart(ideal: Int) -> Int {
        guard !natural.isEmpty else { return max(0, ideal) }
        let lower = max(0, ideal - searchRadius)
        let upper = ideal + searchRadius
        guard lower <= upper else { return lower }

        var bestStart = lower
        var bestScore = -Float.greatestFiniteMagnitude
        let count = vDSP_Length(hop)

        pending.withUnsafeBufferPointer { candidates in
            natural.withUnsafeBufferPointer { reference in
                guard let base = candidates.baseAddress, let ref = reference.baseAddress else { return }
                for candidate in lower...upper {
                    let offset = candidate - pendingOrigin
                    guard offset >= 0, offset + hop <= candidates.count else { continue }
                    var dot: Float = 0
                    vDSP_dotpr(base + offset, 1, ref, 1, &dot, count)
                    var energy: Float = 0
                    vDSP_svesq(base + offset, 1, &energy, count)
                    // Dividing by the candidate's own magnitude keeps the search
                    // honest across a loudness ramp — on a raw dot product the
                    // loudest window wins whether or not it is in phase.
                    let score = dot / (energy.squareRoot() + .leastNormalMagnitude)
                    if score > bestScore {
                        bestScore = score
                        bestStart = candidate
                    }
                }
            }
        }
        return bestStart
    }

    private func windowedFrame(at start: Int) -> [Float] {
        var frame = slice(from: start, count: frameLength)
        frame.withUnsafeMutableBufferPointer { samples in
            window.withUnsafeBufferPointer { taper in
                guard let out = samples.baseAddress, let win = taper.baseAddress else { return }
                vDSP_vmul(out, 1, win, 1, out, 1, vDSP_Length(frameLength))
            }
        }
        return frame
    }

    /// Copy `count` samples starting at an absolute stream index, zero-filling
    /// anything outside the buffered window.
    private func slice(from absolute: Int, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let offset = absolute - pendingOrigin
        let lower = max(0, offset)
        let upper = min(pending.count, offset + count)
        guard lower < upper else { return out }
        out.replaceSubrange((lower - offset)..<(upper - offset), with: pending[lower..<upper])
        return out
    }

    private mutating func trim(before absolute: Int) {
        let removable = min(absolute - pendingOrigin, pending.count)
        guard removable > 0 else { return }
        pending.removeFirst(removable)
        pendingOrigin += removable
    }
}
