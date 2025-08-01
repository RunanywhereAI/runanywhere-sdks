//
//  UnifiedModelRow.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import SwiftUI

struct UnifiedModelRow: View {
    let model: ModelInfo
    let framework: LLMFramework
    let onTap: () -> Void
    let onDownload: (ModelInfo) -> Void
    let viewModel: ModelListViewModel

    @State private var showingNoURLAlert = false
    @State private var showingDownloadConfirmation = false
    @State private var selectedModelInfo: ModelInfo?

    @StateObject private var modelURLRegistry = ModelURLRegistry.shared
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @StateObject private var modelManager = ModelManager.shared

    private var downloadableModel: ModelInfo? {
        let registry = ModelURLRegistry.shared
        let modelsWithURLs = registry.getAllModels(for: framework)

        return modelsWithURLs.first { modelInfo in
            // Try exact matches first
            if modelInfo.name == model.name || modelInfo.id == model.id {
                return true
            }

            // Try fuzzy matching
            let modelNameLower = model.name.lowercased()
            let downloadNameLower = modelInfo.name.lowercased()

            // Common patterns for model name matching
            let patterns = ["phi", "tinyllama", "llama-3.2", "mistral", "gemma", "qwen"]
            for pattern in patterns {
                if modelNameLower.contains(pattern) && downloadNameLower.contains(pattern) {
                    return true
                }
            }

            return false
        }
    }

    private var isDownloading: Bool {
        downloadManager.activeDownloads.keys.contains(model.id)
    }

    private var isModelDownloaded: Bool {
        if let downloadableModel = downloadableModel {
            return modelManager.isModelDownloaded(downloadableModel.name, framework: framework)
        }
        return modelManager.isModelDownloaded(model.name, framework: framework)
    }

    private var effectiveModelType: ModelType {
        // Use modelType from downloadableModel if available, otherwise from model
        return downloadableModel?.modelType ?? model.modelType ?? .text
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Model icon
                Image(systemName: isModelDownloaded ? "checkmark.circle.fill" : "doc.fill")
                    .font(.title3)
                    .foregroundColor(isModelDownloaded ? .green : .secondary)
                    .frame(width: 40)

                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        // Model type indicator
                        Image(systemName: effectiveModelType.icon)
                            .font(.caption)
                            .foregroundColor(effectiveModelType.supportedInChat ? .blue : .orange)
                            .help(effectiveModelType.rawValue)
                    }

                    // Status indicators
                    VStack(alignment: .leading, spacing: 6) {
                        // First row: Type and size
                        HStack(spacing: 8) {
                            // Model type badge
                            Text(effectiveModelType.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(effectiveModelType.supportedInChat ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                                .foregroundColor(effectiveModelType.supportedInChat ? .blue : .orange)
                                .cornerRadius(4)

                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(model.displaySize)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Quantization
                            if let quantization = model.quantization {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(quantization)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        // Second row: Status badges
                        HStack(spacing: 8) {
                            // Compatibility
                            if model.isCompatible {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    Text("Compatible")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }

                            // Download status
                            if isModelDownloaded {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    Text("Downloaded")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            } else if downloadableModel != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    Text("Available")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }

                            Spacer()
                        }
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    // Download progress or button
                    if isDownloading {
                        if let progress = downloadManager.activeDownloads[model.id] {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(progress.fractionCompleted * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                ProgressView(value: progress.fractionCompleted)
                                    .frame(width: 40)
                                    .scaleEffect(0.8)
                            }
                        } else {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    } else if !isModelDownloaded {
                        // Download button
                        Button(action: {
                            if let downloadableModel = downloadableModel {
                                selectedModelInfo = downloadableModel
                                showingDownloadConfirmation = true
                            } else {
                                showingNoURLAlert = true
                            }
                        }) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Show status for local models
                    if isModelDownloaded {
                        if !effectiveModelType.supportedInChat {
                            // Coming Soon badge for unsupported model types
                            VStack(spacing: 2) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("Coming Soon")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 8)
                        } else {
                            // Ready to use indicator
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDownloadConfirmation) {
            if let modelInfo = selectedModelInfo {
                ModelDownloadConfirmationView(
                    model: model
                ) { confirmedModelInfo in
                    onDownload(confirmedModelInfo)
                    showingDownloadConfirmation = false
                }
            }
        }
        .alert("No Download URL Available", isPresented: $showingNoURLAlert) {
            Button("OK", role: .cancel) { }
            Button("Add Custom URL") {
                // TODO: Implement custom URL addition
            }
        } message: {
            Text("This model doesn't have a pre-configured download URL. You can add a custom URL in Settings.")
        }
    }
}

// MARK: - Download Only Model Row

struct DownloadOnlyModelRow: View {
    let modelInfo: ModelInfo
    let onDownload: () -> Void

    @StateObject private var downloadManager = ModelDownloadManager.shared

    private var isDownloaded: Bool {
        // Try to determine framework from modelInfo
        let framework = modelInfo.framework
        return ModelManager.shared.isModelDownloaded(modelInfo.name, framework: framework)
    }

    private var isDownloading: Bool {
        downloadManager.activeDownloads.keys.contains(modelInfo.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Model icon
            Image(systemName: modelInfo.isLocal ? "apple.logo" : (isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle"))
                .font(.title3)
                .foregroundColor(modelInfo.isLocal ? .blue : (isDownloaded ? .green : .orange))
                .frame(width: 40)

            // Model info
            VStack(alignment: .leading, spacing: 4) {
                Text(modelInfo.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Status indicators
                HStack(spacing: 8) {
                    // Download status
                    if isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if modelInfo.isLocal {
                        Label("Built-in", systemImage: "apple.logo")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if modelInfo.downloadURL != nil {
                        Label("Available", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("URL Issue", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // Additional info - show file format
                    Text("•")
                        .foregroundColor(.secondary)
                    Label(modelInfo.format.rawValue.uppercased(), systemImage: "doc.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Model size
                Text(modelInfo.displaySize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action button
            if isDownloading {
                if let progress = downloadManager.activeDownloads[modelInfo.id] {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(progress.fractionCompleted * 100))%")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        ProgressView(value: progress.fractionCompleted)
                            .frame(width: 40)
                            .scaleEffect(0.8)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            } else if !isDownloaded {
                Button(action: onDownload) {
                    if modelInfo.isLocal {
                        Image(systemName: "apple.logo")
                            .font(.title2)
                            .foregroundColor(.blue)
                    } else if modelInfo.downloadURL == nil {
                        Image(systemName: "link.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .disabled(modelInfo.downloadURL == nil && !modelInfo.isLocal && !isDownloaded)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDownloaded && !isDownloading {
                onDownload()
            }
        }
        .opacity((modelInfo.downloadURL == nil && !modelInfo.isLocal && !isDownloaded) ? 0.6 : 1.0)
    }
}

#Preview {
    VStack {
        UnifiedModelRow(
            model: ModelInfo(
                name: "Test Model",
                format: .gguf,
                size: "1.2GB",
                framework: .coreML,
                quantization: "Q4_K_M",
                isLocal: false
            ),
            framework: .coreML,
            onTap: {},
            onDownload: { _ in },
            viewModel: ModelListViewModel()
        )

        DownloadOnlyModelRow(
            modelInfo: ModelInfo(
                name: "Test Download Model",
                format: .gguf,
                size: "2.1GB",
                framework: .llamaCpp,
                isLocal: false,
                downloadURL: URL(string: "https://example.com/model.gguf")
            )
        ) {}
    }
    .padding()
}
