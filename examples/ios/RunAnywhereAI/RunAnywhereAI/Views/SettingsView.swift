//
//  SettingsView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import SwiftUI
import RunAnywhereSDK

struct SettingsView: View {
    @State private var temperature: Double = Double(SDKConstants.ConfigurationDefaults.temperature)
    @State private var maxTokens: Double = Double(SDKConstants.ConfigurationDefaults.maxTokens)
    @State private var topP: Double = Double(SDKConstants.ConfigurationDefaults.topP)
    @State private var topK: Double = Double(SDKConstants.ConfigurationDefaults.topK)
    @AppStorage("showAdvancedSettings") private var showAdvancedSettings = false
    @State private var showingFrameworkConfig = false
    @State private var selectedFramework: LLMFramework?

    // SDK Configuration settings
    @State private var cloudRoutingEnabled: Bool = SDKConstants.ConfigurationDefaults.cloudRoutingEnabled
    @State private var privacyModeEnabled: Bool = SDKConstants.ConfigurationDefaults.privacyModeEnabled
    @State private var routingPolicy: String = SDKConstants.ConfigurationDefaults.routingPolicy
    @State private var apiKey: String = ""

    // Access to SDK
    private let sdk = RunAnywhereSDK.shared

    var body: some View {
        Form {
            Section("SDK Configuration") {
                Toggle("Enable Cloud Routing", isOn: $cloudRoutingEnabled)
                    .onChange(of: cloudRoutingEnabled) { newValue in
                        Task {
                            await sdk.setCloudRoutingEnabled(newValue)
                        }
                    }

                Toggle("Privacy Mode", isOn: $privacyModeEnabled)
                    .onChange(of: privacyModeEnabled) { newValue in
                        Task {
                            await sdk.setPrivacyModeEnabled(newValue)
                        }
                    }

                Picker("Routing Policy", selection: $routingPolicy) {
                    Text("Automatic").tag(SDKConstants.RoutingPolicy.automatic)
                    Text("On-Device Only").tag(SDKConstants.RoutingPolicy.onDeviceOnly)
                    Text("Cloud Only").tag(SDKConstants.RoutingPolicy.cloudOnly)
                    Text("Cost Optimized").tag(SDKConstants.RoutingPolicy.costOptimized)
                }
                .onChange(of: routingPolicy) { newValue in
                    Task {
                        await sdk.setRoutingPolicy(newValue)
                    }
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
                    if apiKey.isEmpty {
                        Text("Not Set")
                            .foregroundColor(.red)
                    } else {
                        Text("••••••••")
                            .foregroundColor(.green)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    // In a real app, you'd show a secure input dialog
                    // For now, we'll just toggle between set/not set
                    Task {
                        if apiKey.isEmpty {
                            let testKey = "test_api_key_123"
                            apiKey = testKey
                            await sdk.setApiKey(testKey)
                        } else {
                            apiKey = ""
                            await sdk.setApiKey(nil)
                        }
                    }
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
        temperature = Double(SDKConstants.ConfigurationDefaults.temperature)
        maxTokens = Double(SDKConstants.ConfigurationDefaults.maxTokens)
        topP = Double(SDKConstants.ConfigurationDefaults.topP)
        topK = Double(SDKConstants.ConfigurationDefaults.topK)
        showAdvancedSettings = false
        cloudRoutingEnabled = SDKConstants.ConfigurationDefaults.cloudRoutingEnabled
        privacyModeEnabled = SDKConstants.ConfigurationDefaults.privacyModeEnabled
        routingPolicy = SDKConstants.ConfigurationDefaults.routingPolicy

        // Clear SDK overrides and reset to defaults
        Task {
            await sdk.resetGenerationSettings()
            await sdk.setCloudRoutingEnabled(SDKConstants.ConfigurationDefaults.cloudRoutingEnabled)
            await sdk.setPrivacyModeEnabled(SDKConstants.ConfigurationDefaults.privacyModeEnabled)
            await sdk.setRoutingPolicy(SDKConstants.ConfigurationDefaults.routingPolicy)

            // Sync to database and cloud
            await sdk.syncUserPreferences()
        }
    }

    private func loadCurrentSettings() async {
        // Load generation settings
        let settings = await sdk.getGenerationSettings()

        // Load SDK configuration settings
        let cloudRouting = await sdk.getCloudRoutingEnabled()
        let privacyMode = await sdk.getPrivacyModeEnabled()
        let policy = await sdk.getRoutingPolicy()
        let key = await sdk.getApiKey()

        await MainActor.run {
            temperature = Double(settings.temperature)
            maxTokens = Double(settings.maxTokens)
            topP = Double(settings.topP)
            topK = Double(settings.topK)

            cloudRoutingEnabled = cloudRouting
            privacyModeEnabled = privacyMode
            routingPolicy = policy
            apiKey = key ?? ""
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
