//
//  InitializationViews.swift
//  RunAnywhereAI
//

import SwiftUI

// MARK: - Loading view shown while the SDK bootstraps

struct InitializationLoadingView: View {
    private let startDate = Date()

    private let trackWidth: CGFloat = 240
    private let barHeight: CGFloat = 6

    var body: some View {
        VStack(spacing: 24) {
            Text("RunAnywhere")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)

            progressBar
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }

    // Determinate 0→100 sweep. TimelineView drives it and SwiftUI cancels the
    // ticker when the view leaves the hierarchy, so there is no leaked timer.
    private var progressBar: some View {
        TimelineView(.periodic(from: startDate, by: 0.02)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(startDate)
            let progress = progressValue(elapsed: elapsed)

            Capsule()
                .fill(AppColors.backgroundGray5)
                .frame(width: trackWidth, height: barHeight)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.primaryAccent)
                        .frame(width: trackWidth * CGFloat(progress / 100), height: barHeight)
                }
                .clipShape(Capsule())
        }
    }

    // Piecewise smoothstep so the fill eases to a near-stop (damped arrival) as
    // it settles at 20 and 60 before accelerating on to 100.
    private func progressValue(elapsed: Double) -> Double {
        let total = 2.6
        let u = min(elapsed / total, 1.0)

        func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

        let uA = 0.35   // reaches 20
        let uB = 0.72   // reaches 60

        if u <= uA {
            return smoothstep(u / uA) * 20
        } else if u <= uB {
            return 20 + smoothstep((u - uA) / (uB - uA)) * 40
        } else {
            return 60 + smoothstep((u - uB) / (1 - uB)) * 40
        }
    }
}

// MARK: - Error view shown when SDK initialisation fails

struct InitializationErrorView: View {
    let error: Error
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(AppTypography.system60)
                .foregroundColor(AppColors.statusOrange)

            Text("RunAnywhere Couldn't Start")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .font(.headline)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }
}
