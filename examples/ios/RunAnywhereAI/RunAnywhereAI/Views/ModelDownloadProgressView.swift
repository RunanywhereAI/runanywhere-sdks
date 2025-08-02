//
//  ModelDownloadProgressView.swift
//  RunAnywhereAI
//
//  Simplified version for direct SDK consumption
//

import SwiftUI
import RunAnywhereSDK

enum DownloadStep: String, CaseIterable {
    case preparing = "Preparing"
    case downloading = "Downloading"
    case verifying = "Verifying"
    case complete = "Complete"

    var icon: String {
        switch self {
        case .preparing: return "gear"
        case .downloading: return "arrow.down.circle"
        case .verifying: return "checkmark.shield"
        case .complete: return "checkmark.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .preparing: return "Preparing download..."
        case .downloading: return "Downloading model..."
        case .verifying: return "Verifying download..."
        case .complete: return "Download complete!"
        }
    }
}

struct ModelDownloadProgressView: View {
    let model: ModelInfo
    @Binding var isPresented: Bool

    @StateObject private var downloadManager = ModelDownloadManager.shared
    @State private var currentStep: DownloadStep = .preparing
    @State private var downloadProgress: Double = 0
    @State private var error: Error?
    @State private var showingError = false
    @State private var isComplete = false

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)

                    Text(model.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    if model.estimatedMemory > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: model.estimatedMemory, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Progress Steps
                VStack(spacing: 20) {
                    ForEach(Array(DownloadStep.allCases.enumerated()), id: \.offset) { index, step in
                        DownloadStepRow(
                            step: step,
                            isActive: step == currentStep,
                            isCompleted: DownloadStep.allCases.firstIndex(of: step)! < DownloadStep.allCases.firstIndex(of: currentStep)!,
                            progress: step == .downloading ? downloadProgress : nil
                        )
                    }
                }

                // Progress Bar
                if currentStep == .downloading {
                    VStack(spacing: 8) {
                        ProgressView(value: downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .tint(.blue)

                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }

                Spacer()

                // Action Button
                if isComplete {
                    Button("Done") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                } else {
                    Button("Cancel") {
                        cancelDownload()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .padding()
                }
            }
            .padding()
            .navigationTitle("Downloading")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            startDownload()
        }
        .alert("Download Error", isPresented: $showingError) {
            Button("Retry") {
                startDownload()
            }
            Button("Cancel", role: .cancel) {
                isPresented = false
            }
        } message: {
            Text(error?.localizedDescription ?? "Unknown error occurred")
        }
    }

    private func startDownload() {
        currentStep = .preparing
        error = nil
        isComplete = false

        Task {
            // Simulate preparing
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            await MainActor.run {
                currentStep = .downloading
            }

            // Start download
            downloadManager.downloadModel(
                model,
                progress: { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                },
                completion: { result in
                    Task { @MainActor in
                        switch result {
                        case .success(_):
                            self.currentStep = .verifying

                            // Simulate verification
                            Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                await MainActor.run {
                                    self.currentStep = .complete
                                    self.isComplete = true
                                }
                            }
                        case .failure(let error):
                            self.error = error
                            self.showingError = true
                        }
                    }
                }
            )
        }
    }

    private func cancelDownload() {
        downloadManager.cancelDownload(model.id)
        isPresented = false
    }
}

struct DownloadStepRow: View {
    let step: DownloadStep
    let isActive: Bool
    let isCompleted: Bool
    let progress: Double?

    var body: some View {
        HStack(spacing: 16) {
            // Step icon
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)

                Image(systemName: step.icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }

            // Step info
            VStack(alignment: .leading, spacing: 4) {
                Text(step.rawValue)
                    .font(.headline)
                    .foregroundColor(isActive || isCompleted ? .primary : .secondary)

                if isActive {
                    Text(step.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status indicator
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            } else if isActive {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.vertical, 12)
    }

    private var backgroundColor: Color {
        if isCompleted {
            return .green.opacity(0.2)
        } else if isActive {
            return .blue.opacity(0.2)
        } else {
            return Color(.systemGray5)
        }
    }

    private var iconColor: Color {
        if isCompleted {
            return .green
        } else if isActive {
            return .blue
        } else {
            return .secondary
        }
    }
}

#Preview {
    ModelDownloadProgressView(
        model: ModelInfo(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            format: .gguf,
            downloadURL: URL(string: "https://example.com/model.gguf"),
            localPath: nil,
            estimatedMemory: 2_400_000_000,
            contextLength: 2048,
            downloadSize: 2_400_000_000,
            checksum: nil,
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            hardwareRequirements: [],
            tokenizerFormat: nil,
            metadata: nil,
            alternativeDownloadURLs: []
        ),
        isPresented: .constant(true)
    )
}
