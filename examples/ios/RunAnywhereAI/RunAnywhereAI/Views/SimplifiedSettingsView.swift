//
//  SimplifiedSettingsView.swift
//  RunAnywhereAI
//
//  A simplified settings view that demonstrates SDK configuration
//

import SwiftUI
import RunAnywhereSDK

struct SimplifiedSettingsView: View {
    @State private var enableCloudRouting = false
    @State private var privacyMode = true
    @State private var routingPolicy = RoutingPolicy.automatic
    @State private var defaultTemperature = 0.7
    @State private var defaultMaxTokens = 256
    @State private var showApiKeyEntry = false
    @State private var apiKey = ""

    var body: some View {
        Form {
            Section("SDK Configuration") {
                Toggle("Enable Cloud Routing", isOn: $enableCloudRouting)
                    .onChange(of: enableCloudRouting) { _ in
                        updateSDKConfiguration()
                    }

                Toggle("Privacy Mode", isOn: $privacyMode)
                    .onChange(of: privacyMode) { _ in
                        updateSDKConfiguration()
                    }

                Picker("Routing Policy", selection: $routingPolicy) {
                    Text("Automatic").tag(RoutingPolicy.automatic)
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
                       in: 50...4096,
                       step: 50)
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
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Link(destination: URL(string: "https://docs.runanywhere.ai")!) {
                    Label("Documentation", systemImage: "book")
                }

                Link(destination: URL(string: "https://github.com/runanywhere/sdk")!) {
                    Label("GitHub", systemImage: "link")
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            loadCurrentConfiguration()
        }
    }

    private func updateSDKConfiguration() {
        let config = Configuration(
            apiKey: apiKey.isEmpty ? nil : apiKey,
            routingPolicy: routingPolicy,
            enableCloudRouting: enableCloudRouting,
            privacyMode: privacyMode,
            defaultGenerationOptions: GenerationOptions(
                temperature: defaultTemperature,
                maxTokens: defaultMaxTokens
            )
        )

        // Note: In a real app, you would update the SDK configuration
        // RunAnywhereSDK.shared.updateConfiguration(config)
        print("Configuration updated: \(config)")
    }

    private func loadCurrentConfiguration() {
        // Load from SDK or UserDefaults
        if let savedApiKey = KeychainService.shared.retrieve(key: "runanywhere_api_key") {
            apiKey = savedApiKey
        }

        // Load other settings from UserDefaults
        enableCloudRouting = UserDefaults.standard.bool(forKey: "enableCloudRouting")
        privacyMode = UserDefaults.standard.bool(forKey: "privacyMode")
        if let policyRaw = UserDefaults.standard.string(forKey: "routingPolicy"),
           let policy = RoutingPolicy(rawValue: policyRaw) {
            routingPolicy = policy
        } else {
            routingPolicy = .automatic
        }
        defaultTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
        if defaultTemperature == 0 { defaultTemperature = 0.7 }

        defaultMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        if defaultMaxTokens == 0 { defaultMaxTokens = 256 }
    }

    private func saveApiKey() {
        KeychainService.shared.save(key: "runanywhere_api_key", value: apiKey)
        updateSDKConfiguration()
    }
}


#Preview {
    NavigationView {
        SimplifiedSettingsView()
    }
}
