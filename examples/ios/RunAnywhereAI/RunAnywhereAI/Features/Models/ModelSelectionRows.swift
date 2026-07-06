//
//  ModelSelectionRows.swift
//  RunAnywhereAI
//
//  Row components for model selection sheet
//

import SwiftUI
import RunAnywhere
import os

// MARK: - System TTS Row

/// System TTS selection row - uses built-in AVSpeechSynthesizer
struct SystemTTSRow: View {
    let isLoading: Bool
    let onSelect: () async -> Void

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                HStack(spacing: AppSpacing.smallMedium) {
                    Text("System Voice")
                        .font(AppTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)

                    Text("System")
                        .font(AppTypography.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(Color.primary.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)
                }

                HStack(spacing: AppSpacing.xxSmall) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.statusGreen)
                        .font(AppTypography.caption2)
                    Text("Built-in - Always available")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.statusGreen)
                }
            }

            Spacer()

            Button("Use") {
                Task { await onSelect() }
            }
            .font(AppTypography.caption)
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .controlSize(.small)
            .disabled(isLoading)
        }
        .padding(.vertical, AppSpacing.smallMedium)
    }
}

// MARK: - Loading Model Overlay

struct LoadingModelOverlay: View {
    let loadingProgress: String

    var body: some View {
        AppColors.overlayMedium
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: AppSpacing.xLarge) {
                    ProgressView()
                        .scaleEffect(DeviceFormFactor.current == .desktop ? 1.5 : 1.2)
                        #if os(macOS)
                        .controlSize(.large)
                        #endif

                    Text("Loading Model")
                        .font(AppTypography.headline)

                    Text(loadingProgress)
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 200)
                }
                .padding(DeviceFormFactor.current == .desktop ? 40 : AppSpacing.xxLarge)
                .frame(minWidth: DeviceFormFactor.current == .desktop ? 300 : nil)
                .background(AppColors.backgroundPrimary)
                .cornerRadius(AppSpacing.cornerRadiusXLarge)
                .shadow(radius: AppSpacing.shadowXLarge)
            }
    }
}

// MARK: - Device Info Row

struct DeviceInfoRow: View {
    let label: String
    let systemImage: String
    let value: String

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Neural Engine Row

struct NeuralEngineRow: View {
    var body: some View {
        HStack {
            Label("Neural Engine", systemImage: "brain")
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.statusGreen)
        }
    }
}

// MARK: - Loading Device Row

struct LoadingDeviceRow: View {
    var body: some View {
        HStack {
            ProgressView()
            Text("Loading device info...")
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Flat Model Row (Consumer-Friendly Design)

/// A model row designed for flat list display with prominent framework badge
struct FlatModelRow: View {
    private let logger = Logger(
        subsystem: "com.runanywhere.RunAnywhereAI",
        category: "ModelDownload"
    )
    private let catalogLogger = Logger(
        subsystem: "com.runanywhere",
        category: "Download"
    )

    let model: RAModelInfo
    let availabilityReason: String?
    let isSelected: Bool
    let isLoading: Bool
    let onDownloadCompleted: () -> Void
    let onSelectModel: () -> Void
    let onModelUpdated: () -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadStage: RADownloadStage = .downloading
    @State private var downloadErrorMessage: String?

    private var frameworkColor: Color {
        switch model.framework {
        case .llamaCpp: return AppColors.primaryAccent
        case .mlx: return .teal
        case .onnx: return .purple
        case .foundationModels: return .primary
        default: return .gray
        }
    }

    private var frameworkName: String {
        switch model.framework {
        case .llamaCpp: return "Fast"
        case .mlx: return "MLX"
        case .onnx: return "ONNX"
        case .foundationModels: return "Apple"
        case .systemTts: return "System"
        default: return model.framework.displayName
        }
    }

    /// Check if any LoRA adapters are compatible with this model
    private var hasLoRAAdapters: Bool {
        model.supportsLora
    }

    private var downloadAccessibilityLabel: String {
        let size = model.downloadSizeBytes
        if size > 0 {
            let formatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .memory)
            return "Get \(formatted)"
        }
        return "Get"
    }

    private var statusIcon: String {
        if availabilityReason != nil || downloadErrorMessage != nil {
            return "exclamationmark.triangle.fill"
        } else if model.isBuiltIn {
            return "checkmark.circle.fill"
        } else if model.localPathURL != nil {
            return "checkmark.circle.fill"
        } else {
            return "arrow.down.circle"
        }
    }

    private var statusColor: Color {
        if availabilityReason != nil || downloadErrorMessage != nil {
            return AppColors.statusOrange
        } else if model.isBuiltIn || model.localPathURL != nil {
            return AppColors.statusGreen
        } else {
            return AppColors.primaryAccent
        }
    }

    private var statusText: String {
        if let availabilityReason {
            return availabilityReason
        } else if let downloadErrorMessage {
            return downloadErrorMessage
        } else if model.isBuiltIn {
            return "Built-in"
        } else if model.localPathURL != nil {
            return "Ready"
        } else {
            return ""  // Removed "Download" text
        }
    }

    /// Get logo asset name for model - uses centralized extension
    private var modelLogoName: String {
        model.logoAssetName
    }

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            // Model logo
            Image(modelLogoName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(8)

            modelInfoView

            Spacer()

            actionButton
        }
        .padding(.vertical, AppSpacing.smallMedium)
        .opacity(isLoading && !isSelected ? 0.6 : 1.0)
    }

    private var modelInfoView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            // Model name with framework badge inline
            HStack(spacing: AppSpacing.smallMedium) {
                Text(model.name)
                    .font(AppTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)

                // Framework badge
                Text(frameworkName)
                    .font(AppTypography.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, AppSpacing.xxSmall)
                    .background(frameworkColor.opacity(0.15))
                    .foregroundColor(frameworkColor)
                    .cornerRadius(AppSpacing.cornerRadiusSmall)
            }

            statusRowView
        }
    }

    private var statusRowView: some View {
        HStack(spacing: AppSpacing.smallMedium) {
            // Status indicator (no size badge here anymore)
            if isDownloading {
                HStack(spacing: AppSpacing.xSmall) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("\(downloadStage.displayName)… \(Int(downloadProgress * 100))%")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            } else if !statusText.isEmpty {
                HStack(spacing: AppSpacing.xxSmall) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(AppTypography.caption2)
                    Text(statusText)
                        .font(AppTypography.caption2)
                        .foregroundColor(statusColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Thinking support indicator
            if model.supportsThinking {
                HStack(spacing: AppSpacing.xxSmall) {
                    Image(systemName: "brain")
                    Text("Smart")
                }
                .font(AppTypography.caption2)
                .padding(.horizontal, AppSpacing.small)
                .padding(.vertical, AppSpacing.xxSmall)
                .background(AppColors.badgePurple)
                .foregroundColor(AppColors.primaryPurple)
                .cornerRadius(AppSpacing.cornerRadiusSmall)
            }

            // LoRA adapter support indicator
            if hasLoRAAdapters {
                HStack(spacing: AppSpacing.xxSmall) {
                    Image(systemName: "sparkles")
                    Text("LoRA")
                }
                .font(AppTypography.caption2)
                .padding(.horizontal, AppSpacing.small)
                .padding(.vertical, AppSpacing.xxSmall)
                .background(AppColors.badgeBlue)
                .foregroundColor(AppColors.primaryBlue)
                .cornerRadius(AppSpacing.cornerRadiusSmall)
            }
        }
    }

    @ViewBuilder private var actionButton: some View {
        if availabilityReason != nil {
            Button("Unavailable") {}
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(true)
        } else if model.isBuiltIn {
            // Built-in models (Foundation Models, System TTS) - always ready
            Button("Use") {
                onSelectModel()
            }
            .font(AppTypography.caption)
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .controlSize(.small)
            .disabled(isLoading || isSelected)
        } else if model.localPathURL == nil {
            // Model needs to be downloaded
            if isDownloading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    Task {
                        await downloadModel()
                    }
                } label: {
                    HStack(spacing: AppSpacing.xxSmall) {
                        Image(systemName: "arrow.down.circle.fill")
                        // Show file size instead of "Get"
                        let size = model.downloadSizeBytes
                        if size > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .memory))
                        } else {
                            Text("Get")
                        }
                    }
                }
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .tint(AppColors.primaryAccent)
                .controlSize(.small)
                .accessibilityIdentifier("model-download-\(model.id)")
                .accessibilityLabel(downloadAccessibilityLabel)
                .disabled(isLoading)
            }
        } else {
            // Model is downloaded - ready to use
            Button("Use") {
                onSelectModel()
            }
            .font(AppTypography.caption)
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .controlSize(.small)
            .disabled(isLoading || isSelected)
        }
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
            downloadStage = .downloading
            downloadErrorMessage = nil
        }

        logger.info("Starting download for \(model.id, privacy: .public)")
        catalogLogger.info("Starting download for \(model.id, privacy: .public)")

        do {
            try await RunAnywhere.downloadModel(model) { progress in
                await MainActor.run {
                    self.downloadProgress = Double(progress.overallProgress)
                    self.downloadStage = progress.stage
                }
            }

            logger.info("Download completed for \(model.id, privacy: .public)")
            catalogLogger.info("Download completed for \(model.id, privacy: .public)")

            await MainActor.run {
                self.downloadProgress = 1.0
                self.isDownloading = false
                self.downloadStage = .downloading
                self.downloadErrorMessage = nil
                onDownloadCompleted()
            }
        } catch {
            let message = (error as? SDKException)?.message ?? error.localizedDescription
            logger.error(
                "Download failed for \(model.id, privacy: .public): \(message, privacy: .public)"
            )

            await MainActor.run {
                downloadProgress = 0.0
                isDownloading = false
                downloadStage = .downloading
                downloadErrorMessage = message.isEmpty ? "Download failed" : message
            }
        }
    }
}
