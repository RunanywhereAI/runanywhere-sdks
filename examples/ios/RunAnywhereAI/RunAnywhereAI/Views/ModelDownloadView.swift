//
//  ModelDownloadView.swift
//  RunAnywhereAI
//

import SwiftUI

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedModel: DownloadableModel?
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadError: Error?
    @State private var showingError = false
    
    // Sample downloadable models
    let availableModels = [
        DownloadableModel(
            id: "tinyllama-1.1b",
            name: "TinyLlama 1.1B",
            description: "Small but capable model, perfect for testing",
            size: "550MB",
            format: .gguf,
            url: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")!
        ),
        DownloadableModel(
            id: "phi-3-mini",
            name: "Phi-3 Mini",
            description: "Microsoft's efficient 3.8B parameter model",
            size: "1.5GB",
            format: .gguf,
            url: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf")!
        ),
        DownloadableModel(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            description: "Meta's latest small language model",
            size: "1.7GB",
            format: .gguf,
            url: URL(string: "https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct-GGUF/resolve/main/llama-3.2-3b-instruct-q4_k_m.gguf")!
        )
    ]
    
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
                Text("Select a model to download")
                    .font(.headline)
                    .padding(.top)
                
                ForEach(availableModels) { model in
                    ModelDownloadCard(
                        model: model,
                        isSelected: selectedModel?.id == model.id,
                        onSelect: {
                            selectedModel = model
                        }
                    )
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
            
            ProgressView(value: downloadProgress) {
                Text("\(Int(downloadProgress * 100))%")
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
        downloadProgress = 0
        
        Task {
            do {
                let modelManager = ModelManager.shared
                let destinationPath = try await modelManager.downloadModel(
                    from: model.url,
                    modelName: model.fileName,
                    progress: { progress in
                        Task { @MainActor in
                            downloadProgress = progress
                        }
                    }
                )
                
                // Create model info
                let modelInfo = ModelInfo(
                    id: model.id,
                    name: model.name,
                    path: destinationPath.path,
                    format: model.format,
                    size: model.size,
                    framework: .llamaCpp // Default to llama.cpp for GGUF
                )
                
                // Add to model list
                await ModelListViewModel.shared.addDownloadedModel(modelInfo)
                
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
    let model: DownloadableModel
    let isSelected: Bool
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
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Label(model.format.displayName, systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
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

struct DownloadableModel: Identifiable {
    let id: String
    let name: String
    let description: String
    let size: String
    let format: ModelFormat
    let url: URL
    
    var fileName: String {
        return url.lastPathComponent
    }
}

struct ModelDownloadView_Previews: PreviewProvider {
    static var previews: some View {
        ModelDownloadView()
    }
}