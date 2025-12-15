//
//  CombinedSettingsView.swift
//  RunAnywhereAI
//
//  Combined Settings and Storage view
//

import SwiftUI
import RunAnywhere
import Combine

struct CombinedSettingsView: View {
    // Settings state
    @State private var defaultTemperature = 0.7
    @State private var defaultMaxTokens = 10000
    @State private var showApiKeyEntry = false
    @State private var apiKey = ""
    @State private var analyticsLogToLocal = false

    // Storage state (using StorageViewModel)
    @StateObject private var storageViewModel = StorageViewModel()

    // Section expansion state
    @State private var isStorageExpanded = true
    @State private var isModelsExpanded = true

    var body: some View {
        Group {
            #if os(macOS)
            macOSSettingsView
            #else
            iOSSettingsView
            #endif
        }
        .onChange(of: defaultTemperature) {
            updateSDKConfiguration()
        }
        .onChange(of: defaultMaxTokens) {
            updateSDKConfiguration()
        }
        .sheet(isPresented: $showApiKeyEntry) {
            apiKeySheet
        }
        .onAppear {
            loadCurrentConfiguration()
            syncWithSDKSettings()
        }
        .task {
            await storageViewModel.loadData()
        }
    }

    // MARK: - iOS Layout

    private var iOSSettingsView: some View {
        Form {
            // Generation Settings
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

            // API Configuration
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

            // Storage Overview Section
            Section {
                storageOverviewRows
            } header: {
                HStack {
                    Text("Storage Overview")
                    Spacer()
                    Button("Refresh") {
                        Task {
                            await storageViewModel.refreshData()
                        }
                    }
                    .font(AppTypography.caption)
                }
            }

            // Downloaded Models Section
            Section("Downloaded Models") {
                if storageViewModel.storedModels.isEmpty {
                    Text("No models downloaded yet")
                        .foregroundColor(AppColors.textSecondary)
                        .font(AppTypography.caption)
                } else {
                    ForEach(storageViewModel.storedModels, id: \.id) { model in
                        StoredModelRow(model: model) {
                            await storageViewModel.deleteModel(model)
                        }
                    }
                }
            }

            // Storage Management
            Section("Storage Management") {
                Button(action: {
                    Task {
                        await storageViewModel.clearCache()
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(AppColors.primaryRed)
                        Text("Clear Cache")
                            .foregroundColor(AppColors.primaryRed)
                        Spacer()
                    }
                }

                Button(action: {
                    Task {
                        await storageViewModel.cleanTempFiles()
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(AppColors.primaryOrange)
                        Text("Clean Temporary Files")
                            .foregroundColor(AppColors.primaryOrange)
                        Spacer()
                    }
                }
            }

            // Logging Configuration
            Section("Logging Configuration") {
                Toggle("Log Analytics Locally", isOn: $analyticsLogToLocal)
                    .onChange(of: analyticsLogToLocal) { _, newValue in
                        KeychainHelper.save(key: "analyticsLogToLocal", data: newValue)
                    }

                Text("When enabled, analytics events will be logged locally for debugging purposes.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            // About
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
    }

    // MARK: - macOS Layout

    private var macOSSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxLarge) {
                Text("Settings")
                    .font(AppTypography.largeTitleBold)
                    .padding(.bottom, AppSpacing.medium)

                // Generation Settings Section
                settingsCard(title: "Generation Settings") {
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
                }

                // API Configuration Section
                settingsCard(title: "API Configuration") {
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
                }

                // Storage Overview Section
                settingsCard(title: "Storage", trailing: {
                    Button(action: {
                        Task {
                            await storageViewModel.refreshData()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        storageOverviewRows
                    }
                }

                // Downloaded Models Section
                settingsCard(title: "Downloaded Models") {
                    VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                        if storageViewModel.storedModels.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: AppSpacing.mediumLarge) {
                                    Image(systemName: "cube")
                                        .font(AppTypography.system48)
                                        .foregroundColor(AppColors.textSecondary.opacity(0.5))
                                    Text("No models downloaded yet")
                                        .foregroundColor(AppColors.textSecondary)
                                        .font(AppTypography.callout)
                                }
                                .padding(.vertical, AppSpacing.xxLarge)
                                Spacer()
                            }
                        } else {
                            ForEach(storageViewModel.storedModels, id: \.id) { model in
                                StoredModelRow(model: model) {
                                    await storageViewModel.deleteModel(model)
                                }
                                if model.id != storageViewModel.storedModels.last?.id {
                                    Divider()
                                        .padding(.vertical, AppSpacing.xSmall)
                                }
                            }
                        }
                    }
                }

                // Storage Management Section
                settingsCard(title: "Storage Management") {
                    VStack(spacing: AppSpacing.large) {
                        storageManagementButton(
                            title: "Clear Cache",
                            subtitle: "Free up space by clearing cached data",
                            icon: "trash",
                            color: AppColors.primaryRed
                        ) {
                            await storageViewModel.clearCache()
                        }

                        storageManagementButton(
                            title: "Clean Temporary Files",
                            subtitle: "Remove temporary files and logs",
                            icon: "trash",
                            color: AppColors.primaryOrange
                        ) {
                            await storageViewModel.cleanTempFiles()
                        }
                    }
                }

                // Logging Configuration Section
                settingsCard(title: "Logging Configuration") {
                    VStack(alignment: .leading, spacing: AppSpacing.padding15) {
                        HStack {
                            Text("Log Analytics Locally")
                                .frame(width: 150, alignment: .leading)

                            Toggle("", isOn: $analyticsLogToLocal)
                                .onChange(of: analyticsLogToLocal) { _, newValue in
                                    KeychainHelper.save(key: "analyticsLogToLocal", data: newValue)
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
                }

                // About Section
                settingsCard(title: "About") {
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
                    }
                }

                Spacer()
            }
            .padding(AppSpacing.xxLarge)
            .frame(maxWidth: AppLayout.maxContentWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }

    // MARK: - Reusable Components

    private var storageOverviewRows: some View {
        Group {
            HStack {
                Label("Total Usage", systemImage: "externaldrive")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: storageViewModel.totalStorageSize, countStyle: .file))
                    .foregroundColor(AppColors.textSecondary)
            }

            HStack {
                Label("Available Space", systemImage: "externaldrive.badge.plus")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: storageViewModel.availableSpace, countStyle: .file))
                    .foregroundColor(AppColors.primaryGreen)
            }

            HStack {
                Label("Models Storage", systemImage: "cpu")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: storageViewModel.modelStorageSize, countStyle: .file))
                    .foregroundColor(AppColors.primaryBlue)
            }

            HStack {
                Label("Downloaded Models", systemImage: "number")
                Spacer()
                Text("\(storageViewModel.storedModels.count)")
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textSecondary)

            content()
                .padding(AppSpacing.large)
                .background(AppColors.backgroundSecondary)
                .cornerRadius(AppSpacing.cornerRadiusLarge)
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
            HStack {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                trailing()
            }

            content()
                .padding(AppSpacing.large)
                .background(AppColors.backgroundSecondary)
                .cornerRadius(AppSpacing.cornerRadiusLarge)
        }
    }

    @ViewBuilder
    private func storageManagementButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                Spacer()
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(AppSpacing.mediumLarge)
        .background(color.opacity(0.1))
        .cornerRadius(AppSpacing.cornerRadiusRegular)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                .stroke(color.opacity(0.3), lineWidth: AppSpacing.strokeRegular)
        )
    }

    private var apiKeySheet: some View {
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

    // MARK: - Configuration Methods

    private func updateSDKConfiguration() {
        UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
        UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")

        print("Configuration saved - Temperature: \(defaultTemperature), MaxTokens: \(defaultMaxTokens)")
    }

    private func loadCurrentConfiguration() {
        if let savedApiKeyData = try? KeychainService.shared.retrieve(key: "runanywhere_api_key"),
           let savedApiKey = String(data: savedApiKeyData, encoding: .utf8) {
            apiKey = savedApiKey
        }

        defaultTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
        if defaultTemperature == 0 { defaultTemperature = 0.7 }

        defaultMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        if defaultMaxTokens == 0 { defaultMaxTokens = 10000 }

        analyticsLogToLocal = KeychainHelper.loadBool(key: "analyticsLogToLocal", defaultValue: false)
    }

    private func syncWithSDKSettings() {
        // Load settings from UserDefaults
        // In the new architecture, these settings are applied per-request
    }

    private func saveApiKey() {
        if let apiKeyData = apiKey.data(using: .utf8) {
            try? KeychainService.shared.save(key: "runanywhere_api_key", data: apiKeyData)
        }
        updateSDKConfiguration()
    }
}

// MARK: - Supporting Views

private struct StoredModelRow: View {
    let model: StoredModel
    let onDelete: () async -> Void
    @State private var showingDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(model.name)
                        .font(AppTypography.subheadlineMedium)

                    HStack(spacing: AppSpacing.smallMedium) {
                        Text(model.format.rawValue.uppercased())
                            .font(AppTypography.caption2)
                            .padding(.horizontal, AppSpacing.small)
                            .padding(.vertical, AppSpacing.xxSmall)
                            .background(AppColors.badgeBlue)
                            .cornerRadius(AppSpacing.cornerRadiusSmall)

                        if let framework = model.framework {
                            Text(framework.displayName)
                                .font(AppTypography.caption2)
                                .padding(.horizontal, AppSpacing.small)
                                .padding(.vertical, AppSpacing.xxSmall)
                                .background(AppColors.badgeGreen)
                                .cornerRadius(AppSpacing.cornerRadiusSmall)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xSmall) {
                    Text(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .file))
                        .font(AppTypography.captionMedium)

                    HStack(spacing: AppSpacing.xSmall) {
                        Button(showingDetails ? "Hide" : "Details") {
                            withAnimation {
                                showingDetails.toggle()
                            }
                        }
                        .font(AppTypography.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(AppColors.primaryRed)
                        }
                        .font(AppTypography.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isDeleting)
                    }
                }
            }

            if showingDetails {
                modelDetailsView
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
        .alert("Delete Model", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    await onDelete()
                    isDeleting = false
                }
            }
        } message: {
            Text("Are you sure you want to delete \(model.name)? This action cannot be undone.")
        }
    }

    private var modelDetailsView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Text("Format:")
                    .font(AppTypography.caption2Medium)
                Text(model.format.rawValue.uppercased())
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }

            if let framework = model.framework {
                HStack {
                    Text("Framework:")
                        .font(AppTypography.caption2Medium)
                    Text(framework.displayName)
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            if let contextLength = model.contextLength {
                HStack {
                    Text("Context Length:")
                        .font(AppTypography.caption2Medium)
                    Text("\(contextLength) tokens")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Path:")
                    .font(AppTypography.caption2Medium)
                Text(model.path.path)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Created:")
                    .font(AppTypography.caption2Medium)
                Text(model.createdDate, style: .date)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }

            if let lastUsed = model.lastUsed {
                HStack {
                    Text("Last used:")
                        .font(AppTypography.caption2Medium)
                    Text(lastUsed, style: .relative)
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .padding(.top, AppSpacing.xSmall)
        .padding(.horizontal, AppSpacing.smallMedium)
        .padding(.vertical, AppSpacing.small)
        .background(AppColors.backgroundTertiary)
        .cornerRadius(AppSpacing.cornerRadiusRegular)
    }
}

#Preview {
    NavigationView {
        CombinedSettingsView()
    }
}
