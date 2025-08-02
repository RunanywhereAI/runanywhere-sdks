//
//  ModelImportView.swift
//  RunAnywhereAI
//

import SwiftUI
import UniformTypeIdentifiers
import RunAnywhereSDK

struct ModelImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var importError: Error?
    @State private var showingError = false
    @State private var importedModelName = ""
    @State private var selectedFormat: ModelFormat = .gguf

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Import Local Model")
                    .font(.largeTitle)
                    .padding(.top)

                Text("Select a model file from your device to import it into the app.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Format selector
                Picker("Model Format", selection: $selectedFormat) {
                    ForEach(ModelFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                // Format description
                Text(formatDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Spacer()

                // Import button
                Button(action: {
                    isImporting = true
                }) {
                    Label("Select Model File", systemImage: "doc.badge.plus")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)

                // Model name field (shown after file selection)
                if !importedModelName.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model Name")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Enter model name", text: $importedModelName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.horizontal)

                    Button(action: importModel) {
                        Text("Import Model")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: contentTypes(for: selectedFormat),
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Import Error", isPresented: $showingError, presenting: importError) { _ in
                Button("OK") {
                    importError = nil
                }
            } message: { error in
                Text(error.localizedDescription)
            }
        }
    }

    private var formatDescription: String {
        switch selectedFormat {
        case .gguf:
            return "GGUF format used by llama.cpp. Efficient quantized models."
        case .coreML:
            return "Apple Core ML format. Optimized for Apple hardware."
        case .onnx:
            return "Open Neural Network Exchange format. Cross-platform."
        case .mlx:
            return "MLX format for Apple Silicon. High performance."
        default:
            return "Select a model format to see description."
        }
    }

    private func contentTypes(for format: ModelFormat) -> [UTType] {
        switch format {
        case .gguf:
            return [UTType(filenameExtension: "gguf") ?? .data]
        case .coreML:
            return [UTType(filenameExtension: "mlpackage") ?? .folder,
                    UTType(filenameExtension: "mlmodel") ?? .data]
        case .onnx:
            return [UTType(filenameExtension: "onnx") ?? .data]
        case .mlx:
            return [.folder] // MLX models are typically directories
        default:
            return [.data]
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Suggest a name based on the file
            let suggestedName = url.deletingPathExtension().lastPathComponent
            importedModelName = suggestedName

            // Store the URL for later import
            selectedFileURL = url

        case .failure(let error):
            importError = error
            showingError = true
        }
    }

    @State private var selectedFileURL: URL?

    private func importModel() {
        guard let url = selectedFileURL,
              !importedModelName.isEmpty else { return }

        Task {
            do {
                // Import the model
                let modelManager = ModelManager.shared
                let destinationURL = try await modelManager.importModel(
                    from: url,
                    as: importedModelName + "." + selectedFormat.fileExtension,
                    format: selectedFormat
                )

                // Create model info
                let modelInfo = ModelInfo(
                    id: UUID().uuidString,
                    name: importedModelName,
                    path: destinationURL.path,
                    format: selectedFormat,
                    size: ByteCountFormatter.string(
                        fromByteCount: Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
                        countStyle: .file
                    ),
                    framework: frameworkForFormat(selectedFormat)
                )

                // Add to model list
                await ModelListViewModel.shared.addImportedModel(modelInfo)

                // Dismiss
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    importError = error
                    showingError = true
                }
            }
        }
    }

    private func frameworkForFormat(_ format: ModelFormat) -> LLMFramework {
        switch format {
        case .gguf:
            return .llamaCpp
        case .coreML:
            return .coreML
        case .onnx:
            return .onnxRuntime
        case .mlx:
            return .mlx
        default:
            return .coreML  // Default to Core ML
        }
    }
}

struct ModelImportView_Previews: PreviewProvider {
    static var previews: some View {
        ModelImportView()
    }
}
