import SwiftUI

struct FrameworkCapabilityExplorerView: View {
    @StateObject private var viewModel = FrameworkCapabilityExplorerViewModel()
    @State private var selectedFramework: LLMFramework?
    @State private var showComparison = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerSection

                ScrollView {
                    LazyVStack(spacing: 16) {
                        frameworkGridSection

                        if let framework = selectedFramework {
                            frameworkDetailSection(framework)
                        }

                        if showComparison {
                            comparisonSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Framework Explorer")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Compare All") {
                        showComparison.toggle()
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("LLM Framework Capabilities")
                .font(.title2)
                .fontWeight(.bold)

            Text("Explore the unique features and capabilities of each framework")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
    }

    private var frameworkGridSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
            ForEach(LLMFramework.allCases, id: \.self) { framework in
                CapabilityFrameworkCard(
                    framework: framework,
                    capabilities: viewModel.getCapabilities(for: framework),
                    isSelected: selectedFramework == framework
                ) {
                    selectedFramework = selectedFramework == framework ? nil : framework
                }
            }
        }
    }

    private func frameworkDetailSection(_ framework: LLMFramework) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: framework.iconName)
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text(framework.displayName)
                        .font(.headline)
                    Text(framework.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            capabilitiesDetailSection(framework)
            performanceMetricsSection(framework)
            useCasesSection(framework)
            codeExampleSection(framework)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private func capabilitiesDetailSection(_ framework: LLMFramework) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capabilities")
                .font(.subheadline)
                .fontWeight(.semibold)

            let capabilities = viewModel.getCapabilities(for: framework)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                CapabilityRow(title: "Streaming", supported: capabilities.supportsStreaming)
                CapabilityRow(title: "Quantization", supported: capabilities.supportsQuantization)
                CapabilityRow(title: "Batching", supported: capabilities.supportsBatching)
                CapabilityRow(title: "Multi-Modal", supported: capabilities.supportsMultiModal)
                CapabilityRow(title: "GPU Acceleration", supported: capabilities.supportsGPUAcceleration)
                CapabilityRow(title: "Custom Models", supported: capabilities.supportsCustomModels)
            }
        }
    }

    private func performanceMetricsSection(_ framework: LLMFramework) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Profile")
                .font(.subheadline)
                .fontWeight(.semibold)

            let metrics = viewModel.getPerformanceProfile(for: framework)

            VStack(spacing: 4) {
                MetricBar(title: "Speed", value: metrics.speed, color: .green)
                MetricBar(title: "Memory Efficiency", value: metrics.memoryEfficiency, color: .blue)
                MetricBar(title: "Model Size Support", value: metrics.modelSizeSupport, color: .orange)
                MetricBar(title: "Ease of Use", value: metrics.easeOfUse, color: .purple)
            }
        }
    }

    private func useCasesSection(_ framework: LLMFramework) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best Use Cases")
                .font(.subheadline)
                .fontWeight(.semibold)

            let useCases = viewModel.getUseCases(for: framework)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(useCases, id: \.self) { useCase in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(useCase)
                            .font(.caption)
                        Spacer()
                    }
                }
            }
        }
    }

    private func codeExampleSection(_ framework: LLMFramework) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Example")
                .font(.subheadline)
                .fontWeight(.semibold)

            let example = viewModel.getCodeExample(for: framework)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(example)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Framework Comparison Matrix")
                .font(.headline)
                .fontWeight(.bold)

            ScrollView(.horizontal, showsIndicators: false) {
                ComparisonMatrix(frameworks: LLMFramework.allCases, viewModel: viewModel)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct CapabilityFrameworkCard: View {
    let framework: LLMFramework
    let capabilities: FrameworkCapabilities
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                VStack(spacing: 8) {
                    Image(systemName: framework.iconName)
                        .font(.system(size: 30))
                        .foregroundColor(framework.isDeferred ? .gray : (isSelected ? .white : .blue))

                    Text(framework.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(framework.isDeferred ? .gray : (isSelected ? .white : .primary))

                    if framework.isDeferred {
                        Text("Coming Soon")
                            .font(.system(size: 10))
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(capabilities.topFeatures.prefix(3), id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(isSelected ? .white : .orange)
                            }
                        }
                    }
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)

                if framework.isDeferred {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(4)
                        }
                        Spacer()
                    }
                }
            }
            .background(framework.isDeferred ? Color.gray.opacity(0.1) : (isSelected ? Color.blue : Color.blue.opacity(0.1)))
            .cornerRadius(12)
        }
        .disabled(framework.isDeferred)
    }
}

struct CapabilityRow: View {
    let title: String
    let supported: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(supported ? .green : .red)
                .font(.caption)
            Text(title)
                .font(.caption)
                .foregroundColor(supported ? .primary : .secondary)
            Spacer()
        }
    }
}

struct MetricBar: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(color.opacity(0.2))
                        .frame(height: 4)

                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * value, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

struct ComparisonMatrix: View {
    let frameworks: [LLMFramework]
    let viewModel: FrameworkCapabilityExplorerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 12) {
                Text("Feature")
                    .font(.caption)
                    .fontWeight(.bold)
                    .frame(width: 100, alignment: .leading)

                ForEach(frameworks, id: \.self) { framework in
                    Text(framework.displayName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 80)
                        .rotationEffect(.degrees(-45))
                }
            }

            Divider()

            // Capability rows
            let features = ["Streaming", "Quantization", "Batching", "Multi-Modal", "GPU Accel", "Custom Models"]

            ForEach(features, id: \.self) { feature in
                HStack(spacing: 12) {
                    Text(feature)
                        .font(.caption)
                        .frame(width: 100, alignment: .leading)

                    ForEach(frameworks, id: \.self) { framework in
                        let capabilities = viewModel.getCapabilities(for: framework)
                        let supported = getFeatureSupport(feature: feature, capabilities: capabilities)

                        Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(supported ? .green : .red)
                            .font(.caption)
                            .frame(width: 80)
                    }
                }
            }
        }
        .padding()
    }

    private func getFeatureSupport(feature: String, capabilities: FrameworkCapabilities) -> Bool {
        switch feature {
        case "Streaming": return capabilities.supportsStreaming
        case "Quantization": return capabilities.supportsQuantization
        case "Batching": return capabilities.supportsBatching
        case "Multi-Modal": return capabilities.supportsMultiModal
        case "GPU Accel": return capabilities.supportsGPUAcceleration
        case "Custom Models": return capabilities.supportsCustomModels
        default: return false
        }
    }
}

#Preview {
    FrameworkCapabilityExplorerView()
}
