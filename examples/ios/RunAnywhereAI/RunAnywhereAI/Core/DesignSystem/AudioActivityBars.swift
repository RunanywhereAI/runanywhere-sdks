//
//  AudioActivityBars.swift
//  RunAnywhereAI
//
//  The app's one audio-activity figure, in two honest modes.
//
//  ## Why one component
//
//  Three screens had hand-rolled bar waveforms, and all three were built the
//  same wrong way: N sibling bars, each carrying its own
//  `.repeatForever(autoreverses: true)` with a `.delay(index * k)` stagger, at a
//  different duration per screen (0.6s on TTS, 0.8s on STT). That is N
//  independent animations pretending to be one object — they drift, they cannot
//  be interrupted coherently, and none of them had a Reduce Motion path.
//
//  Worse, they were *dishonest*. A bar waveform is a picture of amplitude. Those
//  bars were a fixed array of heights (`[20, 32, 28, 36, 28, 32, 20]`) toggling
//  to a second fixed array on a loop. They showed a shape that looked like the
//  user's voice and was in fact a hardcoded constant. On the STT "Ready to
//  transcribe" screen it looped forever while the microphone was closed.
//
//  ## The two modes
//
//  `.level(Float)` — a real meter. Bar heights come from the signal, so the
//  figure is a readout and every frame of it means something.
//
//  `.indeterminate` — playback or work is happening, but this layer genuinely
//  has no amplitude to show (`TTSViewModel` publishes `isSpeaking`, not a level;
//  see the SDK note below). Rather than invent an amplitude, the silhouette
//  holds still and a single highlight travels across it on the canonical 1.2s
//  shimmer period. Shimmer is the established idiom for "working, duration
//  unknown"; it communicates activity without claiming to be a measurement.
//
//  SDK gap worth closing: `RunAnywhere.tts.speak` exposes no playback level or
//  progress, so a TTS screen cannot draw a true waveform for its own output.
//  Every SDK would benefit from a level or progress signal on the speak path.
//
//  ## Motion
//
//  One value, one animation, one signature, in both modes. `.level` retargets
//  the whole figure from wherever it is on each new sample, so it tracks a voice
//  instead of queueing per-bar curves. `.indeterminate` is driven by a clock, so
//  two figures on screen stay in phase and a re-render cannot restart the sweep.
//  Reduce Motion suppresses the sweep entirely and leaves the silhouette, which
//  still reads as "audio here".
//

import SwiftUI

struct AudioActivityBars: View {
    enum Mode: Equatable {
        /// A true meter: `0...1`.
        case level(Float)
        /// Activity with no measurable amplitude at this layer.
        case indeterminate
    }

    let mode: Mode
    var tint: Color = AppColors.brand
    var barCount: Int = 7
    var height: CGFloat = 40

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private static let sweepPeriod: Double = 1.2

    var body: some View {
        Group {
            switch mode {
            case .level(let level):
                bars { index in
                    BarStyle(
                        height: levelHeight(index, level: level),
                        opacity: baseOpacity(index)
                    )
                }
                // The one value that changed drives the one animation.
                .motionAware(Motion.microFade, value: level)

            case .indeterminate:
                indeterminateBars
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Indeterminate

    @ViewBuilder private var indeterminateBars: some View {
        if reduceMotion {
            bars { index in
                BarStyle(height: restHeight(index), opacity: baseOpacity(index))
            }
        } else {
            TimelineView(.animation) { context in
                let sweep = Self.sweepPhase(at: context.date)
                bars { index in
                    BarStyle(
                        height: restHeight(index),
                        opacity: baseOpacity(index) * highlight(index, sweep: sweep)
                    )
                }
            }
        }
    }

    /// A soft moving crest. Opacity only — the silhouette never changes shape,
    /// so nothing here can be mistaken for a measurement, and no frame costs a
    /// layout pass.
    private func highlight(_ index: Int, sweep: Double) -> Double {
        guard barCount > 1 else { return 1 }
        let position = Double(index) / Double(barCount - 1)
        // Wrapped distance, so the crest leaving the right edge is already
        // arriving at the left and the loop has no visible seam.
        var distance = abs(position - sweep)
        if distance > 0.5 { distance = 1 - distance }
        let falloff = max(0, 1 - distance / 0.35)
        return 0.45 + 0.55 * falloff
    }

    private static func sweepPhase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod
    }

    // MARK: - Geometry

    private struct BarStyle {
        let height: CGFloat
        let opacity: Double
    }

    private func bars(_ style: @escaping (Int) -> BarStyle) -> some View {
        HStack(alignment: .center, spacing: Space.xs) {
            ForEach(0..<barCount, id: \.self) { index in
                let resolved = style(index)
                Capsule()
                    .fill(tint.opacity(resolved.opacity))
                    .frame(width: Self.barWidth, height: resolved.height)
            }
        }
    }

    private static let barWidth: CGFloat = 5

    /// Bars taper from the center out, so the figure has a recognisable
    /// silhouette at rest instead of reading as a progress bar on its side.
    private func envelope(_ index: Int) -> CGFloat {
        guard barCount > 1 else { return 1 }
        let mid = CGFloat(barCount - 1) / 2
        let distance = abs(CGFloat(index) - mid) / mid
        return 1 - 0.55 * distance * distance
    }

    private func levelHeight(_ index: Int, level: Float) -> CGFloat {
        // A floor keeps the figure present in a silent room: a meter that
        // collapses to nothing reads as broken rather than as quiet.
        let amplitude = 0.18 + 0.82 * CGFloat(max(0, min(1, level)))
        return max(Stroke.emphasis, height * amplitude * envelope(index))
    }

    private func restHeight(_ index: Int) -> CGFloat {
        max(Stroke.emphasis, height * 0.62 * envelope(index))
    }

    private func baseOpacity(_ index: Int) -> Double {
        0.45 + 0.55 * Double(envelope(index))
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch mode {
        case .level: return "Input level"
        case .indeterminate: return "Audio activity"
        }
    }

    private var accessibilityValue: String {
        switch mode {
        case .level(let level): return "\(Int(max(0, min(1, level)) * 100)) percent"
        case .indeterminate: return "In progress"
        }
    }
}

#Preview("Modes") {
    VStack(spacing: Space.xxl) {
        AudioActivityBars(mode: .level(0.1))
        AudioActivityBars(mode: .level(0.55))
        AudioActivityBars(mode: .level(1.0), tint: AppColors.statusGreen)
        AudioActivityBars(mode: .indeterminate, tint: AppColors.primaryPurple)
    }
    .padding(Space.xxl)
    .background(AppColors.background)
}
