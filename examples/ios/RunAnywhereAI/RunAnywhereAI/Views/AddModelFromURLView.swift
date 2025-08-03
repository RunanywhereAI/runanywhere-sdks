//
//  AddModelFromURLView.swift
//  RunAnywhereAI
//
//  View for adding models from URLs
//

import SwiftUI
import RunAnywhereSDK

struct AddModelFromURLView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var modelName: String = ""
    @State private var modelURL: String = ""
    @State private var selectedFramework: LLMFramework = .llamaCpp
    @State private var estimatedSize: String = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var availableFrameworks: [LLMFramework] = []

    let onModelAdded: (ModelInfo) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Model Information") {
                    TextField("Model Name", text: $modelName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Download URL", text: $modelURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section("Framework") {
                    Picker("Target Framework", selection: $selectedFramework) {
                        ForEach(availableFrameworks, id: \.self) { framework in
                            Text(framework.displayName).tag(framework)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Advanced (Optional)") {
                    TextField("Estimated Size (bytes)", text: $estimatedSize)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button("Add Model") {
                        Task {
                            await addModel()
                        }
                    }
                    .disabled(modelName.isEmpty || modelURL.isEmpty || isAdding)

                    if isAdding {
                        HStack {
                            ProgressView()
                            Text("Adding model...")
                        }
                    }
                }
            }
            .navigationTitle("Add Model from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadAvailableFrameworks()
        }
    }

    private func loadAvailableFrameworks() async {
        let frameworks = RunAnywhereSDK.shared.getAvailableFrameworks()
        await MainActor.run {
            self.availableFrameworks = frameworks.isEmpty ? [.llamaCpp] : frameworks
            // Set default selection to first available framework
            if !frameworks.isEmpty && !frameworks.contains(selectedFramework) {
                selectedFramework = frameworks.first!
            }
        }
    }

    private func addModel() async {
        guard let url = URL(string: modelURL) else {
            errorMessage = "Invalid URL format"
            return
        }

        isAdding = true
        errorMessage = nil

        do {
            let estimatedSizeBytes: Int64? = {
                guard !estimatedSize.isEmpty, let size = Int64(estimatedSize) else {
                    return nil
                }
                return size
            }()

            let modelInfo = RunAnywhereSDK.shared.addModelFromURL(
                name: modelName,
                url: url,
                framework: selectedFramework,
                estimatedSize: estimatedSizeBytes
            )

            await MainActor.run {
                onModelAdded(modelInfo)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to add model: \(error.localizedDescription)"
                isAdding = false
            }
        }
    }
}

#Preview {
    AddModelFromURLView { modelInfo in
        print("Added model: \(modelInfo.name)")
    }
}
