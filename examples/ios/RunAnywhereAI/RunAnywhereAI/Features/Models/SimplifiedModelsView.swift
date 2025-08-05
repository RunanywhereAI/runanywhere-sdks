//
//  SimplifiedModelsView.swift
//  RunAnywhereAI
//
//  A simplified models view that demonstrates SDK usage
//

import SwiftUI
import RunAnywhereSDK

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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add Model") {
                    showingAddModelSheet = true
                }
            }
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
        let frameworks = RunAnywhereSDK.shared.getAvailableFrameworks()
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No models available for this framework")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Text("Tap 'Add Model' to add a model from URL")
                            .foregroundColor(.blue)
                            .font(.caption2)
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

private struct FrameworkRow: View {
    let framework: LLMFramework
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: frameworkIcon)
                    .foregroundColor(frameworkColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(framework.displayName)
                        .font(.headline)
                    Text(frameworkDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var frameworkIcon: String {
        switch framework {
        case .foundationModels:
            return "apple.logo"
        case .mediaPipe:
            return "brain.filled.head.profile"
        default:
            return "cpu"
        }
    }

    private var frameworkColor: Color {
        switch framework {
        case .foundationModels:
            return .black
        case .mediaPipe:
            return .blue
        default:
            return .gray
        }
    }

    private var frameworkDescription: String {
        switch framework {
        case .foundationModels:
            return "Apple's on-device language models"
        case .mediaPipe:
            return "Google's cross-platform ML framework"
        default:
            return "Machine learning framework"
        }
    }
}

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
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                HStack(spacing: 8) {
                    let size = model.estimatedMemory
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
                        // For downloaded models without thinking support, show option to enable it
                        Button(action: {
                            // Enable thinking support for this model
                            Task {
                                await RunAnywhereSDK.shared.updateModelThinkingSupport(
                                    modelId: model.id,
                                    supportsThinking: true,
                                    thinkingTagPattern: ThinkingTagPattern.defaultPattern
                                )
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

                // Show download status
                if let _ = model.downloadURL {
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
                if let downloadURL = model.downloadURL, model.localPath == nil {
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
                    }
                } else if model.localPath != nil {
                    // Model is downloaded - show select and load options
                    if isSelected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Loaded")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    } else {
                        Button("Load") {
                            onSelectModel()
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }

        do {
            let downloadTask = try await RunAnywhereSDK.shared.downloadModel(model.id)

            // Track progress
            Task {
                for await progress in downloadTask.progress {
                    await MainActor.run {
                        switch progress.state {
                        case .downloading:
                            self.downloadProgress = Double(progress.bytesDownloaded) / Double(progress.totalBytes)
                        case .completed:
                            self.downloadProgress = 1.0
                        case .failed:
                            self.downloadProgress = 0.0
                        default:
                            break
                        }
                    }
                }
            }

            // Wait for download to complete
            let url = try await downloadTask.result.value

            print("Model \(model.name) downloaded successfully to: \(url)")

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
