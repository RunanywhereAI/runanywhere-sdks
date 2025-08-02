//
//  SimplifiedModelsView.swift
//  RunAnywhereAI
//
//  A simplified models view that demonstrates SDK usage
//

import SwiftUI
import RunAnywhereSDK

struct SimplifiedModelsView: View {
    @StateObject private var viewModel = ModelListViewModel()
    @StateObject private var deviceInfo = DeviceInfoService.shared

    @State private var selectedModel: ModelInfo?
    @State private var expandedFramework: LLMFramework?

    var body: some View {
        NavigationView {
            mainContentView
        }
    }

    private var mainContentView: some View {
        List {
            deviceStatusSection
            frameworksSection
            modelsSection
        }
        .navigationTitle("Models")
        .task {
            await viewModel.loadModels()
        }
    }

    private var deviceStatusSection: some View {
        Section("Device Status") {
            if let device = deviceInfo.deviceInfo {
                deviceInfoRows(device)
            } else {
                loadingDeviceRow
            }
        }
    }

    private func deviceInfoRows(_ device: SystemDeviceInfo) -> some View {
        Group {
            deviceInfoRow(label: "Model", systemImage: "iphone", value: device.modelName)
            deviceInfoRow(label: "Chip", systemImage: "cpu", value: device.chipName)
            deviceInfoRow(label: "Memory", systemImage: "memorychip",
                         value: ByteCountFormatter.string(fromByteCount: device.totalMemory, countStyle: .memory))

            if device.neuralEngineAvailable {
                neuralEngineRow
            }
        }
    }

    private func deviceInfoRow(label: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }

    private var neuralEngineRow: some View {
        HStack {
            Label("Neural Engine", systemImage: "brain")
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }

    private var loadingDeviceRow: some View {
        HStack {
            ProgressView()
            Text("Loading device info...")
                .foregroundColor(.secondary)
        }
    }

    private var frameworksSection: some View {
        Section("Available Frameworks") {
            FrameworkRow(
                framework: .foundationModels,
                isExpanded: expandedFramework == .foundationModels,
                onTap: { toggleFramework(.foundationModels) }
            )

            FrameworkRow(
                framework: .mediaPipe,
                isExpanded: expandedFramework == .mediaPipe,
                onTap: { toggleFramework(.mediaPipe) }
            )
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        if let expanded = expandedFramework {
            let filteredModels = viewModel.availableModels.filter { $0.compatibleFrameworks.contains(expanded) }

            Section("Models for \(expanded.displayName)") {
                ForEach(filteredModels, id: \.id) { model in
                    ModelRow(model: model, isSelected: selectedModel?.id == model.id)
                        .onTapGesture {
                            Task {
                                await selectModel(model)
                            }
                        }
                }

                if filteredModels.isEmpty {
                    Text("No models available for this framework")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    private func toggleFramework(_ framework: LLMFramework) {
        withAnimation {
            if expandedFramework == framework {
                expandedFramework = nil
            } else {
                expandedFramework = framework
            }
        }
    }

    private func selectModel(_ model: ModelInfo) async {
        selectedModel = model

        // Use SDK to load the model
        do {
            _ = try await RunAnywhereSDK.shared.loadModel(model.id)
            // Model loaded successfully
        } catch {
            print("Failed to load model: \(error)")
        }
    }
}

// MARK: - Supporting Views

private struct FrameworkRow: View {
    let framework: LLMFramework
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: frameworkIcon)
                    .foregroundColor(frameworkColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(framework.displayName)
                        .font(.headline)
                    Text(frameworkDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var frameworkIcon: String {
        switch framework {
        case .foundationModels:
            return "apple.logo"
        case .mediaPipe:
            return "brain.filled.head.profile"
        default:
            return "cpu"
        }
    }

    private var frameworkColor: Color {
        switch framework {
        case .foundationModels:
            return .black
        case .mediaPipe:
            return .blue
        default:
            return .gray
        }
    }

    private var frameworkDescription: String {
        switch framework {
        case .foundationModels:
            return "Apple's on-device language models"
        case .mediaPipe:
            return "Google's cross-platform ML framework"
        default:
            return "Machine learning framework"
        }
    }
}

private struct ModelRow: View {
    let model: ModelInfo
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                HStack(spacing: 8) {
                    let size = model.estimatedMemory
                    if size > 0 {
                        Label(
                            ByteCountFormatter.string(fromByteCount: size, countStyle: .memory),
                            systemImage: "memorychip"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }

                    let format = model.format
                    Text(format.rawValue.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SimplifiedModelsView()
}
