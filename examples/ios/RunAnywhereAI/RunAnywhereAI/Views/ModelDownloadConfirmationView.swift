//
//  ModelDownloadConfirmationView.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/28/25.
//

import SwiftUI
import RunAnywhereSDK

struct ModelDownloadConfirmationView: View {
    let model: ModelInfo
    let onDownload: (ModelInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedURL: URL?
    @State private var downloadInfo: ModelInfo?

    private var availableDownloads: [ModelInfo] {
        let registry = ModelURLRegistry.shared
        // Use preferred framework or first compatible framework
        let framework = model.preferredFramework ?? model.compatibleFrameworks.first ?? .foundationModels
        let allModels = registry.getAllModels(for: framework)

        return allModels.filter { downloadInfo in
            // Exact match
            if downloadInfo.name == model.name || downloadInfo.id == model.id {
                return true
            }

            // Check if the model name contains key parts of the download name
            let modelNameLower = model.name.lowercased()
            let downloadNameLower = downloadInfo.name.lowercased()

            // Check for common patterns
            if modelNameLower.contains("phi") && downloadNameLower.contains("phi") {
                return true
            }
            if modelNameLower.contains("tinyllama") && downloadNameLower.contains("tinyllama") {
                return true
            }
            if modelNameLower.contains("llama-3.2") && downloadNameLower.contains("llama-3.2") {
                return true
            }
            if modelNameLower.contains("mistral") && downloadNameLower.contains("mistral") {
                return true
            }
            if modelNameLower.contains("gemma") && downloadNameLower.contains("gemma") {
                return true
            }
            if modelNameLower.contains("gpt2") && downloadNameLower.contains("gpt2") {
                return true
            }

            return false
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Model info
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.name, systemImage: "doc.fill")
                        .font(.headline)

                    HStack {
                        Label(model.framework.displayName, systemImage: "cpu")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Label(model.displaySize, systemImage: "internaldrive")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

                if availableDownloads.isEmpty {
                    // No pre-configured URLs
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)

                        Text("No Download URL Available")
                            .font(.headline)

                        Text("This model doesn't have a pre-configured download URL.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                    Spacer()
                } else {
                    // Show available download options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Download Options")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(availableDownloads) { download in
                            DownloadOptionRow(
                                downloadInfo: download,
                                isSelected: selectedURL == download.downloadURL
                            )                                {
                                    selectedURL = download.downloadURL
                                    downloadInfo = download
                                }
                        }
                    }

                    Spacer()

                    // Download details
                    if let info = downloadInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            if info.requiresAuth {
                                Label("Requires authentication", systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            if info.requiresUnzip {
                                Label("Will be extracted after download", systemImage: "doc.zipper")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    }

                    // Download button
                    Button(action: {
                        if let info = downloadInfo {
                            dismiss()
                            onDownload(info)
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Model")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(downloadInfo != nil ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(downloadInfo == nil)
                }
            }
            .padding()
            .navigationTitle("Download Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DownloadOptionRow: View {
    let downloadInfo: ModelInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(downloadInfo.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text(downloadInfo.downloadURL?.host ?? "Unknown source")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}

struct ModelDownloadConfirmationView_Previews: PreviewProvider {
    static var previews: some View {
        ModelDownloadConfirmationView(
            model: ModelInfo(
                name: "Llama 3.2 3B",
                format: .gguf,
                size: "2.4 GB",
                framework: .llamaCpp,
                quantization: "Q4_K_M"
            )
        )            { _ in }
    }
}
