//
//  UnifiedFrameworkCard.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import SwiftUI

struct UnifiedFrameworkCard: View {
    let framework: LLMFramework
    let isExpanded: Bool
    let viewModel: ModelListViewModel
    let onTap: () -> Void
    let onModelTap: (ModelInfo) -> Void
    let onDownload: (ModelDownloadInfo) -> Void

    @StateObject private var modelURLRegistry = ModelURLRegistry.shared

    private var service: LLMService? {
        viewModel.availableServices.first { service in
            service.name == framework.displayName || service.name.lowercased() == framework.rawValue.lowercased()
        }
    }

    private var frameworkIcon: String {
        switch framework {
        case .coreML: return "brain.head.profile"
        case .mlx: return "cube.fill"
        case .onnxRuntime: return "cpu.fill"
        case .tensorFlowLite: return "square.stack.3d.up.fill"
        case .foundationModels: return "sparkles"
        default: return "cube"
        }
    }

    private var availableDownloadModels: [ModelDownloadInfo] {
        modelURLRegistry.getAllModels(for: framework)
    }

    private var allModels: [ModelInfo] {
        guard let service = service else { return [] }
        return service.supportedModels
    }

    private var totalModelsCount: Int {
        let serviceModels = service?.supportedModels.count ?? 0
        let downloadableModels = availableDownloadModels.count
        // Avoid double counting if some models exist in both lists
        return max(serviceModels, downloadableModels)
    }

    private var downloadedCount: Int {
        allModels.filter { $0.isLocal }.count
    }

    private var compatibleCount: Int {
        allModels.filter { $0.isCompatible }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Framework Header
            Button(action: onTap) {
                HStack {
                    Image(systemName: frameworkIcon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(framework.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        HStack(spacing: 8) {
                            // Framework status
                            if let service = service {
                                if service.isInitialized {
                                    Label("Ready", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Label("Available", systemImage: "circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Label("Loading", systemImage: "circle.dotted")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            Text("•")
                                .foregroundColor(.secondary)

                            // Model counts
                            Text("\(totalModelsCount) models")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if downloadedCount > 0 {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("\(downloadedCount) downloaded")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if compatibleCount < totalModelsCount && totalModelsCount > 0 {
                            Text("\(compatibleCount)/\(totalModelsCount) compatible")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded Model List
            if isExpanded {
                Divider()

                if allModels.isEmpty {
                    EmptyModelsView(framework: framework, onDownload: onDownload)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(allModels.enumerated()), id: \.element.id) { index, model in
                            UnifiedModelRow(
                                model: model,
                                framework: framework,
                                onTap: { onModelTap(model) },
                                onDownload: onDownload,
                                viewModel: viewModel
                            )

                            if index < allModels.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }

                        // Show additional downloadable models that aren't in the service
                        let additionalModels = getAdditionalDownloadableModels()
                        if !additionalModels.isEmpty {
                            if !allModels.isEmpty {
                                Divider()
                                    .padding(.leading, 56)
                            }

                            ForEach(Array(additionalModels.enumerated()), id: \.element.id) { index, downloadInfo in
                                DownloadOnlyModelRow(
                                    downloadInfo: downloadInfo
                                )                                    { onDownload(downloadInfo) }

                                if index < additionalModels.count - 1 {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func getAdditionalDownloadableModels() -> [ModelDownloadInfo] {
        let serviceModelNames = Set(allModels.map { $0.name.lowercased() })
        let serviceModelIds = Set(allModels.map { $0.id.lowercased() })

        return availableDownloadModels.filter { downloadInfo in
            let downloadNameLower = downloadInfo.name.lowercased()
            let downloadIdLower = downloadInfo.id.lowercased()

            // Include if not already in service models
            return !serviceModelNames.contains(downloadNameLower) &&
                !serviceModelIds.contains(downloadIdLower) &&
                !serviceModelNames.contains { serviceName in
                    // Check for similar names (e.g., contains common patterns)
                    downloadNameLower.contains(serviceName) || serviceName.contains(downloadNameLower)
                }
        }
    }
}

// MARK: - Empty Models View

struct EmptyModelsView: View {
    let framework: LLMFramework
    let onDownload: (ModelDownloadInfo) -> Void

    @StateObject private var modelURLRegistry = ModelURLRegistry.shared

    private var availableDownloads: [ModelDownloadInfo] {
        modelURLRegistry.getAllModels(for: framework)
    }

    var body: some View {
        VStack(spacing: 16) {
            if availableDownloads.isEmpty {
                // No models available at all
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text("No models available")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if framework == .foundationModels {
                        Text("Foundation Models require iOS 18+ or macOS 15+")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Add model URLs in Settings or import models manually")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // Show available downloads
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.largeTitle)
                        .foregroundColor(.blue)

                    Text("Models available for download")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Tap any model below to download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 20)

                // Show downloadable models
                VStack(spacing: 0) {
                    ForEach(Array(availableDownloads.enumerated()), id: \.element.id) { index, downloadInfo in
                        DownloadOnlyModelRow(
                            downloadInfo: downloadInfo
                        )                            { onDownload(downloadInfo) }

                        if index < availableDownloads.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    UnifiedFrameworkCard(
        framework: .coreML,
        isExpanded: true,
        viewModel: ModelListViewModel(),
        onTap: {},
        onModelTap: { _ in },
        onDownload: { _ in }
    )
    .padding()
}
