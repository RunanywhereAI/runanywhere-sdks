//
//  SimplifiedModelsView.swift
//  RunAnywhereAI
//
//  A simplified models view for managing AI models
//

import SwiftUI
import RunAnywhere

struct SimplifiedModelsView: View {
    @StateObject private var viewModel = ModelListViewModel.shared
    @StateObject private var deviceInfo = DeviceInfoService.shared

    @State private var selectedModel: ModelInfo?
    @State private var expandedFramework: InferenceFramework?
    @State private var availableFrameworks: [InferenceFramework] = []
    @State private var showingAddModelSheet = false

    /// All available models sorted by availability (downloaded first)
    private var sortedModels: [ModelInfo] {
        viewModel.availableModels.sorted { model1, model2 in
            let m1Priority = model1.preferredFramework == .foundationModels ? 0 : (model1.localPath != nil ? 1 : 2)
            let m2Priority = model2.preferredFramework == .foundationModels ? 0 : (model2.localPath != nil ? 1 : 2)
            if m1Priority != m2Priority {
                return m1Priority < m2Priority
            }
            return model1.name < model2.name
        }
    }

    var body: some View {
        NavigationView {
            mainContentView
        }
    }

    private var mainContentView: some View {
        List {
            deviceStatusSection
            modelsListSection
        }
        .navigationTitle("Models")
        .task {
            await loadInitialData()
        }
    }

    private func loadInitialData() async {
        await viewModel.loadModels()
        await loadAvailableFrameworks()
    }

    private func loadAvailableFrameworks() async {
        // Get available frameworks from SDK - derived from registered models
        let frameworks = await MainActor.run {
            RunAnywhere.getRegisteredFrameworks()
        }
        await MainActor.run {
            self.availableFrameworks = frameworks
        }
    }

    private var deviceStatusSection: some View {
        Section("Device Status") {
            if let device = deviceInfo.deviceInfo {
                deviceInfoRows(device)
            } else {
                loadingDeviceRow
            }
        }
    }

    private func deviceInfoRows(_ device: SystemDeviceInfo) -> some View {
        Group {
            deviceInfoRow(label: "Model", systemImage: "iphone", value: device.modelName)
            deviceInfoRow(label: "Chip", systemImage: "cpu", value: device.chipName)
            deviceInfoRow(label: "Memory", systemImage: "memorychip",
                         value: ByteCountFormatter.string(fromByteCount: device.totalMemory, countStyle: .memory))

            if device.neuralEngineAvailable {
                neuralEngineRow
            }
        }
    }

    private func deviceInfoRow(label: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var neuralEngineRow: some View {
        HStack {
            Label("Neural Engine", systemImage: "brain")
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.statusGreen)
        }
    }

    private var loadingDeviceRow: some View {
        HStack {
            ProgressView()
            Text("Loading device info...")
                .foregroundColor(AppColors.textSecondary)
        }
    }

    /// Flat list of all models with framework badges
    private var modelsListSection: some View {
        Section {
            if sortedModels.isEmpty {
                VStack(alignment: .center, spacing: AppSpacing.mediumLarge) {
                    ProgressView()
                    Text("Loading models...")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xLarge)
            } else {
                ForEach(sortedModels, id: \.id) { model in
                    SimplifiedModelRow(
                        model: model,
                        isSelected: selectedModel?.id == model.id,
                        onDownloadCompleted: {
                            Task {
                                await viewModel.loadModels()
                            }
                        },
                        onSelectModel: {
                            Task {
                                await selectModel(model)
                            }
                        },
                        onModelUpdated: {
                            Task {
                                await viewModel.loadModels()
                            }
                        }
                    )
                }
            }
        } header: {
            Text("Available Models")
        } footer: {
            Text("All models run privately on your device. Downloaded models are ready to use.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private func selectModel(_ model: ModelInfo) async {
        selectedModel = model

        // Update the view model state
        await viewModel.selectModel(model)
    }
}

// MARK: - Supporting Views

/// Simplified model row with framework badge for flat list display
private struct SimplifiedModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let onDownloadCompleted: () -> Void
    let onSelectModel: () -> Void
    let onModelUpdated: () -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0

    private var frameworkColor: Color {
        guard let framework = model.preferredFramework else { return .gray }
        switch framework {
        case .llamaCpp: return .blue
        case .onnx: return .purple
        case .foundationModels: return .primary
        case .whisperKit: return .green
        default: return .gray
        }
    }

    private var frameworkName: String {
        guard let framework = model.preferredFramework else { return "Unknown" }
        switch framework {
        case .llamaCpp: return "Fast"
        case .onnx: return "ONNX"
        case .foundationModels: return "Apple"
        case .whisperKit: return "Whisper"
        default: return framework.displayName
        }
    }

    private var isReady: Bool {
        model.preferredFramework == .foundationModels || model.localPath != nil
    }

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            // Model info with framework badge
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                // Name with framework badge
                HStack(spacing: AppSpacing.smallMedium) {
                    Text(model.name)
                        .font(AppTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)

                    Text(frameworkName)
                        .font(AppTypography.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(frameworkColor.opacity(0.15))
                        .foregroundColor(frameworkColor)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)
                }

                // Size and status
                HStack(spacing: AppSpacing.smallMedium) {
                    if let size = model.memoryRequired, size > 0 {
                        Label(
                            ByteCountFormatter.string(fromByteCount: size, countStyle: .memory),
                            systemImage: "memorychip"
                        )
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                    }

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
                            Image(systemName: isReady ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundColor(isReady ? AppColors.statusGreen : AppColors.statusBlue)
                                .font(AppTypography.caption2)
                            Text(model.preferredFramework == .foundationModels ? "Built-in" : (model.localPath != nil ? "Ready" : "Download"))
                                .font(AppTypography.caption2)
                                .foregroundColor(isReady ? AppColors.statusGreen : AppColors.statusBlue)
                        }
                    }

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

            Spacer()

            // Action button
            if model.preferredFramework == .foundationModels {
                Button("Use") {
                    onSelectModel()
                }
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSelected)
            } else if model.localPath == nil {
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
                    .controlSize(.small)
                }
            } else {
                if isSelected {
                    HStack(spacing: AppSpacing.xxSmall) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.statusGreen)
                        Text("Active")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.statusGreen)
                    }
                } else {
                    Button("Use") {
                        onSelectModel()
                    }
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, AppSpacing.smallMedium)
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }

        do {
            // Use the new convenience download API
            let progressStream = try await RunAnywhere.downloadModel(model.id)

            for await progress in progressStream {
                await MainActor.run {
                    self.downloadProgress = progress.overallProgress
                    print("Download progress for \(model.name): \(Int(progress.overallProgress * 100))%")
                }

                // Check if download completed
                if progress.stage == .completed {
                    await MainActor.run {
                        self.downloadProgress = 1.0
                        self.isDownloading = false
                        onDownloadCompleted()
                    }
                    return
                }
            }

            // If we exit the loop normally, download completed
            await MainActor.run {
                self.downloadProgress = 1.0
                self.isDownloading = false
                onDownloadCompleted()
            }

        } catch {
            await MainActor.run {
                downloadProgress = 0.0
                isDownloading = false
            }
        }
    }
}

#Preview {
    SimplifiedModelsView()
}
