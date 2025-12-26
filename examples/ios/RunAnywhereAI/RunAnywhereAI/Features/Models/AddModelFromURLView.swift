//
//  AddModelFromURLView.swift
//  RunAnywhereAI
//
//  View for adding models from URLs
//

import SwiftUI
import RunAnywhere
import Combine

struct AddModelFromURLView: View {
    @Environment(\.dismiss)
    private var dismiss
    @State private var modelName: String = ""
    @State private var modelURL: String = ""
    @State private var selectedFramework: InferenceFramework = .llamaCpp
    @State private var estimatedSize: String = ""
    @State private var supportsThinking = false
    @State private var thinkingOpenTag = "<thinking>"
    @State private var thinkingCloseTag = "</thinking>"
    @State private var useCustomThinkingTags = false
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var availableFrameworks: [InferenceFramework] = []

    let onModelAdded: (ModelInfo) -> Void

    var body: some View {
        NavigationStack {
            Form {
                formContent

                Section {
                    Button("Add Model") {
                        Task {
                            await addModel()
                        }
                    }
                    .disabled(modelName.isEmpty || modelURL.isEmpty || isAdding)
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primaryAccent)
                    #endif

                    if isAdding {
                        HStack {
                            ProgressView()
                                #if os(macOS)
                                .controlSize(.small)
                                #endif
                            Text("Adding model...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500)
            #endif
            .navigationTitle("Add Model from URL")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
                #endif
            }
        }
        #if os(macOS)
        .padding()
        #endif
        .task {
            await loadAvailableFrameworks()
        }
    }

    @ViewBuilder private var formContent: some View {
        Section("Model Information") {
            TextField("Model Name", text: $modelName)
                .textFieldStyle(.roundedBorder)

            TextField("Download URL", text: $modelURL)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.URL)
                .autocapitalization(.none)
                #endif
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

        Section("Thinking Support") {
            Toggle("Model Supports Thinking", isOn: $supportsThinking)

            if supportsThinking {
                Toggle("Use Custom Tags", isOn: $useCustomThinkingTags)

                if useCustomThinkingTags {
                    TextField("Opening Tag", text: $thinkingOpenTag)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()

                    TextField("Closing Tag", text: $thinkingCloseTag)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                } else {
                    HStack {
                        Text("Default tags:")
                        Text("<thinking>...</thinking>")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        Section("Advanced (Optional)") {
            TextField("Estimated Size (bytes)", text: $estimatedSize)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }

        if let error = errorMessage {
            Section {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }

    private func loadAvailableFrameworks() async {
        let frameworks = await MainActor.run {
            RunAnywhere.getRegisteredFrameworks()
        }
        await MainActor.run {
            self.availableFrameworks = frameworks.isEmpty ? [.llamaCpp] : frameworks
            // Set default selection to first available framework
            if let first = frameworks.first, !frameworks.contains(selectedFramework) {
                selectedFramework = first
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

        // Use the new registerModel API
        let modelInfo = await MainActor.run {
            RunAnywhere.registerModel(
                name: modelName,
                url: url,
                framework: selectedFramework,
                memoryRequirement: Int64(estimatedSize),
                supportsThinking: supportsThinking
            )
        }

        await MainActor.run {
            onModelAdded(modelInfo)
            dismiss()
        }
    }
}

#Preview {
    AddModelFromURLView { modelInfo in
        print("Added model: \(modelInfo.name)")
    }
}
