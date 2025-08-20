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
        Group {
            #if os(macOS)
            // macOS: Custom layout without Form
            ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 10)
                
                // SDK Configuration Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("SDK Configuration")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("Routing Policy")
                                .frame(width: 150, alignment: .leading)
                            Picker("", selection: $routingPolicy) {
                                Text("Automatic").tag(RoutingPolicy.automatic)
                                Text("Device Only").tag(RoutingPolicy.deviceOnly)
                                Text("Prefer Device").tag(RoutingPolicy.preferDevice)
                                Text("Prefer Cloud").tag(RoutingPolicy.preferCloud)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 400)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // Generation Settings Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Generation Settings")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Temperature")
                                    .frame(width: 150, alignment: .leading)
                                Text("\(String(format: "%.2f", defaultTemperature))")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.accentColor)
                            }
                            HStack {
                                Text("")
                                    .frame(width: 150)
                                Slider(value: $defaultTemperature, in: 0...2, step: 0.1)
                                    .frame(maxWidth: 400)
                            }
                        }
                        
                        HStack {
                            Text("Max Tokens")
                                .frame(width: 150, alignment: .leading)
                            Stepper("\(defaultMaxTokens)", value: $defaultMaxTokens, in: 500...20000, step: 500)
                                .frame(maxWidth: 200)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // API Configuration Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("API Configuration")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("API Key")
                                .frame(width: 150, alignment: .leading)
                            
                            if !apiKey.isEmpty {
                                Text("Configured")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Text("Not Set")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                            
                            Spacer()
                            
                            Button("Configure") {
                                showApiKeyEntry = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // About Section
                VStack(alignment: .leading, spacing: 20) {
                    Text("About")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "cube")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text("RunAnywhere SDK")
                                    .font(.headline)
                                Text("Version 0.1")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Link(destination: URL(string: "https://docs.runanywhere.ai")!) {
                            HStack {
                                Image(systemName: "book")
                                Text("Documentation")
                            }
                        }
                        .buttonStyle(.link)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                Spacer()
            }
            .padding(30)
            .frame(maxWidth: 800, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        // iOS: Keep the Form-based layout
        Form {
            Section("SDK Configuration") {
                Picker("Routing Policy", selection: $routingPolicy) {
                    Text("Automatic").tag(RoutingPolicy.automatic)
                    Text("Device Only").tag(RoutingPolicy.deviceOnly)
                    Text("Prefer Device").tag(RoutingPolicy.preferDevice)
                    Text("Prefer Cloud").tag(RoutingPolicy.preferCloud)
                }
            }

            Section("Generation Settings") {
                VStack(alignment: .leading) {
                    Text("Temperature: \(String(format: "%.2f", defaultTemperature))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $defaultTemperature, in: 0...2, step: 0.1)
                }

                Stepper("Max Tokens: \(defaultMaxTokens)",
                       value: $defaultMaxTokens,
                       in: 500...20000,
                       step: 500)
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
        #endif
        }
        .onChange(of: routingPolicy) { _ in
            updateSDKConfiguration()
        }
        .onChange(of: defaultTemperature) { _ in
            updateSDKConfiguration()
        }
        .onChange(of: defaultMaxTokens) { _ in
            updateSDKConfiguration()
        }
        .sheet(isPresented: $showApiKeyEntry) {
            NavigationStack {
                Form {
                    Section {
                        SecureField("Enter API Key", text: $apiKey)
                            .textContentType(.password)
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                    } header: {
                        Text("RunAnywhere API Key")
                    } footer: {
                        Text("Your API key is stored securely in the keychain")
                            .font(.caption)
                    }
                }
                #if os(macOS)
                .formStyle(.grouped)
                .frame(minWidth: 400, idealWidth: 450, minHeight: 200, idealHeight: 250)
                #endif
                .navigationTitle("API Key")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(iOS)
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
                    #else
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showApiKeyEntry = false
                        }
                        .keyboardShortcut(.escape)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveApiKey()
                            showApiKeyEntry = false
                        }
                        .disabled(apiKey.isEmpty)
                        .keyboardShortcut(.return)
                    }
                    #endif
                }
            }
            #if os(macOS)
            .padding()
            #endif
        }
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