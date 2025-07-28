//
//  ModelDownloadView.swift
//  RunAnywhereAI
//

import SwiftUI

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @StateObject private var modelURLRegistry = ModelURLRegistry.shared
    @State private var selectedModelInfo: ModelDownloadInfo?
    @State private var selectedFramework: LLMFramework = .coreML
    @State private var isDownloading = false
    @State private var downloadProgress: DownloadProgress?
    @State private var downloadError: Error?
    @State private var showingError = false
    @State private var showingProgressView = false
    @State private var isValidatingURLs = false
    @State private var showingKaggleAuth = false
    @State private var selectedKaggleModel: ModelDownloadInfo?
    @State private var showingCustomURL = false
    @State private var selectedUnavailableModel: ModelDownloadInfo?

    // Get models from centralized registry
    private var availableModels: [ModelDownloadInfo] {
        let registry = ModelURLRegistry.shared
        return registry.getAllModels(for: selectedFramework)
    }

    var body: some View {
        NavigationView {
            VStack {
                frameworkPicker
                modelListSection
                downloadButtonSection
            }
            .navigationTitle("Download Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Refresh URLs") {
                        validateURLs()
                    }
                    .disabled(isValidatingURLs)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Download Error", isPresented: $showingError) {
                Button("OK") {
                    downloadError = nil
                }
            } message: {
                Text(downloadError?.localizedDescription ?? "Unknown error")
            }
            .fullScreenCover(isPresented: $showingProgressView) {
                if let selectedModel = selectedModelInfo {
                    ModelDownloadProgressView(
                        model: createModelInfo(from: selectedModel),
                        downloadInfo: selectedModel,
                        isPresented: $showingProgressView
                    )
                }
            }
            .onAppear {
                validateURLs()
            }
            .sheet(isPresented: $showingKaggleAuth) {
                if let kaggleModel = selectedKaggleModel {
                    KaggleAuthView(
                        model: kaggleModel,
                        onSuccess: {
                            showingKaggleAuth = false
                            selectedModelInfo = kaggleModel
                            showingProgressView = true
                        },
                        onCancel: {
                            showingKaggleAuth = false
                            selectedKaggleModel = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showingCustomURL) {
                if let unavailableModel = selectedUnavailableModel {
                    CustomURLDialog(
                        model: unavailableModel,
                        onSuccess: { customURL in
                            showingCustomURL = false
                            addCustomModel(unavailableModel, with: customURL)
                            selectedUnavailableModel = nil
                        },
                        onCancel: {
                            showingCustomURL = false
                            selectedUnavailableModel = nil
                        }
                    )
                }
            }
        }
    }

    private func downloadSelectedModel() {
        guard let modelInfo = selectedModelInfo else { return }
        
        // Check if model is unavailable
        if modelInfo.isUnavailable {
            selectedUnavailableModel = modelInfo
            showingCustomURL = true
        }
        // Check if this model requires Kaggle authentication
        else if modelInfo.requiresAuth && modelInfo.url.host?.contains("kaggle") == true {
            selectedKaggleModel = modelInfo
            showingKaggleAuth = true
        } else {
            // Regular download flow
            showingProgressView = true
        }
    }
    
    private func addCustomModel(_ originalModel: ModelDownloadInfo, with customURL: URL) {
        // Add the custom model to the registry
        let customModel = ModelDownloadInfo(
            id: "\(originalModel.id)-custom",
            name: "\(originalModel.name) (Custom URL)",
            url: customURL,
            sha256: originalModel.sha256,
            requiresUnzip: originalModel.requiresUnzip,
            requiresAuth: false,
            notes: "Custom URL provided by user"
        )
        
        modelURLRegistry.addCustomModel(customModel)
        
        // Select the custom model for download
        selectedModelInfo = customModel
        showingProgressView = true
    }
    
    private func validateURLs() {
        isValidatingURLs = true
        Task {
            await modelURLRegistry.validateURLs(for: selectedFramework)
            await MainActor.run {
                isValidatingURLs = false
            }
        }
    }
    
    private func createModelInfo(from downloadInfo: ModelDownloadInfo) -> ModelInfo {
        // Convert ModelDownloadInfo to ModelInfo for the progress view
        let format = ModelFormat.from(extension: downloadInfo.url.pathExtension)
        let framework = LLMFramework.forFormat(format)
        
        return ModelInfo(
            id: downloadInfo.id,
            name: downloadInfo.name,
            format: format,
            size: "Unknown", // Will be determined during download
            framework: framework,
            downloadURL: downloadInfo.url
        )
    }
    
    private func getButtonTitle() -> String {
        guard let model = selectedModelInfo else { return "Download Model" }
        
        let isModelDownloaded = ModelManager.shared.isModelDownloaded(model.name)
        
        if model.isBuiltIn {
            return "Setup Model"
        } else if model.isUnavailable {
            return "Add Custom URL"
        } else if isModelDownloaded {
            return "Downloaded"
        } else {
            return "Download Model"
        }
    }
    
    private func getButtonIcon() -> String {
        guard let model = selectedModelInfo else { return "arrow.down.circle.fill" }
        
        let isModelDownloaded = ModelManager.shared.isModelDownloaded(model.name)
        
        if model.isBuiltIn {
            return "apple.logo"
        } else if model.isUnavailable {
            return "link.circle.fill"
        } else if isModelDownloaded {
            return "checkmark.circle.fill"
        } else {
            return "arrow.down.circle.fill"
        }
    }
    
    // MARK: - View Components
    
    private var frameworkPicker: some View {
        VStack {
            HStack {
                Picker("Framework", selection: $selectedFramework) {
                    ForEach(LLMFramework.availableFrameworks.filter { !$0.isDeferred }, id: \.self) { framework in
                        Text(framework.displayName).tag(framework)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedFramework) { oldValue, newValue in
                    selectedModelInfo = nil // Clear selection when framework changes
                    validateURLs()
                }
                
                if isValidatingURLs {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, 8)
                }
            }
            
            if isValidatingURLs {
                Text("Validating model URLs...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var modelListSection: some View {
        if availableModels.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("No models available")
                    .font(.title2)
                    .foregroundColor(.secondary)

                if selectedFramework == .foundationModels {
                    Text("Foundation Models are built into iOS/macOS and don't require downloads")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Models for \(selectedFramework.displayName) can be added via Settings → Model URLs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(availableModels) { model in
                    ModelDownloadRow(
                        model: model,
                        isSelected: selectedModelInfo?.id == model.id,
                        isDownloaded: ModelManager.shared.isModelDownloaded(model.name),
                        onTap: {
                            selectedModelInfo = model
                        }
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private var downloadButtonSection: some View {
        if selectedModelInfo != nil {
            HStack {
                if let progress = downloadProgress {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Downloading...")
                                .font(.caption)
                            Spacer()
                            Text("\(Int(progress.fractionCompleted * 100))%")
                                .font(.caption.monospacedDigit())
                        }

                        ProgressView(value: progress.fractionCompleted)

                        HStack {
                            Text(formatSpeed(progress.downloadSpeed))
                                .font(.caption2)
                            Spacer()
                            if let time = progress.estimatedTimeRemaining {
                                Text(formatTimeRemaining(time))
                                    .font(.caption2)
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    let isModelDownloaded = selectedModelInfo != nil && ModelManager.shared.isModelDownloaded(selectedModelInfo!.name)
                    
                    Button(action: downloadSelectedModel) {
                        Label(getButtonTitle(), systemImage: getButtonIcon())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading || isModelDownloaded)
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: seconds) ?? ""
    }
}

// MARK: - Model Download Row

struct ModelDownloadRow: View {
    let model: ModelDownloadInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        // Download status
                        if isDownloaded {
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        
                        // Built-in model indicator
                        if model.isBuiltIn {
                            Label("Built-in", systemImage: "apple.logo")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        // Auth requirement with Kaggle-specific info
                        if model.requiresAuth {
                            if model.url.host?.contains("kaggle") == true {
                                let authService = KaggleAuthService.shared
                                if authService.isAuthenticated {
                                    Label("Kaggle: Authenticated", systemImage: "checkmark.shield.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Label("Kaggle: Auth Required", systemImage: "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            } else {
                                Label("Requires Auth", systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        // URL validity indicator
                        if !model.isBuiltIn {
                            if model.isURLValid {
                                Label("Available", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else if model.isUnavailable {
                                Label("Unavailable", systemImage: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Label("URL Broken", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    // Show notes if available
                    if let notes = model.notes {
                        Text(notes)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!model.isURLValid && !model.isBuiltIn && !isDownloaded)
        .opacity((!model.isURLValid && !model.isBuiltIn && !isDownloaded) ? 0.6 : 1.0)
    }
}

#Preview {
    ModelDownloadView()
}
