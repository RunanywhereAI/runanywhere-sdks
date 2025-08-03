//
//  UnifiedModelDetailsView.swift
//  RunAnywhereAI
//
//  Simplified version for direct SDK consumption
//

import SwiftUI
import RunAnywhereSDK

struct UnifiedModelDetailsView: View {
    let model: ModelInfo
    let onDownload: (ModelInfo) -> Void

    @StateObject private var downloadManager = ModelDownloadManager.shared

    private var frameworkIcon: String {
        guard let framework = model.preferredFramework ?? model.compatibleFrameworks.first else {
            return "cube"
        }

        switch framework {
        case .coreML: return "brain.head.profile"
        case .mlx: return "cube.fill"
        case .onnx: return "cpu.fill"
        case .tensorFlowLite: return "square.stack.3d.up.fill"
        case .foundationModels: return "sparkles"
        case .llamaCpp: return "terminal.fill"
        case .mediaPipe: return "brain.filled.head.profile"
        case .swiftTransformers: return "swift"
        case .execuTorch: return "flame.fill"
        case .picoLLM: return "waveform"
        case .mlc: return "gear.badge"
        }
    }

    private var isDownloading: Bool {
        downloadManager.isDownloading(model.id)
    }

    private func hardwareRequirementDescription(_ requirement: HardwareRequirement) -> String {
        switch requirement {
        case .minimumMemory(let bytes):
            return "Minimum Memory: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory))"
        case .minimumCompute(let compute):
            return "Minimum Compute: \(compute)"
        case .requiresNeuralEngine:
            return "Requires Neural Engine"
        case .requiresGPU:
            return "Requires GPU"
        case .minimumOSVersion(let version):
            return "Minimum OS: \(version)"
        case .specificChip(let chip):
            return "Requires: \(chip)"
        case .requiresAppleSilicon:
            return "Requires Apple Silicon"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: frameworkIcon)
                            .font(.largeTitle)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            if let framework = model.preferredFramework ?? model.compatibleFrameworks.first {
                                Text(framework.rawValue)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }

                    // Status
                    HStack(spacing: 8) {
                        StatusBadge(
                            text: model.localPath != nil ? "Downloaded" : "Available",
                            systemImage: model.localPath != nil ? "checkmark.circle.fill" : "circle",
                            color: model.localPath != nil ? .green : .orange
                        )

                        StatusBadge(
                            text: "Compatible",
                            systemImage: "checkmark.circle.fill",
                            color: .green
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

                // Model Details
                VStack(alignment: .leading, spacing: 16) {
                    Text("Model Details")
                        .font(.headline)

                    VStack(spacing: 12) {
                        DetailRow(label: "Format", value: model.format.rawValue)

                        if model.estimatedMemory > 0 {
                            DetailRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: model.estimatedMemory, countStyle: .file))
                        }

                        if model.contextLength > 0 {
                            DetailRow(label: "Context Length", value: "\(model.contextLength) tokens")
                        }

                        if let localPath = model.localPath {
                            DetailRow(
                                label: "Local Path",
                                value: localPath.lastPathComponent,
                                valueColor: .green
                            )
                        }

                        if let downloadURL = model.downloadURL {
                            DetailRow(
                                label: "Download URL",
                                value: downloadURL.absoluteString,
                                isURL: true
                            )
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

                // Hardware Requirements
                if !model.hardwareRequirements.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hardware Requirements")
                            .font(.headline)

                        VStack(spacing: 8) {
                            ForEach(Array(model.hardwareRequirements.enumerated()), id: \.offset) { index, requirement in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(hardwareRequirementDescription(requirement))
                                        .font(.subheadline)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }

                // Actions
                VStack(spacing: 12) {
                    if model.localPath != nil {
                        Button(action: {}) {
                            Label("Model Ready", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(12)
                        }
                        .disabled(true)
                    } else if isDownloading {
                        Button(action: {
                            downloadManager.cancelDownload(model.id)
                        }) {
                            Label("Cancel Download", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(12)
                        }
                    } else {
                        Button(action: {
                            onDownload(model)
                        }) {
                            Label("Download Model", systemImage: "arrow.down.circle")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Model Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
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
    var valueColor: Color = .primary
    var isURL: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            if isURL {
                Text(value)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(valueColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

#Preview {
    NavigationView {
        UnifiedModelDetailsView(
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
            )
        ) { _ in }
    }
}
