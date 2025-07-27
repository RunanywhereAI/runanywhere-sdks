//
//  ModelDownloadView.swift
//  RunAnywhereAI
//

import SwiftUI

struct ModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @State private var selectedModelInfo: ModelDownloadInfo?
    @State private var selectedFramework: LLMFramework = .coreML
    @State private var isDownloading = false
    @State private var downloadProgress: DownloadProgress?
    @State private var downloadError: Error?
    @State private var showingError = false

    // Get models from centralized registry
    private var availableModels: [ModelDownloadInfo] {
        let registry = ModelURLRegistry.shared
        return registry.getAllModels(for: selectedFramework)
    }

    var body: some View {
        NavigationView {
            VStack {
                // Framework Picker
                Picker("Framework", selection: $selectedFramework) {
                    ForEach([LLMFramework.coreML, .mlx, .onnxRuntime, .tensorFlowLite, .llamaCpp], id: \.self) { framework in
                        Text(framework.displayName).tag(framework)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                // Model List
                if availableModels.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No models available")
                            .font(.title2)
                            .foregroundColor(.secondary)

                        Text("Models for \(selectedFramework.displayName) can be added via Settings → Model URLs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(availableModels) { model in
                            ModelDownloadRow(
                                model: model,
                                isSelected: selectedModelInfo?.id == model.id,
                                isDownloaded: ModelManager.shared.isModelDownloaded(model.name)
                            )                                {
                                    selectedModelInfo = model
                                }
                        }
                    }
                }

                // Download Button
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
                                    Text(progress.downloadSpeed ?? "Calculating...")
                                        .font(.caption2)
                                    Spacer()
                                    Text(progress.timeRemaining ?? "")
                                        .font(.caption2)
                                }
                                .foregroundColor(.secondary)
                            }
                            .padding()
                        } else {
                            Button(action: downloadSelectedModel) {
                                Label("Download Model", systemImage: "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isDownloading || (selectedModelInfo != nil && ModelManager.shared.isModelDownloaded(selectedModelInfo!.name)))
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Download Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        }
    }

    private func downloadSelectedModel() {
        guard let modelInfo = selectedModelInfo else { return }

        isDownloading = true

        downloadManager.downloadModel(
            modelInfo,
            progress: { progress in
                downloadProgress = progress
            },
            completion: { result in
                isDownloading = false
                downloadProgress = nil

                switch result {
                case .success:
                    selectedModelInfo = nil
                // Refresh the view
                case .failure(let error):
                    downloadError = error
                    showingError = true
                }
            }
        )
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

                    HStack {
                        if isDownloaded {
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        if model.requiresAuth {
                            Label("Requires Auth", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
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
    }
}

#Preview {
    ModelDownloadView()
}
