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
                ToolbarItemGroup(placement: .topBarLeading) {
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

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Add Model") {
                        showingAddModelSheet = true
                    }
                    .disabled(isLoadingModel)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
        #endif
        .sheet(isPresented: $showingAddModelSheet) {
            AddModelFromURLView(onModelAdded: { modelInfo in
                Task {
                    await viewModel.addImportedModel(modelInfo)
                }
            })
            #if os(macOS)
            .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500)
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
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("Loading Model")
                        .font(.headline)

                    Text(loadingProgress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                #if os(iOS)
                .background(Color(.systemBackground))
                #else
                .background(Color(NSColor.windowBackgroundColor))
                #endif
                .cornerRadius(12)
                .shadow(radius: 10)
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
                .foregroundColor(.secondary)
        }
    }

    private var neuralEngineRow: some View {
        HStack {
            Label("Neural Engine", systemImage: "brain")
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }

    private var loadingDeviceRow: some View {
        HStack {
            ProgressView()
            Text("Loading device info...")
                .foregroundColor(.secondary)
        }
    }

    private var frameworksSection: some View {
        Section("Available Frameworks") {
            if availableFrameworks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                        Text("Loading frameworks...")
                            .foregroundColor(.secondary)
                    }

                    Text("No framework adapters are currently registered. Register framework adapters to see available frameworks.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
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
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iOS 26+ with Apple Intelligence")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No models available for this framework")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        if expanded != .foundationModels {
                            Text("Tap 'Add Model' to add a model from URL")
                                .foregroundColor(.blue)
                                .font(.caption2)
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

            // Call the callback with the loaded model
            await onModelSelected(model)

            // Update the shared view model
            await viewModel.selectModel(model)

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
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                HStack(spacing: 8) {
                    let size = model.memoryRequired ?? 0
                    if size > 0 {
                        Label(
                            ByteCountFormatter.string(fromByteCount: size, countStyle: .memory),
                            systemImage: "memorychip"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }

                    let format = model.format
                    Text(format.rawValue.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)

                    // Show thinking indicator if model supports thinking
                    if model.supportsThinking {
                        HStack(spacing: 2) {
                            Image(systemName: "brain")
                                .font(.caption2)
                            Text("THINKING")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                    } else if model.localPath != nil {
                        Button(action: {
                            Task {
                                // Thinking support update not available in new API
                                // Will be enabled when the model is loaded
                                onModelUpdated()
                            }
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "brain")
                                    .font(.caption2)
                                Text("ENABLE")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Show download status or built-in status
                if model.preferredFramework == .foundationModels {
                    // Foundation Models are built-in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                } else if let _ = model.downloadURL {
                    if model.localPath == nil {
                        HStack(spacing: 4) {
                            if isDownloading {
                                ProgressView(value: downloadProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Available for download")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text("Downloaded")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }
            }

            Spacer()

            // Action buttons based on model state
            HStack(spacing: 8) {
                if model.preferredFramework == .foundationModels {
                    // Foundation Models are built-in, always ready to select
                    Button("Select") {
                        onSelectModel()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading || isSelected)
                } else if let _ = model.downloadURL, model.localPath == nil {
                    // Model needs to be downloaded
                    if isDownloading {
                        VStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.8)
                            if downloadProgress > 0 {
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Button("Download") {
                            Task {
                                await downloadModel()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isLoading)
                    }
                } else if model.localPath != nil {
                    // Model is downloaded - show select button
                    Button("Select") {
                        onSelectModel()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading || isSelected)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isLoading && !isSelected ? 0.6 : 1.0)
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }

        do {
            // Use the download model method from RunAnywhere
            _ = try await RunAnywhere.downloadModel(model.id)

            // Simulate progress completion (progress tracking not available in simplified API)
            await MainActor.run {
                self.downloadProgress = 1.0
            }

            print("Model \(model.name) downloaded successfully")

            await MainActor.run {
                onDownloadCompleted()
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
