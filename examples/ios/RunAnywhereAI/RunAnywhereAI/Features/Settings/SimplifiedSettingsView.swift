//
//  SimplifiedSettingsView.swift
//  RunAnywhereAI
//
//  A simplified settings view that demonstrates SDK configuration
//

import SwiftUI
import RunAnywhere
import Combine

struct SimplifiedSettingsView: View {
    @State private var routingPolicy = RoutingPolicy.automatic
    @State private var defaultTemperature = 0.7
    @State private var defaultMaxTokens = 10000
    @State private var showApiKeyEntry = false
    @State private var apiKey = ""
    @State private var analyticsLogToLocal = false

    var body: some View {
        Group {
            #if os(macOS)
            // macOS: Custom layout without Form
            ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxLarge) {
                Text("Settings")
                    .font(AppTypography.largeTitleBold)
                    .padding(.bottom, AppSpacing.medium)

                // SDK Configuration Section
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    Text("SDK Configuration")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: AppSpacing.padding15) {
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
                    .padding(AppSpacing.large)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
                }

                // Generation Settings Section
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    Text("Generation Settings")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                            HStack {
                                Text("Temperature")
                                    .frame(width: 150, alignment: .leading)
                                Text("\(String(format: "%.2f", defaultTemperature))")
                                    .font(AppTypography.monospaced)
                                    .foregroundColor(AppColors.primaryAccent)
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
                    .padding(AppSpacing.large)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
                }

                // API Configuration Section
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    Text("API Configuration")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: AppSpacing.padding15) {
                        HStack {
                            Text("API Key")
                                .frame(width: 150, alignment: .leading)

                            if !apiKey.isEmpty {
                                Text("Configured")
                                    .foregroundColor(AppColors.statusGreen)
                                    .font(AppTypography.caption)
                            } else {
                                Text("Not Set")
                                    .foregroundColor(AppColors.statusOrange)
                                    .font(AppTypography.caption)
                            }

                            Spacer()

                            Button("Configure") {
                                showApiKeyEntry = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(AppSpacing.large)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
                }

                // Logging Configuration Section
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    Text("Logging Configuration")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: AppSpacing.padding15) {
                        HStack {
                            Text("Log Analytics Locally")
                                .frame(width: 150, alignment: .leading)

                            Toggle("", isOn: $analyticsLogToLocal)
                                .onChange(of: analyticsLogToLocal) { _, newValue in
                                    // Save to keychain for persistence
                                    KeychainHelper.save(key: "analyticsLogToLocal", data: newValue)
                                    // Note: Analytics settings are now applied per-request in the new architecture
                                }

                            Spacer()

                            Text(analyticsLogToLocal ? "Enabled" : "Disabled")
                                .font(AppTypography.caption)
                                .foregroundColor(analyticsLogToLocal ? AppColors.statusGreen : AppColors.textSecondary)
                        }

                        Text("When enabled, analytics events will be logged locally instead of being sent to the server.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(AppSpacing.large)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
                }

                // About Section
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    Text("About")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: AppSpacing.padding15) {
                        HStack {
                            Image(systemName: "cube")
                                .foregroundColor(AppColors.primaryAccent)
                            VStack(alignment: .leading) {
                                Text("RunAnywhere SDK")
                                    .font(AppTypography.headline)
                                Text("Version 0.1")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textSecondary)
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
                    .padding(AppSpacing.large)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
                }

                Spacer()
            }
            .padding(AppSpacing.xxLarge)
            .frame(maxWidth: AppLayout.maxContentWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
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
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
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
                                .foregroundColor(AppColors.statusGreen)
                                .font(AppTypography.caption)
                        } else {
                            Text("Not Set")
                                .foregroundColor(AppColors.statusOrange)
                                .font(AppTypography.caption)
                        }
                    }
                }
            }

            Section("Logging Configuration") {
                Toggle("Log Analytics Locally", isOn: $analyticsLogToLocal)
                    .onChange(of: analyticsLogToLocal) { _, newValue in
                        // Save to keychain for persistence
                        KeychainHelper.save(key: "analyticsLogToLocal", data: newValue)
                        // Note: Analytics settings are now applied per-request in the new architecture
                    }

                Text("When enabled, analytics events will be logged locally for debugging purposes.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Section {
                VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                    Label("RunAnywhere SDK", systemImage: "cube")
                        .font(AppTypography.headline)
                    Text("Version 0.1")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
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
                            .font(AppTypography.caption)
                    }
                }
                #if os(macOS)
                .formStyle(.grouped)
                .frame(minWidth: AppLayout.macOSMinWidth, idealWidth: 450, minHeight: 200, idealHeight: 250)
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
            .padding(AppSpacing.large)
            #endif
        }
        .onAppear {
            loadCurrentConfiguration()
            syncWithSDKSettings()
        }
    }

    private func updateSDKConfiguration() {
        // Note: In the new architecture, settings are applied per-request
        // Save to UserDefaults for persistence
            UserDefaults.standard.set(routingPolicy.rawValue, forKey: "routingPolicy")
            UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
            UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")

            print("Configuration saved - Temperature: \(defaultTemperature), MaxTokens: \(defaultMaxTokens)")
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

        // Load analytics logging setting from keychain
        analyticsLogToLocal = KeychainHelper.loadBool(key: "analyticsLogToLocal", defaultValue: false)
    }

    private func syncWithSDKSettings() {
        // Load settings from UserDefaults
        // In the new architecture, these settings are applied per-request
        // No need to get them from SDK anymore
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
