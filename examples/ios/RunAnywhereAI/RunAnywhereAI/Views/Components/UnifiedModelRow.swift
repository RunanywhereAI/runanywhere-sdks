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
    let onDownload: (ModelDownloadInfo) -> Void
    let viewModel: ModelListViewModel

    @State private var isLoading = false
    @State private var showingNoURLAlert = false
    @State private var showingDownloadConfirmation = false
    @State private var selectedDownloadInfo: ModelDownloadInfo?

    @StateObject private var modelURLRegistry = ModelURLRegistry.shared
    @StateObject private var downloadManager = ModelDownloadManager.shared

    private var downloadInfo: ModelDownloadInfo? {
        let registry = ModelURLRegistry.shared
        let modelsWithURLs = registry.getAllModels(for: framework)

        return modelsWithURLs.first { downloadInfo in
            // Try exact matches first
            if downloadInfo.name == model.name || downloadInfo.id == model.id {
                return true
            }

            // Try fuzzy matching
            let modelNameLower = model.name.lowercased()
            let downloadNameLower = downloadInfo.name.lowercased()

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

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Model icon
                Image(systemName: model.isLocal ? "checkmark.circle.fill" : "doc.fill")
                    .font(.title3)
                    .foregroundColor(model.isLocal ? .green : .secondary)
                    .frame(width: 40)

                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    // Status indicators
                    HStack(spacing: 8) {
                        // Size
                        Text(model.displaySize)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Quantization
                        if let quantization = model.quantization {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(quantization)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Compatibility
                        if model.isCompatible {
                            Text("•")
                                .foregroundColor(.secondary)
                            Label("Compatible", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("•")
                                .foregroundColor(.secondary)
                            Label("Incompatible", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        // Download status
                        if model.isLocal {
                            Text("•")
                                .foregroundColor(.secondary)
                            Label("Downloaded", systemImage: "checkmark.icloud.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else if downloadInfo != nil {
                            Text("•")
                                .foregroundColor(.secondary)
                            Label("Available", systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
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
                    } else if !model.isLocal {
                        // Download button
                        Button(action: {
                            if let downloadInfo = downloadInfo {
                                selectedDownloadInfo = downloadInfo
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

                    // Load button for local models
                    if model.isLocal {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Button(action: {
                                Task {
                                    isLoading = true
                                    await viewModel.loadModel(model)
                                    isLoading = false
                                }
                            }) {
                                Text("Load")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(model.isCompatible ? Color.blue : Color.gray)
                                    .cornerRadius(15)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(!model.isCompatible || isLoading)
                        }
                    }
                }
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDownloadConfirmation) {
            if let downloadInfo = selectedDownloadInfo {
                ModelDownloadConfirmationView(
                    model: model
                )                    { confirmedDownloadInfo in
                        onDownload(confirmedDownloadInfo)
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
    let downloadInfo: ModelDownloadInfo
    let onDownload: () -> Void

    @StateObject private var downloadManager = ModelDownloadManager.shared

    private var isDownloaded: Bool {
        ModelManager.shared.isModelDownloaded(downloadInfo.name)
    }

    private var isDownloading: Bool {
        downloadManager.activeDownloads.keys.contains(downloadInfo.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Model icon
            Image(systemName: downloadInfo.isBuiltIn ? "apple.logo" : (isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle"))
                .font(.title3)
                .foregroundColor(downloadInfo.isBuiltIn ? .blue : (isDownloaded ? .green : .orange))
                .frame(width: 40)

            // Model info
            VStack(alignment: .leading, spacing: 4) {
                Text(downloadInfo.name)
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
                    } else if downloadInfo.isBuiltIn {
                        Label("Built-in", systemImage: "apple.logo")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if downloadInfo.requiresAuth {
                        if downloadInfo.url.host?.contains("kaggle") == true {
                            let authService = KaggleAuthService.shared
                            if authService.isAuthenticated {
                                Label("Kaggle: Ready", systemImage: "checkmark.shield.fill")
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
                    } else if downloadInfo.isURLValid {
                        Label("Available", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if downloadInfo.isUnavailable {
                        Label("Unavailable", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Label("URL Issue", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // Additional info
                    if downloadInfo.requiresUnzip {
                        Text("•")
                            .foregroundColor(.secondary)
                        Label("ZIP", systemImage: "archivebox")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Notes
                if let notes = downloadInfo.notes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Action button
            if isDownloading {
                if let progress = downloadManager.activeDownloads[downloadInfo.id] {
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
                    if downloadInfo.isBuiltIn {
                        Image(systemName: "apple.logo")
                            .font(.title2)
                            .foregroundColor(.blue)
                    } else if downloadInfo.isUnavailable {
                        Image(systemName: "link.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .disabled(!downloadInfo.isURLValid && !downloadInfo.isBuiltIn && !isDownloaded)
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
        .opacity((!downloadInfo.isURLValid && !downloadInfo.isBuiltIn && !isDownloaded) ? 0.6 : 1.0)
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
            downloadInfo: ModelDownloadInfo(
                id: "test",
                name: "Test Download Model",
                url: URL(string: "https://example.com/model.gguf")!,
                requiresUnzip: false
            )
        )            {}
    }
    .padding()
}
