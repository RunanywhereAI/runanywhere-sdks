//
//  UnifiedModelDetailsView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import SwiftUI
import RunAnywhereSDK

// Helper function
private func formatSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct UnifiedModelDetailsView: View {
    let model: ModelInfo
    let onDownload: (ModelInfo) -> Void

    @StateObject private var modelURLRegistry = ModelURLRegistry.shared
    @StateObject private var deviceInfoService = DeviceInfoService.shared
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @StateObject private var modelManager = ModelManager.shared

    @State private var showingCompatibilityDetails = false

    private var downloadInfo: ModelInfo? {
        let framework = model.preferredFramework ?? model.compatibleFrameworks.first ?? .foundationModels
        let modelsWithURLs = modelURLRegistry.getAllModels(for: framework)
        return modelsWithURLs.first { downloadInfo in
            downloadInfo.name == model.name ||
                downloadInfo.id == model.id ||
                isModelNameMatch(model.name, downloadInfo.name)
        }
    }

    private var repositoryURL: URL? {
        guard let downloadInfo = downloadInfo else { return nil }

        // Extract repository URL from Hugging Face URLs
        if downloadInfo.downloadURL?.host?.contains("huggingface.co") == true {
            let pathComponents = downloadInfo.downloadURL?.pathComponents ?? []
            if pathComponents.count >= 3 {
                let repo = "\(pathComponents[1])/\(pathComponents[2])"
                return URL(string: "https://huggingface.co/\(repo)")
            }
        }

        return nil
    }

    private var isModelDownloaded: Bool {
        if let downloadInfo = downloadInfo {
            let framework = model.preferredFramework ?? model.compatibleFrameworks.first ?? .foundationModels
            return modelManager.isModelDownloaded(downloadInfo.name, framework: framework)
        }
        let framework = model.preferredFramework ?? model.compatibleFrameworks.first ?? .foundationModels
        return modelManager.isModelDownloaded(model.name, framework: framework)
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

                            Text((model.preferredFramework ?? model.compatibleFrameworks.first ?? .foundationModels).rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    // Status badges
                    HStack(spacing: 8) {
                        StatusBadge(
                            text: isModelDownloaded ? "Downloaded" : "Not Downloaded",
                            systemImage: isModelDownloaded ? "checkmark.circle.fill" : "circle",
                            color: isModelDownloaded ? .green : .orange
                        )

                        StatusBadge(
                            text: !model.compatibleFrameworks.isEmpty ? "Compatible" : "Incompatible",
                            systemImage: !model.compatibleFrameworks.isEmpty ? "checkmark.circle.fill" : "xmark.circle.fill",
                            color: !model.compatibleFrameworks.isEmpty ? .green : .red
                        )

                        if false { // Auth check placeholder
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
                        DetailRow(label: "Format", value: model.format.rawValue)
                        DetailRow(label: "Size", value: formatSize(model.downloadSize ?? model.estimatedMemory))

                        if let quantization = model.metadata?.quantizationLevel {
                            DetailRow(label: "Quantization", value: quantization.rawValue)
                        }

                        if model.contextLength > 0 {
                            DetailRow(label: "Context Length", value: "\(model.contextLength) tokens")
                        }

                        if let localPath = model.localPath {
                            DetailRow(
                                label: "Downloaded File",
                                value: localPath.lastPathComponent,
                                valueColor: .green
                            )
                        } else if let downloadInfo = downloadInfo {
                            DetailRow(
                                label: "File Name",
                                value: downloadInfo.name
                            )
                        }

                        if let downloadInfo = downloadInfo {
                            DetailRow(
                                label: "Download URL",
                                value: downloadInfo.downloadURL?.absoluteString ?? "No URL",
                                isURL: true
                            )

                            if false { // Unzip check placeholder
                                DetailRow(label: "Format", value: "ZIP Archive")
                            }

                            if let notes = downloadInfo.metadata?.description {
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
                            isCompatible: deviceMemory >= model.estimatedMemory,
                            message: ByteCountFormatter.string(fromByteCount: model.estimatedMemory, countStyle: .memory)
                        )

                        CompatibilityRow(
                            title: "Recommended Memory",
                            isCompatible: deviceMemory >= (model.estimatedMemory * 2),
                            message: ByteCountFormatter.string(fromByteCount: model.estimatedMemory * 2, countStyle: .memory)
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
                            isCompatible: true,
                            message: (model.preferredFramework ?? model.compatibleFrameworks.first ?? .foundationModels).rawValue
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
                    if !isModelDownloaded, let downloadInfo = downloadInfo {
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

                    if isModelDownloaded {
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
    let valueColor: Color?

    init(label: String, value: String, isURL: Bool = false, valueColor: Color? = nil) {
        self.label = label
        self.value = value
        self.isURL = isURL
        self.valueColor = valueColor
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
                    .foregroundColor(valueColor ?? .primary)
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
                id: "test-model-id",
                name: "Test Model",
                format: .gguf,
                downloadURL: nil,
                localPath: nil,
                estimatedMemory: 1_200_000_000,
                contextLength: 2048,
                downloadSize: 1_200_000_000,
                checksum: nil,
                compatibleFrameworks: [.coreML],
                preferredFramework: .coreML,
                hardwareRequirements: [],
                tokenizerFormat: nil,
                metadata: nil,
                alternativeDownloadURLs: []
            )
        )            { _ in }
    }
}
