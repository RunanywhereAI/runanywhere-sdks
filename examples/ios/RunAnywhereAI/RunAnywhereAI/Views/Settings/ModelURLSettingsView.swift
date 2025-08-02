import SwiftUI
import RunAnywhereSDK

struct ModelURLSettingsView: View {
    @State private var selectedFramework: LLMFramework = .coreML
    @State private var showingAddCustomURL = false
    @State private var customURLText = ""
    @State private var customModelName = ""
    @State private var customModelId = ""

    private let registry = ModelURLRegistry.shared

    private let availableFrameworks: [LLMFramework] = [
        .coreML, .mlx, .onnx, .tensorFlowLite, .foundationModels
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    Picker("Framework", selection: $selectedFramework) {
                        ForEach(availableFrameworks, id: \.self) { framework in
                            Text(framework.rawValue).tag(framework)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Available Models")) {
                    ForEach(registry.getAllModels(for: selectedFramework), id: \.id) { model in
                        ModelURLRow(model: model)
                    }
                }

                Section {
                    Button(action: {}) {
                        Label("Export Settings", systemImage: "square.and.arrow.up")
                    }

                    Button(action: {}) {
                        Label("Import Settings", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("Model URLs")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct ModelURLRow: View {
    let model: ModelInfo
    var isCustom: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.name)
                .font(.headline)

            if let url = model.downloadURL {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .contextMenu {
            if isCustom {
                Button("Remove", role: .destructive) {
                    // Remove custom model
                }
            }
        }
    }
}

#Preview {
    ModelURLSettingsView()
}
