import SwiftUI

struct ModelURLSettingsView: View {
    @State private var selectedFramework: LLMFramework = .coreML
    @State private var showingAddCustomURL = false
    @State private var customURLText = ""
    @State private var customModelName = ""
    @State private var customModelId = ""
    @State private var showingExportSheet = false

    private let registry = ModelURLRegistry.shared

    var body: some View {
        NavigationView {
            List {
                Section {
                    Picker("Framework", selection: $selectedFramework) {
                        ForEach([LLMFramework.coreML, .mlx, .onnxRuntime, .tensorFlowLite, .llamaCpp], id: \.self) { framework in
                            Text(framework.displayName).tag(framework)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Available Models")) {
                    ForEach(registry.getAllModels(for: selectedFramework), id: \.id) { model in
                        ModelURLRow(model: model)
                    }
                }

                Section(header: Text("Custom Models")) {
                    ForEach(registry.getCustomModels(), id: \.id) { model in
                        ModelURLRow(model: model, isCustom: true)
                    }

                    Button(action: {
                        showingAddCustomURL = true
                    }) {
                        Label("Add Custom Model URL", systemImage: "plus.circle")
                    }
                }

                Section {
                    Button(action: exportURLRegistry) {
                        Label("Export URL Registry", systemImage: "square.and.arrow.up")
                    }

                    Button(action: loadCustomURLs) {
                        Label("Import URL Registry", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("Model URLs")
            .sheet(isPresented: $showingAddCustomURL) {
                AddCustomURLView(
                    modelId: $customModelId,
                    modelName: $customModelName,
                    urlText: $customURLText,
                    onSave: addCustomModel
                )
            }
            .sheet(isPresented: $showingExportSheet) {
                ShareSheet(items: [getExportURL()])
            }
        }
    }

    private func addCustomModel() {
        guard !customModelId.isEmpty,
              !customModelName.isEmpty,
              let url = URL(string: customURLText) else { return }

        let model = ModelDownloadInfo(
            id: customModelId,
            name: customModelName,
            url: url,
            sha256: nil,
            requiresUnzip: customModelName.contains(".zip") || customModelName.contains(".tar.gz")
        )

        registry.addCustomModel(model)

        // Reset fields
        customModelId = ""
        customModelName = ""
        customURLText = ""
        showingAddCustomURL = false
    }

    private func exportURLRegistry() {
        do {
            let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent("model_urls.json")
            try registry.saveRegistry(to: exportURL)
            showingExportSheet = true
        } catch {
            print("Failed to export: \(error)")
        }
    }

    private func loadCustomURLs() {
        // This would show a document picker in a real implementation
        print("Import functionality would show document picker")
    }

    private func getExportURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("model_urls.json")
    }
}

struct ModelURLRow: View {
    let model: ModelDownloadInfo
    var isCustom: Bool = false
    @State private var showingCopyAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.name)
                    .font(.headline)

                Spacer()

                if isCustom {
                    Text("Custom")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            Text(model.url.absoluteString)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                if model.requiresUnzip {
                    Label("Requires Unzip", systemImage: "archivebox")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                if model.sha256 != nil {
                    Label("Verified", systemImage: "checkmark.shield")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Spacer()

                Button(action: {
                    UIPasteboard.general.string = model.url.absoluteString
                    showingCopyAlert = true
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
        .alert("URL Copied", isPresented: $showingCopyAlert) {
            Button("OK") { }
        }
    }
}

struct AddCustomURLView: View {
    @Binding var modelId: String
    @Binding var modelName: String
    @Binding var urlText: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Model Information")) {
                    TextField("Model ID", text: $modelId)
                        .autocapitalization(.none)

                    TextField("Model Name", text: $modelName)

                    TextField("Download URL", text: $urlText)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                }

                Section {
                    Text("Tips:")
                        .font(.headline)
                    Text("• Model ID should be unique")
                    Text("• Include file extension in name (.gguf, .mlpackage, etc.)")
                    Text("• URL must be direct download link")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .navigationTitle("Add Custom Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(modelId.isEmpty || modelName.isEmpty || urlText.isEmpty)
                }
            }
        }
    }
}

struct ModelURLSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ModelURLSettingsView()
    }
}
