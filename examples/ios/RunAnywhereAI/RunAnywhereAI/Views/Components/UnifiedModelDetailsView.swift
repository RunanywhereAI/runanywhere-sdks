//
//  UnifiedModelDetailsView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import SwiftUI

struct UnifiedModelDetailsView: View {
    let model: ModelInfo
    let onDownload: (ModelDownloadInfo) -> Void
    
    @StateObject private var modelURLRegistry = ModelURLRegistry.shared
    @StateObject private var deviceInfoService = DeviceInfoService.shared
    @StateObject private var downloadManager = ModelDownloadManager.shared
    
    @State private var showingCompatibilityDetails = false
    
    private var downloadInfo: ModelDownloadInfo? {
        let modelsWithURLs = modelURLRegistry.getAllModels(for: model.framework)
        return modelsWithURLs.first { downloadInfo in
            downloadInfo.name == model.name || 
            downloadInfo.id == model.id ||
            isModelNameMatch(model.name, downloadInfo.name)
        }
    }
    
    private var repositoryURL: URL? {
        guard let downloadInfo = downloadInfo else { return nil }
        
        // Extract repository URL from Hugging Face URLs
        if downloadInfo.url.host?.contains("huggingface.co") == true {
            let pathComponents = downloadInfo.url.pathComponents
            if pathComponents.count >= 3 {
                let repo = "\(pathComponents[1])/\(pathComponents[2])"
                return URL(string: "https://huggingface.co/\(repo)")
            }
        }
        
        return nil
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: frameworkIcon)
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(model.framework.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Status badges
                    HStack(spacing: 8) {
                        StatusBadge(
                            text: model.isLocal ? "Downloaded" : "Not Downloaded",
                            systemImage: model.isLocal ? "checkmark.circle.fill" : "circle",
                            color: model.isLocal ? .green : .orange
                        )
                        
                        StatusBadge(
                            text: model.isCompatible ? "Compatible" : "Incompatible",
                            systemImage: model.isCompatible ? "checkmark.circle.fill" : "xmark.circle.fill",
                            color: model.isCompatible ? .green : .red
                        )
                        
                        if downloadInfo?.requiresAuth == true {
                            StatusBadge(
                                text: "Auth Required",
                                systemImage: "lock.fill",
                                color: .orange
                            )
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                // Model Details Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Model Details")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        DetailRow(label: "Format", value: model.format.displayName)
                        DetailRow(label: "Size", value: model.displaySize)
                        
                        if let quantization = model.quantization {
                            DetailRow(label: "Quantization", value: quantization)
                        }
                        
                        if let contextLength = model.contextLength {
                            DetailRow(label: "Context Length", value: "\(contextLength) tokens")
                        }
                        
                        if let downloadInfo = downloadInfo {
                            DetailRow(
                                label: "Download URL",
                                value: downloadInfo.url.absoluteString,
                                isURL: true
                            )
                            
                            if downloadInfo.requiresUnzip {
                                DetailRow(label: "Format", value: "ZIP Archive")
                            }
                            
                            if let notes = downloadInfo.notes {
                                DetailRow(label: "Notes", value: notes)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                // Compatibility Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Device Compatibility")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: {
                            showingCompatibilityDetails = true
                        }) {
                            Text("View Details")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    VStack(spacing: 12) {
                        CompatibilityRow(
                            title: "Memory Required",
                            isCompatible: deviceMemory >= model.minimumMemory,
                            message: ByteCountFormatter.string(fromByteCount: model.minimumMemory, countStyle: .memory)
                        )
                        
                        CompatibilityRow(
                            title: "Recommended Memory",
                            isCompatible: deviceMemory >= model.recommendedMemory,
                            message: ByteCountFormatter.string(fromByteCount: model.recommendedMemory, countStyle: .memory)
                        )
                        
                        if let deviceInfo = deviceInfoService.deviceInfo {
                            CompatibilityRow(
                                title: "Neural Engine",
                                isCompatible: deviceInfo.neuralEngineAvailable,
                                message: deviceInfo.neuralEngineAvailable ? "Available" : "Not Available"
                            )
                        }
                        
                        CompatibilityRow(
                            title: "Framework Support",
                            isCompatible: !model.framework.isDeferred,
                            message: model.framework.displayName
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                // Repository Section
                if let repoURL = repositoryURL {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Repository")
                            .font(.headline)
                        
                        Link(destination: repoURL) {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("View on Hugging Face")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                    
                                    Text(repoURL.absoluteString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                
                // Action Buttons
                VStack(spacing: 12) {
                    if !model.isLocal, let downloadInfo = downloadInfo {
                        Button(action: {
                            onDownload(downloadInfo)
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download Model")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(downloadManager.activeDownloads.keys.contains(model.id))
                    }
                    
                    if model.isLocal {
                        Button(action: {
                            // TODO: Implement model loading
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Load Model")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(model.isCompatible ? Color.green : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(!model.isCompatible)
                    }
                }
                .padding()
            }
            .padding()
        }
        .navigationTitle("Model Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCompatibilityDetails) {
            NavigationView {
                ModelCompatibilityView(model: model, framework: model.framework)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingCompatibilityDetails = false
                            }
                        }
                    }
            }
        }
    }
    
    private var frameworkIcon: String {
        switch model.framework {
        case .coreML: return "brain.head.profile"
        case .mlx: return "cube.fill"
        case .onnxRuntime: return "cpu.fill"
        case .tensorFlowLite: return "square.stack.3d.up.fill"
        case .foundationModels: return "sparkles"
        default: return "cube"
        }
    }
    
    private var deviceMemory: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }
    
    private func isModelNameMatch(_ modelName: String, _ downloadName: String) -> Bool {
        let modelLower = modelName.lowercased()
        let downloadLower = downloadName.lowercased()
        
        let patterns = ["phi", "tinyllama", "llama-3.2", "mistral", "gemma", "qwen"]
        for pattern in patterns {
            if modelLower.contains(pattern) && downloadLower.contains(pattern) {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Supporting Views

struct StatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(8)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let isURL: Bool
    
    init(label: String, value: String, isURL: Bool = false) {
        self.label = label
        self.value = value
        self.isURL = isURL
    }
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            if isURL, let url = URL(string: value) {
                Link(destination: url) {
                    Text(value)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.leading)
                }
            } else {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
    }
}

// Using existing CompatibilityRow from ModelCompatibilityView.swift

#Preview {
    NavigationView {
        UnifiedModelDetailsView(
            model: ModelInfo(
                name: "Test Model",
                format: .gguf,
                size: "1.2GB",
                framework: .coreML,
                quantization: "Q4_K_M",
                isLocal: false,
                description: "A test model for preview"
            ),
            onDownload: { _ in }
        )
    }
}