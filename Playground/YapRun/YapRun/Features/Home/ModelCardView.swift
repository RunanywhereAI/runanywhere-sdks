//
//  ModelCardView.swift
//  YapRun
//
//  Card component for displaying a single STT model with its state.
//  Shared between iOS and macOS.
//

import RunAnywhere
import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let isActive: Bool
    let downloadProgress: Double?
    let onDownload: () -> Void
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: model.framework == .whisperKit ? "brain" : "cpu")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(model.frameworkColor)
                .frame(width: 40, height: 40)
                .background(model.frameworkColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text(model.frameworkBadge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(model.frameworkColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(model.frameworkColor.opacity(0.15), in: Capsule())
                }

                HStack(spacing: 6) {
                    Text(model.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)

                    if !model.engineNote.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)

                        Text(model.framework == .whisperKit ? "Optimized" : "High CPU")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(model.framework == .whisperKit ? .green : .orange)
                    }
                }
            }

            Spacer()

            // State-dependent trailing
            trailingContent
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? AppColors.primaryGreen.opacity(0.4) : AppColors.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let progress = downloadProgress {
            // Downloading
            HStack(spacing: 8) {
                ProgressView()
                    .tint(AppColors.ctaOrange)
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppColors.ctaOrange)
            }
        } else if isActive {
            // Loaded / active
            Text("Active")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.primaryGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.primaryGreen.opacity(0.15), in: Capsule())
        } else if model.isDownloaded {
            // Downloaded but not loaded
            HStack(spacing: 8) {
                Button(action: onLoad) {
                    Text("Load")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColors.overlayMedium, in: Capsule())
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(AppColors.primaryRed.opacity(0.7))
                }
            }
        } else {
            // Not downloaded
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }
}
