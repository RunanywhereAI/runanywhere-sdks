//
//  CombinedSettingsView.swift
//  RunAnywhereAI
//
//  Combined Settings and Storage view
//  Refactored to use SettingsViewModel (MVVM pattern)
//

import SwiftUI
import RunAnywhere
import Combine

struct CombinedSettingsView: View {
    // ViewModel - all business logic is here
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        Group {
            #if os(macOS)
            macOSSettingsView
            #else
            iOSSettingsView
            #endif
        }
        .sheet(isPresented: $viewModel.showApiKeyEntry) {
            apiKeySheet
        }
        .task {
            await viewModel.loadStorageData()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - iOS Layout

    private var iOSSettingsView: some View {
        Form {
            // Generation Settings
            Section("Generation Settings") {
                VStack(alignment: .leading) {
                    Text("Temperature: \(String(format: "%.2f", viewModel.temperature))")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                    Slider(value: $viewModel.temperature, in: 0...2, step: 0.1)
                }

                Stepper("Max Tokens: \(viewModel.maxTokens)",
                       value: $viewModel.maxTokens,
                       in: 500...20000,
                       step: 500)
            }

            // API Configuration
            Section("API Configuration") {
                Button(action: { viewModel.showApiKeySheet() }) {
                    HStack {
                        Text("API Key")
                        Spacer()
                        if viewModel.isApiKeyConfigured {
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
                            await viewModel.refreshStorageData()
                        }
                    }
                    .font(AppTypography.caption)
                }
            }

            // Downloaded Models Section
            Section("Downloaded Models") {
                if viewModel.storedModels.isEmpty {
                    Text("No models downloaded yet")
                        .foregroundColor(AppColors.textSecondary)
                        .font(AppTypography.caption)
                } else {
                    ForEach(viewModel.storedModels, id: \.id) { model in
                        StoredModelRow(model: model) {
                            await viewModel.deleteModel(model)
                        }
                    }
                }
            }

            // Storage Management
            Section("Storage Management") {
                Button(action: {
                    Task {
                        await viewModel.clearCache()
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
                        await viewModel.cleanTempFiles()
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
                Toggle("Log Analytics Locally", isOn: $viewModel.analyticsLogToLocal)

                Text("When enabled, analytics events will be saved locally on your device.")
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
                                Text("\(String(format: "%.2f", viewModel.temperature))")
                                    .font(AppTypography.monospaced)
                                    .foregroundColor(AppColors.primaryAccent)
                            }
                            HStack {
                                Text("")
                                    .frame(width: 150)
                                Slider(value: $viewModel.temperature, in: 0...2, step: 0.1)
                                    .frame(maxWidth: 400)
                            }
                        }

                        HStack {
                            Text("Max Tokens")
                                .frame(width: 150, alignment: .leading)
                            Stepper("\(viewModel.maxTokens)", value: $viewModel.maxTokens, in: 500...20000, step: 500)
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

                            if viewModel.isApiKeyConfigured {
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
                                viewModel.showApiKeySheet()
                            }
                            .buttonStyle(.bordered)
                            .tint(AppColors.primaryAccent)
                        }
                    }
                }

                // Storage Overview Section
                settingsCard(title: "Storage", trailing: {
                    Button(action: {
                        Task {
                            await viewModel.refreshStorageData()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.primaryAccent)
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        storageOverviewRows
                    }
                }

                // Downloaded Models Section
                settingsCard(title: "Downloaded Models") {
                    VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                        if viewModel.storedModels.isEmpty {
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
                            ForEach(viewModel.storedModels, id: \.id) { model in
                                StoredModelRow(model: model) {
                                    await viewModel.deleteModel(model)
                                }
                                if model.id != viewModel.storedModels.last?.id {
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
                            await viewModel.clearCache()
                        }

                        storageManagementButton(
                            title: "Clean Temporary Files",
                            subtitle: "Remove temporary files and logs",
                            icon: "trash",
                            color: AppColors.primaryOrange
                        ) {
                            await viewModel.cleanTempFiles()
                        }
                    }
                }

                // Logging Configuration Section
                settingsCard(title: "Logging Configuration") {
                    VStack(alignment: .leading, spacing: AppSpacing.padding15) {
                        HStack {
                            Text("Log Analytics Locally")
                                .frame(width: 150, alignment: .leading)

                            Toggle("", isOn: $viewModel.analyticsLogToLocal)

                            Spacer()

                            Text(viewModel.analyticsLogToLocal ? "Enabled" : "Disabled")
                                .font(AppTypography.caption)
                                .foregroundColor(viewModel.analyticsLogToLocal ? AppColors.statusGreen : AppColors.textSecondary)
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
                Text(viewModel.formatBytes(viewModel.totalStorageSize))
                    .foregroundColor(AppColors.textSecondary)
            }

            HStack {
                Label("Available Space", systemImage: "externaldrive.badge.plus")
                Spacer()
                Text(viewModel.formatBytes(viewModel.availableSpace))
                    .foregroundColor(AppColors.primaryGreen)
            }

            HStack {
                Label("Models Storage", systemImage: "cpu")
                Spacer()
                Text(viewModel.formatBytes(viewModel.modelStorageSize))
                    .foregroundColor(AppColors.primaryAccent)
            }

            HStack {
                Label("Downloaded Models", systemImage: "number")
                Spacer()
                Text("\(viewModel.storedModels.count)")
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
                    SecureField("Enter API Key", text: $viewModel.apiKey)
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
                        viewModel.cancelApiKeyEntry()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.saveApiKey()
                    }
                    .disabled(viewModel.apiKey.isEmpty)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelApiKeyEntry()
                    }
                    .keyboardShortcut(.escape)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveApiKey()
                    }
                    .disabled(viewModel.apiKey.isEmpty)
                    .keyboardShortcut(.return)
                }
                #endif
            }
        }
        #if os(macOS)
        .padding(AppSpacing.large)
        #endif
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

                    Text(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .file))
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
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
                        .tint(AppColors.primaryAccent)
                        .controlSize(.mini)

                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(AppColors.primaryRed)
                        }
                        .font(AppTypography.caption2)
                        .buttonStyle(.bordered)
                        .tint(AppColors.primaryRed)
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
                Text("Downloaded:")
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

            HStack {
                Text("Size:")
                    .font(AppTypography.caption2Medium)
                Text(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .file))
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
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
