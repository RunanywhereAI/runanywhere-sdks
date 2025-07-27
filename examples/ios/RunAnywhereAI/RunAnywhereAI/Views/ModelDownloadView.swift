//
//  ModelDownloadView.swift
//  RunAnywhereAI
//

import SwiftUI

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @State private var selectedModel: ModelInfo?
    @State private var selectedFramework: LLMFramework = .coreML
    @State private var isDownloading = false
    @State private var downloadProgress: DownloadProgress?
    @State private var downloadError: Error?
    @State private var showingError = false
    
    // Get models from centralized registry
    private var availableModels: [ModelInfo] {
        let registry = ModelURLRegistry.shared
        let downloadInfos = registry.getAllModels(for: selectedFramework)
        
        return downloadInfos.map { info in
            // Convert download info to ModelInfo for display
            let format = getFormat(for: selectedFramework, name: info.name)
            let size = estimateSize(for: info.name)
            
            return ModelInfo(
                id: info.id,
                name: info.name,
                format: format,
                size: size,
                framework: selectedFramework,
                downloadURL: info.url,
                description: getDescription(for: info.id)
            )
        }
    }
    
    private let frameworks: [LLMFramework] = [.coreML, .mlx, .onnxRuntime, .tensorFlowLite, .llamaCpp]
    
    var body: some View {
        NavigationView {
            VStack {
                if isDownloading {
                    downloadingView
                } else {
                    modelSelectionView
                }
            }
            .navigationTitle("Download Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isDownloading)
                }
            }
            .alert("Download Error", isPresented: $showingError, presenting: downloadError) { _ in
                Button("OK") {
                    downloadError = nil
                    isDownloading = false
                }
            } message: { error in
                Text(error.localizedDescription)
            }
        }
    }
    
    private var modelSelectionView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Framework Picker
                Picker("Framework", selection: $selectedFramework) {
                    ForEach(frameworks, id: \.self) { framework in
                        Text(framework.displayName).tag(framework)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                Text("Select a model to download")
                    .font(.headline)
                    .padding(.top)
                
                if availableModels.isEmpty {
                    Text("No models available for \(selectedFramework.displayName)")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(availableModels) { model in
                        ModelDownloadCard(
                            model: model,
                            isSelected: selectedModel?.id == model.id,
                            isDownloading: downloadManager.activeDownloads[model.id] != nil
                        ) {
                            selectedModel = model
                        }
                    }
                }
                
                if selectedModel != nil {
                    Button(action: startDownload) {
                        Text("Download Model")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
            }
            .padding()
        }
    }
    
    private var downloadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            if let model = selectedModel {
                Text("Downloading \(model.name)")
                    .font(.headline)
                
                Text(model.size)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let progress = downloadProgress {
                ProgressView(value: progress.fractionCompleted) {
                    Text(ModelDownloadManager.formatProgress(progress))
                        .font(.caption)
                }
                .progressViewStyle(LinearProgressViewStyle())
                .padding(.horizontal, 40)
            
            Text("Please keep the app open during download")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private func startDownload() {
        guard let model = selectedModel else { return }
        
        isDownloading = true
        
        Task {
            do {
                let modelsDir = ModelManager.modelsDirectory.appendingPathComponent(model.framework.rawValue)
                
                let destinationURL = try await downloadManager.downloadModel(
                    model,
                    to: modelsDir
                ) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                
                // Update model path
                var downloadedModel = model
                downloadedModel.path = destinationURL.path
                downloadedModel.isLocal = true
                
                // Add to model manager
                await ModelManager.shared.addImportedModel(downloadedModel)
                await ModelManager.shared.refreshModelList()
                
                // Dismiss
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    downloadError = error
                    showingError = true
                    isDownloading = false
                }
            }
        }
    }
}

struct ModelDownloadCard: View {
    let model: ModelInfo
    let isSelected: Bool
    let isDownloading: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(model.size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                        .font(.title2)
                }
                
                Text(model.description ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Label(model.format.displayName, systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if isDownloading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}

// MARK: - Helper Methods

extension ModelDownloadView {
    private func getFormat(for framework: LLMFramework, name: String) -> ModelFormat {
        switch framework {
        case .coreML:
            return name.contains(".mlpackage") ? .mlPackage : .coreML
        case .mlx:
            return .mlx
        case .onnxRuntime:
            return .onnxRuntime
        case .tensorFlowLite:
            return .tflite
        case .llamaCpp:
            return .gguf
        default:
            return .other
        }
    }
    
    private func estimateSize(for name: String) -> String {
        // Estimate based on model name patterns
        if name.contains("7b") || name.contains("7B") {
            return "3.5GB"
        } else if name.contains("3b") || name.contains("3B") {
            return "1.7GB"
        } else if name.contains("2b") || name.contains("2B") {
            return "1.2GB"
        } else if name.contains("1b") || name.contains("1B") {
            return "600MB"
        } else if name.contains("gpt2") {
            return "548MB"
        } else if name.contains("distil") {
            return "267MB"
        }
        return "1GB"
    }
    
    private func getDescription(for modelId: String) -> String {
        switch modelId {
        case "gpt2-coreml":
            return "GPT-2 model optimized for Core ML with Neural Engine acceleration"
        case "distilgpt2-coreml":
            return "Smaller, faster GPT-2 variant optimized for mobile devices"
        case "openelm-270m-coreml":
            return "Apple's efficient 270M parameter model for on-device inference"
        case "mistral-7b-mlx-4bit":
            return "Mistral 7B with 4-bit quantization for Apple Silicon"
        case "llama-3.2-3b-mlx":
            return "Meta's latest 3B model optimized for MLX"
        case "phi-3-mini-onnx":
            return "Microsoft's efficient small language model"
        case "gemma-2b-tflite":
            return "Google's Gemma 2B optimized for mobile deployment"
        case "tinyllama-1.1b-gguf":
            return "Compact 1.1B model perfect for testing"
        default:
            return "Language model for on-device inference"
        }
    }
}

struct ModelDownloadView_Previews: PreviewProvider {
    static var previews: some View {
        ModelDownloadView()
    }
}
