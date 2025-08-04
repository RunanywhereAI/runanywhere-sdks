//
//  SettingsView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import SwiftUI
import RunAnywhereSDK

struct SettingsView: View {
    @State private var temperature: Double = 0.7
    @State private var maxTokens: Double = 150
    @State private var topP: Double = 0.95
    @State private var topK: Double = 40
    @AppStorage("showAdvancedSettings") private var showAdvancedSettings = false
    @State private var showingFrameworkConfig = false
    @State private var selectedFramework: LLMFramework?

    // Access to SDK
    private let sdk = RunAnywhereSDK.shared

    var body: some View {
        Form {
            Section("SDK Configuration") {
                HStack {
                    Text("Enable Cloud Routing")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                HStack {
                    Text("Privacy Mode")
                    Spacer()
                    Text("Automatic")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Routing Policy")
                    Spacer()
                    Text("Automatic")
                        .foregroundColor(.secondary)
                }
            }

            Section("Generation Settings") {
                VStack(alignment: .leading) {
                    Text("Temperature: \(temperature, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $temperature, in: 0...2, step: 0.1) { _ in
                        // Update SDK configuration
                        Task {
                            await sdk.setTemperature(Float(temperature))
                        }
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Max Tokens: \(Int(maxTokens))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { maxTokens = max(10, maxTokens - 10) }) {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(BorderlessButtonStyle())

                        Button(action: { maxTokens = min(500, maxTokens + 10) }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    Slider(value: $maxTokens, in: 10...500, step: 10) { _ in
                        // Update SDK configuration
                        Task {
                            await sdk.setMaxTokens(Int(maxTokens))
                        }
                    }
                }

                Toggle("Show Advanced Settings", isOn: $showAdvancedSettings)
            }

            if showAdvancedSettings {
                Section("Advanced Settings") {
                    VStack(alignment: .leading) {
                        Text("Top P: \(topP, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $topP, in: 0...1, step: 0.05) { _ in
                            // Update SDK configuration
                            Task {
                                await sdk.setTopP(Float(topP))
                            }
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Top K: \(Int(topK))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $topK, in: 1...100, step: 1) { _ in
                            // Update SDK configuration
                            Task {
                                await sdk.setTopK(Int(topK))
                            }
                        }
                    }
                }
            }

            Section("API Configuration") {
                HStack {
                    Text("API Key")
                    Spacer()
                    Text("Not Set")
                        .foregroundColor(.red)
                }

                NavigationLink(destination: Text("Documentation")) {
                    Label("Documentation", systemImage: "doc.text")
                }

                NavigationLink(destination: Text("GitHub")) {
                    Label("GitHub", systemImage: "link")
                }
            }

            Section("About") {
                HStack {
                    Label("RunAnywhere SDK", systemImage: "cube")
                    Spacer()
                    Text("Version 1.0.0")
                        .foregroundColor(.secondary)
                }

                NavigationLink(destination: Text("Documentation")) {
                    Label("Documentation", systemImage: "doc.text")
                }

                NavigationLink(destination: Text("GitHub")) {
                    Label("GitHub", systemImage: "link")
                }
            }

            Section {
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingFrameworkConfig) {
            if let framework = selectedFramework {
                Text("Framework Configuration for \(framework.displayName)")
                    .padding()
            }
        }
        .task {
            await loadCurrentSettings()
        }
    }

    private var deviceMemoryString: String {
        let memory = ProcessInfo.processInfo.physicalMemory
        return ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)
    }

    private func resetToDefaults() {
        temperature = 0.7
        maxTokens = 150
        topP = 0.95
        topK = 40
        showAdvancedSettings = false

        // Clear SDK overrides
        Task {
            await sdk.resetGenerationSettings()
        }
    }

    private func loadCurrentSettings() async {
        let settings = await sdk.getGenerationSettings()
        await MainActor.run {
            temperature = Double(settings.temperature)
            maxTokens = Double(settings.maxTokens)
            topP = Double(settings.topP)
            topK = Double(settings.topK)
        }
    }

    private var availableFrameworks: [LLMFramework] {
        return [.coreML, .mlx, .onnx, .tensorFlowLite, .foundationModels, .llamaCpp]
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
}
