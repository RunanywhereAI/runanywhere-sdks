//
//  SimplifiedSettingsView.swift
//  RunAnywhereAI
//
//  A simplified settings view that demonstrates SDK configuration
//

import SwiftUI
import RunAnywhereSDK

struct SimplifiedSettingsView: View {
    @State private var routingPolicy = RoutingPolicy.automatic
    @State private var defaultTemperature = 0.7
    @State private var defaultMaxTokens = 10000
    @State private var showApiKeyEntry = false
    @State private var apiKey = ""

    var body: some View {
        Form {
            Section("SDK Configuration") {
                Picker("Routing Policy", selection: $routingPolicy) {
                    Text("Automatic").tag(RoutingPolicy.automatic)
                    Text("Device Only").tag(RoutingPolicy.deviceOnly)
                    Text("Prefer Device").tag(RoutingPolicy.preferDevice)
                    Text("Prefer Cloud").tag(RoutingPolicy.preferCloud)
                }
                .onChange(of: routingPolicy) { _ in
                    updateSDKConfiguration()
                }
            }

            Section("Generation Settings") {
                VStack(alignment: .leading) {
                    Text("Temperature: \(String(format: "%.2f", defaultTemperature))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $defaultTemperature, in: 0...2, step: 0.1)
                        .onChange(of: defaultTemperature) { _ in
                            updateSDKConfiguration()
                        }
                }

                Stepper("Max Tokens: \(defaultMaxTokens)",
                       value: $defaultMaxTokens,
                       in: 500...20000,
                       step: 500)
                    .onChange(of: defaultMaxTokens) { _ in
                        updateSDKConfiguration()
                    }
            }

            Section("API Configuration") {
                Button(action: { showApiKeyEntry.toggle() }) {
                    HStack {
                        Text("API Key")
                        Spacer()
                        if !apiKey.isEmpty {
                            Text("Configured")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Text("Not Set")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
                .sheet(isPresented: $showApiKeyEntry) {
                    NavigationView {
                        Form {
                            Section {
                                SecureField("Enter API Key", text: $apiKey)
                                    .textContentType(.password)
                                    .autocapitalization(.none)
                            } header: {
                                Text("RunAnywhere API Key")
                            } footer: {
                                Text("Your API key is stored securely in the keychain")
                                    .font(.caption)
                            }
                        }
                        .navigationTitle("API Key")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Cancel") {
                                    showApiKeyEntry = false
                                }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Save") {
                                    saveApiKey()
                                    showApiKeyEntry = false
                                }
                                .disabled(apiKey.isEmpty)
                            }
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("RunAnywhere SDK", systemImage: "cube")
                        .font(.headline)
                    Text("Version 0.1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Link(destination: URL(string: "https://docs.runanywhere.ai")!) {
                    Label("Documentation", systemImage: "book")
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            loadCurrentConfiguration()
            syncWithSDKSettings()
        }
    }

    private func updateSDKConfiguration() {
        Task {
            // Update SDK generation settings
            await RunAnywhereSDK.shared.setTemperature(Float(defaultTemperature))
            await RunAnywhereSDK.shared.setMaxTokens(defaultMaxTokens)

            // Save to UserDefaults for persistence
            UserDefaults.standard.set(routingPolicy.rawValue, forKey: "routingPolicy")
            UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
            UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")

            print("SDK Configuration updated - Temperature: \(defaultTemperature), MaxTokens: \(defaultMaxTokens)")
        }
    }

    private func loadCurrentConfiguration() {
        // Load from SDK or UserDefaults
        if let savedApiKeyData = try? KeychainService.shared.retrieve(key: "runanywhere_api_key"),
           let savedApiKey = String(data: savedApiKeyData, encoding: .utf8) {
            apiKey = savedApiKey
        }

        // Load other settings from UserDefaults
        if let policyRaw = UserDefaults.standard.string(forKey: "routingPolicy"),
           let policy = RoutingPolicy(rawValue: policyRaw) {
            routingPolicy = policy
        } else {
            routingPolicy = .automatic
        }
        defaultTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
        if defaultTemperature == 0 { defaultTemperature = 0.7 }

        defaultMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        if defaultMaxTokens == 0 { defaultMaxTokens = 10000 }
    }

    private func syncWithSDKSettings() {
        Task {
            // Get current settings from SDK to ensure UI shows actual values
            let currentSettings = await RunAnywhereSDK.shared.getGenerationSettings()

            await MainActor.run {
                // Update UI with current SDK values
                self.defaultTemperature = currentSettings.temperature
                self.defaultMaxTokens = currentSettings.maxTokens
            }
        }
    }

    private func saveApiKey() {
        if let apiKeyData = apiKey.data(using: .utf8) {
            try? KeychainService.shared.save(key: "runanywhere_api_key", data: apiKeyData)
        }
        updateSDKConfiguration()
    }
}


#Preview {
    NavigationView {
        SimplifiedSettingsView()
    }
}
