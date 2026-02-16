//
//  BenchmarkProgressView.swift
//  RunAnywhereAI
//
//  Progress overlay shown while benchmarks are running.
//

import SwiftUI

struct BenchmarkProgressView: View {
    let progress: Double
    let currentScenario: String
    let currentModel: String
    let completedCount: Int
    let totalCount: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xxLarge) {
            Text("Running Benchmarks")
                .font(AppTypography.headline)

            ProgressView(value: progress)
                .tint(AppColors.primaryAccent)

            VStack(spacing: AppSpacing.small) {
                Text(currentScenario)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textPrimary)

                if !currentModel.isEmpty {
                    Text(currentModel)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Text("\(completedCount) / \(totalCount)")
                    .font(AppTypography.monospaced)
                    .foregroundColor(AppColors.textSecondary)
            }

            Button("Cancel", role: .destructive) {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
        .padding(AppSpacing.xxLarge)
        .frame(maxWidth: 320)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusCard)
        .shadow(color: AppColors.shadowMedium, radius: AppSpacing.shadowLarge)
    }
}
