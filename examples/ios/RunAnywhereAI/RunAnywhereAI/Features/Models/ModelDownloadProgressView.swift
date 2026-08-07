//
//  ModelDownloadProgressView.swift
//  RunAnywhereAI
//
//  What a download in flight looks like.
//
//  ## Why a percentage was not enough
//
//  The previous control was a spinner and an integer percent. On a 4 GB model
//  over a hotel connection that is indistinguishable from a hang: the number sits
//  at 3% for minutes and the spinner keeps turning whether or not a single byte
//  is moving. The SDK has always been told the byte counts, the measured rate,
//  and the projected finish (C++ computes them in `download_orchestrator.cpp`),
//  so the fix is to show them, not to invent a nicer spinner.
//
//  ## Determinate when we know, indeterminate when we don't
//
//  A bar pinned at zero because the server sent no Content-Length reads as
//  broken. When `fraction` is nil this shows a genuinely indeterminate track
//  instead, which is an honest statement that the size is unknown — and the byte
//  counter still moves, so progress is visible either way.
//
//  ## Motion
//
//  The bar interpolates its own width on the standard tier when the fraction
//  changes: a progress bar that jumps between poll samples reads as stuttering,
//  and interpolating between two known values is exactly the case
//  DESIGN_GUIDELINE §6 calls "motion that explains a state change". Nothing here
//  loops except the indeterminate track, which is the one case where a loop *is*
//  the information (unknown duration), and it is suppressed under Reduce Motion
//  where a static striped track carries the same meaning.
//

import SwiftUI

/// Progress bar plus the byte/rate/ETA detail line for one in-flight download.
struct ModelDownloadProgressView: View {
    let progress: ModelDownloadProgress
    /// Cancel the transfer. Bytes already on disk are kept for a resume.
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                DownloadProgressTrack(fraction: progress.fraction)

                // A percentage is still the fastest thing to read, so it stays —
                // it just is not the only thing shown now. Monospaced digits so
                // the label does not reflow as it counts up.
                if let percent = progress.percent {
                    Text("\(percent)%")
                        .appType(.monoMetric)
                        .foregroundStyle(AppColors.textSecondary)
                        .contentTransition(.numericText())
                }

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel download")
                .help("Cancel download — downloaded bytes are kept")
            }

            // `ViewThatFits` picks the longest variant that fits, so a wide row
            // shows bytes + rate + ETA and a narrow one degrades to just the ETA
            // rather than clipping a number mid-unit.
            // Identified by position, not by text: the variants collapse to the
            // same string early in a transfer (before a rate or ETA exists), and
            // `id: \.self` would then hand ViewThatFits duplicate child IDs, which
            // is a hard error rather than a cosmetic one.
            ViewThatFits(in: .horizontal) {
                ForEach(Array(progress.detailLineVariants.enumerated()), id: \.offset) { variant in
                    Text(variant.element)
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            // The detail line changes several times a second; a transition on it
            // would be noise, so it updates without animation.
            .animation(nil, value: progress.detailLine)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// VoiceOver gets one sentence rather than a percent, a byte pair, a rate and
    /// an ETA read as four separate fragments.
    private var accessibilityLabel: String {
        let head = progress.percent.map { "Downloading, \($0) percent" } ?? "Downloading"
        return "\(head). \(progress.detailLine)"
    }
}

// MARK: - Track

/// The bar itself: determinate when the size is known, honestly indeterminate
/// when it is not.
private struct DownloadProgressTrack: View {
    let fraction: Float?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private static let height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.border)

                if let fraction {
                    Capsule()
                        .fill(AppColors.brand)
                        .frame(width: max(geometry.size.width * CGFloat(fraction), Self.height))
                } else {
                    IndeterminateSweep(width: geometry.size.width, reduceMotion: reduceMotion)
                }
            }
        }
        .frame(height: Self.height)
        // Interpolate between two known fractions so the bar glides between poll
        // samples instead of stepping. Reduce Motion is handled by the token.
        .motionAware(Motion.standardFade, value: fraction)
        .accessibilityHidden(true)
    }
}

/// A single segment travelling the track while the total size is unknown.
///
/// Clock-driven rather than a toggled `@State` with `repeatForever`, so two
/// concurrent downloads stay in phase and a re-render mid-cycle cannot restart
/// the curve. Linear, on the canonical 1.2s shimmer period (§6.4) — an
/// indeterminate indicator must not ease, because easing implies a position
/// within a known range, which is precisely what is unknown here.
private struct IndeterminateSweep: View {
    let width: CGFloat
    let reduceMotion: Bool

    private static let period: Double = 1.2
    private static let segmentRatio: CGFloat = 0.35

    var body: some View {
        let segment = max(width * Self.segmentRatio, 8)

        if reduceMotion {
            // No loop under Reduce Motion. A dimmed full-width fill still says
            // "working, length unknown" without anything moving.
            Capsule()
                .fill(AppColors.brand.opacity(0.45))
        } else {
            TimelineView(.animation) { context in
                Capsule()
                    .fill(AppColors.brand)
                    .frame(width: segment)
                    .offset(x: Self.offset(at: context.date, width: width, segment: segment))
            }
        }
    }

    /// Travels from fully off the leading edge to fully off the trailing edge, so
    /// the segment never appears to be clipped in place at either end.
    private static func offset(at date: Date, width: CGFloat, segment: CGFloat) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        let phase = CGFloat(elapsed / period)
        return -segment + phase * (width + segment)
    }
}

// MARK: - Preview

#Preview("Download states") {
    VStack(alignment: .leading, spacing: Space.xl) {
        ModelDownloadProgressView(progress: sample(fraction: 0.42)) {}
        ModelDownloadProgressView(progress: sample(fraction: 0.03)) {}
        ModelDownloadProgressView(progress: multiFile()) {}
        ModelDownloadProgressView(progress: retrying()) {}
        ModelDownloadProgressView(progress: unknownSize()) {}
    }
    .padding(Space.xl)
    .frame(width: 420)
    .background(AppColors.background)
}

private func sample(fraction: Float) -> ModelDownloadProgress {
    var progress = ModelDownloadProgress()
    progress.bytesTotal = 4_400_000_000
    progress.bytesDone = Int64(Float(progress.bytesTotal) * fraction)
    progress.fraction = fraction
    progress.bytesPerSecond = 3_600_000
    progress.etaSeconds = 735
    return progress
}

private func multiFile() -> ModelDownloadProgress {
    var progress = sample(fraction: 0.66)
    progress.currentFileIndex = 1
    progress.totalFiles = 3
    return progress
}

private func retrying() -> ModelDownloadProgress {
    var progress = sample(fraction: 0.18)
    progress.retryAttempt = 2
    return progress
}

private func unknownSize() -> ModelDownloadProgress {
    var progress = ModelDownloadProgress()
    progress.bytesDone = 12_400_000
    progress.bytesTotal = 0
    progress.fraction = nil
    return progress
}
