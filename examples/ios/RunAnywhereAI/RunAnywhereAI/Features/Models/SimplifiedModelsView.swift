//
//  SimplifiedModelsView.swift
//  RunAnywhereAI
//
//  A simplified models view that demonstrates SDK usage
//

import SwiftUI
import RunAnywhere

struct SimplifiedModelsView: View {
    @StateObject private var viewModel = ModelListViewModel.shared
    @StateObject private var deviceInfo = DeviceInfoService.shared

    @State private var selectedModel: ModelInfo?
    @State private var expandedFramework: LLMFramework?
    @State private var availableFrameworks: [LLMFramework] = []
    @State private var showingAddModelSheet = false

    var body: some View {
        NavigationView {
            mainContentView
        }
    }

    private var mainContentView: some View {
        List {
            deviceStatusSection
            frameworksSection
            modelsSection
        }
        .navigationTitle("Models")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add Model") {
                    showingAddModelSheet = true
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                Button("Add Model") {
                    showingAddModelSheet = true
                }
            }
            #endif
        }
        .sheet(isPresented: $showingAddModelSheet) {
            AddModelFromURLView(onModelAdded: { modelInfo in
                Task {
                    await viewModel.addImportedModel(modelInfo)
                }
            })
        }
        .task {
            await loadInitialData()
        }
    }

    private func loadInitialData() async {
        await viewModel.loadModels()
        await loadAvailableFrameworks()
    }

    private func loadAvailableFrameworks() async {
        // Get available frameworks from SDK
        let frameworks = RunAnywhere.getAvailableFrameworks()
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

    private var frameworksSection: some View {
        Section("Available Frameworks") {
            if availableFrameworks.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                    HStack {
                        ProgressView()
                        Text("Loading frameworks...")
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Text("No framework adapters are currently registered. Register framework adapters to see available frameworks.")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.statusOrange)
                        .padding(.top, AppSpacing.xSmall)
                }
            } else {
                ForEach(availableFrameworks, id: \.self) { framework in
                    FrameworkRow(
                        framework: framework,
                        isExpanded: expandedFramework == framework,
                        onTap: { toggleFramework(framework) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        if let expanded = expandedFramework {
            let filteredModels = viewModel.availableModels.filter { $0.compatibleFrameworks.contains(expanded) }

            Section("Models for \(expanded.displayName)") {
                ForEach(filteredModels, id: \.id) { model in
                    ModelRow(
                        model: model,
                        isSelected: selectedModel?.id == model.id,
                        onDownloadCompleted: {
                            Task {
                                await viewModel.loadModels() // Refresh models list
                                // Also refresh available frameworks in case new adapters were registered
                                await loadAvailableFrameworks()
                            }
                        },
                        onSelectModel: {
                            Task {
                                await selectModel(model)
                            }
                        },
                        onModelUpdated: {
                            Task {
                                await viewModel.loadModels() // Refresh models list after thinking update
                                await loadAvailableFrameworks()
                            }
                        }
                    )
                }

                if filteredModels.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                        Text("No models available for this framework")
                            .foregroundColor(AppColors.textSecondary)
                            .font(AppTypography.caption)

                        Text("Tap 'Add Model' to add a model from URL")
                            .foregroundColor(AppColors.statusBlue)
                            .font(AppTypography.caption2)
                    }
                }
            }
        }
    }

    private func toggleFramework(_ framework: LLMFramework) {
        withAnimation {
            if expandedFramework == framework {
                expandedFramework = nil
            } else {
                expandedFramework = framework
            }
        }
    }

    private func selectModel(_ model: ModelInfo) async {
        selectedModel = model

        // Update the view model state
        await viewModel.selectModel(model)
    }
}

// MARK: - Supporting Views

private struct ModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let onDownloadCompleted: () -> Void
    let onSelectModel: () -> Void
    let onModelUpdated: () -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(model.name)
                    .font(AppTypography.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                HStack(spacing: AppSpacing.smallMedium) {
                    let size = model.memoryRequired ?? 0
                    if size > 0 {
                        Label(
                            ByteCountFormatter.string(fromByteCount: size, countStyle: .memory),
                            systemImage: "memorychip"
                        )
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                    }

                    let format = model.format
                    Text(format.rawValue.uppercased())
                        .font(AppTypography.caption2)
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(AppColors.badgeGray)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)

                    // Show thinking indicator if model supports thinking
                    if model.supportsThinking {
                        HStack(spacing: AppSpacing.xxSmall) {
                            Image(systemName: "brain")
                                .font(AppTypography.caption2)
                            Text("THINKING")
                                .font(AppTypography.caption2)
                        }
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(AppColors.badgePurple)
                        .foregroundColor(AppColors.primaryPurple)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)
                    } else if model.localPath != nil {
                        // For downloaded models without thinking support, show option to enable it
                        Button(action: {
                            // Enable thinking support for this model
                            Task {
                                // Thinking support update not available in new API
                                // Will be enabled when the model is loaded
                                onModelUpdated()
                            }
                        }) {
                            HStack(spacing: AppSpacing.xxSmall) {
                                Image(systemName: "brain")
                                    .font(AppTypography.caption2)
                                Text("ENABLE")
                                    .font(AppTypography.caption2)
                            }
                            .padding(.horizontal, AppSpacing.small)
                            .padding(.vertical, AppSpacing.xxSmall)
                            .background(AppColors.badgeOrange)
                            .foregroundColor(AppColors.statusOrange)
                            .cornerRadius(AppSpacing.cornerRadiusSmall)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Show download status
                if let _ = model.downloadURL {
                    if model.localPath == nil {
                        HStack(spacing: AppSpacing.xSmall) {
                            if isDownloading {
                                ProgressView(value: downloadProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.textSecondary)
                            } else {
                                Text("Available for download")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.statusBlue)
                            }
                        }
                    } else {
                        HStack(spacing: AppSpacing.xSmall) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.statusGreen)
                                .font(AppTypography.caption2)
                            Text("Downloaded")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.statusGreen)
                        }
                    }
                }
            }

            Spacer()

            // Action buttons based on model state
            HStack(spacing: AppSpacing.smallMedium) {
                if let _ = model.downloadURL, model.localPath == nil {
                    // Model needs to be downloaded
                    if isDownloading {
                        VStack(spacing: AppSpacing.xSmall) {
                            ProgressView()
                                .scaleEffect(0.8)
                            if downloadProgress > 0 {
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    } else {
                        Button("Download") {
                            Task {
                                await downloadModel()
                            }
                        }
                        .font(AppTypography.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else if model.localPath != nil {
                    // Model is downloaded - show select and load options
                    if isSelected {
                        HStack(spacing: AppSpacing.xSmall) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.statusGreen)
                            Text("Loaded")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.statusGreen)
                        }
                    } else {
                        Button("Load") {
                            onSelectModel()
                        }
                        .font(AppTypography.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }

        do {
            // Use the download model method from RunAnywhere
            // Note: Progress tracking not available in simplified API
            _ = try await RunAnywhere.downloadModel(model.id)

            // Simulate progress completion
            await MainActor.run {
                self.downloadProgress = 1.0
            }

            print("Model \(model.name) downloaded successfully")

            // Notify parent that download completed so it can refresh
            await MainActor.run {
                onDownloadCompleted()
                // Reset download state
                isDownloading = false
                downloadProgress = 1.0
            }

        } catch {
            print("Download failed: \(error)")
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
