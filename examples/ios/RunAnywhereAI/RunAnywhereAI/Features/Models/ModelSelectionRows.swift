//
//  ModelSelectionRows.swift
//  RunAnywhereAI
//
//  Row components for model selection sheet
//

import SwiftUI
import RunAnywhere

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
    let model: ModelInfo
    let isSelected: Bool
    let isLoading: Bool
    let onDownloadCompleted: () -> Void
    let onSelectModel: () -> Void
    let onModelUpdated: () -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0

    private var frameworkColor: Color {
        switch model.framework {
        case .llamaCpp: return AppColors.primaryAccent
        case .onnx: return .purple
        case .foundationModels: return .primary
        default: return .gray
        }
    }

    private var frameworkName: String {
        switch model.framework {
        case .llamaCpp: return "Fast"
        case .onnx: return "ONNX"
        case .foundationModels: return "Apple"
        case .systemTTS: return "System"
        default: return model.framework.displayName
        }
    }

    /// Check if this is a built-in model that doesn't require download
    private var isBuiltIn: Bool {
        model.framework == .foundationModels ||
        model.framework == .systemTTS ||
        model.artifactType == .builtIn
    }

    private var statusIcon: String {
        if isBuiltIn {
            return "checkmark.circle.fill"
        } else if model.localPath != nil {
            return "checkmark.circle.fill"
        } else {
            return "arrow.down.circle"
        }
    }

    private var statusColor: Color {
        if isBuiltIn || model.localPath != nil {
            return AppColors.statusGreen
        } else {
            return AppColors.primaryAccent
        }
    }

    private var statusText: String {
        if isBuiltIn {
            return "Built-in"
        } else if model.localPath != nil {
            return "Ready"
        } else {
            return "Download"
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
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
            // Size badge
            if let size = model.downloadSize, size > 0 {
                Label(
                    ByteCountFormatter.string(fromByteCount: size, countStyle: .memory),
                    systemImage: "memorychip"
                )
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
            }

            // Status indicator
            if isDownloading {
                HStack(spacing: AppSpacing.xSmall) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            } else {
                HStack(spacing: AppSpacing.xxSmall) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(AppTypography.caption2)
                    Text(statusText)
                        .font(AppTypography.caption2)
                        .foregroundColor(statusColor)
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
        }
    }

    @ViewBuilder private var actionButton: some View {
        if isBuiltIn {
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
        } else if model.localPath == nil {
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
                        Text("Get")
                    }
                }
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .tint(AppColors.primaryAccent)
                .controlSize(.small)
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
        }

        do {
            let progressStream = try await RunAnywhere.downloadModel(model.id)

            for await progress in progressStream {
                await MainActor.run {
                    self.downloadProgress = progress.percentage
                }

                switch progress.state {
                case .completed:
                    await MainActor.run {
                        self.downloadProgress = 1.0
                        self.isDownloading = false
                        onDownloadCompleted()
                    }
                    return

                case .failed:
                    await MainActor.run {
                        self.downloadProgress = 0.0
                        self.isDownloading = false
                    }
                    return

                default:
                    continue
                }
            }
        } catch {
            await MainActor.run {
                downloadProgress = 0.0
                isDownloading = false
            }
        }
    }
}
