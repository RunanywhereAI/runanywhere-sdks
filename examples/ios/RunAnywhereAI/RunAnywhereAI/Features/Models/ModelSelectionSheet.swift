//
//  ModelSelectionSheet.swift
//  RunAnywhereAI
//
//  Reusable model selection sheet that can be used across the app
//

import SwiftUI
import RunAnywhere

struct ModelSelectionSheet: View {
    @StateObject private var viewModel = ModelListViewModel.shared
    @StateObject private var deviceInfo = DeviceInfoService.shared
    @Environment(\.dismiss) var dismiss

    @State private var selectedModel: ModelInfo?
    @State private var expandedFramework: LLMFramework?
    @State private var availableFrameworks: [LLMFramework] = []
    @State private var showingAddModelSheet = false
    @State private var isLoadingModel = false
    @State private var loadingProgress: String = ""

    let onModelSelected: (ModelInfo) async -> Void

    init(onModelSelected: @escaping (ModelInfo) async -> Void) {
        self.onModelSelected = onModelSelected
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mainContentView

                if isLoadingModel {
                    loadingOverlay
                }
            }
            .navigationTitle("Select Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    #if os(iOS)
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoadingModel)
                    #else
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoadingModel)
                    .keyboardShortcut(.escape)
                    #endif
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Add Model") {
                        showingAddModelSheet = true
                    }
                    .disabled(isLoadingModel)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: AppLayout.sheetMinWidth, idealWidth: AppLayout.sheetIdealWidth, minHeight: AppLayout.sheetMinHeight, idealHeight: AppLayout.sheetIdealHeight)
        #endif
        .sheet(isPresented: $showingAddModelSheet) {
            AddModelFromURLView(onModelAdded: { modelInfo in
                Task {
                    await viewModel.addImportedModel(modelInfo)
                }
            })
            #if os(macOS)
            .frame(minWidth: AppLayout.sheetMinWidth, idealWidth: AppLayout.sheetIdealWidth, minHeight: AppLayout.sheetMinHeight, idealHeight: AppLayout.sheetIdealHeight)
            #endif
        }
        .task {
            await loadInitialData()
        }
    }

    private var mainContentView: some View {
        List {
            deviceStatusSection
            frameworksSection
            modelsSection
        }
    }

    private var loadingOverlay: some View {
        AppColors.overlayMedium
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: AppSpacing.xLarge) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("Loading Model")
                        .font(AppTypography.headline)

                    Text(loadingProgress)
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(AppSpacing.xxLarge)
                .background(AppColors.backgroundPrimary)
                .cornerRadius(AppSpacing.cornerRadiusXLarge)
                .shadow(radius: AppSpacing.shadowXLarge)
            }
    }

    private func loadInitialData() async {
        await viewModel.loadModels()
        await loadAvailableFrameworks()
    }

    private func loadAvailableFrameworks() async {
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
            // Filter models based on the expanded framework
            let filteredModels = viewModel.availableModels.filter { model in
                if expanded == .foundationModels {
                    return model.preferredFramework == .foundationModels
                } else {
                    return model.compatibleFrameworks.contains(expanded)
                }
            }

            Section("Models for \(expanded.displayName)") {
                // Show requirements notice for Foundation Models
                if expanded == .foundationModels {
                    HStack(spacing: AppSpacing.smallMedium) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppColors.statusBlue)
                            .font(AppTypography.caption)
                        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                            Text("iOS 26+ with Apple Intelligence")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.xSmall)
                }

                // Show models
                ForEach(filteredModels, id: \.id) { model in
                    SelectableModelRow(
                        model: model,
                        isSelected: selectedModel?.id == model.id,
                        isLoading: isLoadingModel,
                        onDownloadCompleted: {
                            Task {
                                await viewModel.loadModels()
                                await loadAvailableFrameworks()
                            }
                        },
                        onSelectModel: {
                            Task {
                                await selectAndLoadModel(model)
                            }
                        },
                        onModelUpdated: {
                            Task {
                                await viewModel.loadModels()
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

                        if expanded != .foundationModels {
                            Text("Tap 'Add Model' to add a model from URL")
                                .foregroundColor(AppColors.statusBlue)
                                .font(AppTypography.caption2)
                        }
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

    private func selectAndLoadModel(_ model: ModelInfo) async {
        // Foundation Models don't need local path check
        if model.preferredFramework != .foundationModels {
            guard model.localPath != nil else {
                return // Model not downloaded yet
            }
        }

        await MainActor.run {
            isLoadingModel = true
            loadingProgress = "Initializing \(model.name)..."
            selectedModel = model
        }

        do {
            await MainActor.run {
                loadingProgress = "Loading model into memory..."
            }

            // This is where we actually wait for the model to load
            try await RunAnywhere.loadModel(model.id)

            await MainActor.run {
                loadingProgress = "Model loaded successfully!"
            }

            // Wait a moment to show success message
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Update the shared view model first to ensure state consistency
            await viewModel.selectModel(model)

            // Call the callback with the loaded model
            await onModelSelected(model)

            await MainActor.run {
                dismiss()
            }

        } catch {
            await MainActor.run {
                isLoadingModel = false
                loadingProgress = ""
                selectedModel = nil
                // Could show error alert here
            }
            print("Failed to load model: \(error)")
        }
    }

}

// MARK: - Supporting Views

private struct SelectableModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isLoading: Bool
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
                        Button(action: {
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
                            .foregroundColor(AppColors.primaryOrange)
                            .cornerRadius(AppSpacing.cornerRadiusSmall)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Show download status or built-in status
                if model.preferredFramework == .foundationModels {
                    // Foundation Models are built-in
                    HStack(spacing: AppSpacing.xSmall) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.statusGreen)
                            .font(AppTypography.caption2)
                        Text("Built-in")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.statusGreen)
                    }
                } else if let _ = model.downloadURL {
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
                if model.preferredFramework == .foundationModels {
                    // Foundation Models are built-in, always ready to select
                    Button("Select") {
                        onSelectModel()
                    }
                    .font(AppTypography.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading || isSelected)
                } else if let _ = model.downloadURL, model.localPath == nil {
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
                        .disabled(isLoading)
                    }
                } else if model.localPath != nil {
                    // Model is downloaded - show select button
                    Button("Select") {
                        onSelectModel()
                    }
                    .font(AppTypography.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading || isSelected)
                }
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
        .opacity(isLoading && !isSelected ? 0.6 : 1.0)
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }

        do {
            // Use the progress-enabled download API
            let progressStream = try await RunAnywhere.downloadModelWithProgress(model.id)

            // Process progress updates
            for await progress in progressStream {
                await MainActor.run {
                    self.downloadProgress = progress.percentage
                    print("Download progress for \(model.name): \(Int(progress.percentage * 100))%")
                }

                // Check if download completed or failed
                switch progress.state {
                case .completed:
                    await MainActor.run {
                        self.downloadProgress = 1.0
                        self.isDownloading = false
                        onDownloadCompleted()
                        print("Model \(model.name) downloaded successfully")
                    }
                    return

                case .failed(let error):
                    await MainActor.run {
                        self.downloadProgress = 0.0
                        self.isDownloading = false
                        print("Download failed for \(model.name): \(error.localizedDescription)")
                    }
                    return

                default:
                    // Continue processing progress updates
                    continue
                }
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
