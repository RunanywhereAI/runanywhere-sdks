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
    @StateObject private var toolViewModel = ToolSettingsViewModel.shared

    var body: some View {
        Group {
            #if os(macOS)
            MacOSSettingsContent(viewModel: viewModel, toolViewModel: toolViewModel)
            #else
            IOSSettingsContent(viewModel: viewModel, toolViewModel: toolViewModel)
            #endif
        }
        .adaptiveSheet(isPresented: $viewModel.showApiKeyEntry) {
            ApiConfigurationSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.loadStorageData()
            await toolViewModel.refreshRegisteredTools()
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
        .alert("Restart Required", isPresented: $viewModel.showRestartAlert) {
            Button("OK") {
                viewModel.showRestartAlert = false
            }
        } message: {
            Text("Please restart the app for the new API configuration to take effect. The SDK will be reinitialized with your custom settings.")
        }
    }
}

// MARK: - iOS Layout

private struct IOSSettingsContent: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var toolViewModel: ToolSettingsViewModel

    var body: some View {
        Form {
            // Generation Settings
            Section("Generation Settings") {
                VStack(alignment: .leading) {
                    Text("Temperature: \(String(format: "%.2f", viewModel.temperature))")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                    Slider(value: $viewModel.temperature, in: 0...2, step: 0.1)
                }

                Stepper(
                    "Max Tokens: \(viewModel.maxTokens)",
                    value: $viewModel.maxTokens,
                    in: 500...20000,
                    step: 500
                )
            }

            // System Prompt
            Section {
                TextField("Enter system prompt...", text: $viewModel.systemPrompt, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("System Prompt")
            } footer: {
                Text("Optional instructions that define AI behavior and response style.")
                    .font(AppTypography.caption)
            }

            // Tool Calling Settings
            ToolSettingsSection(viewModel: toolViewModel)

            // API Configuration (for testing custom backend)
            Section {
                Button(
                    action: { viewModel.showApiKeySheet() },
                    label: {
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
                )

                HStack {
                    Text("Base URL")
                    Spacer()
                    if viewModel.isBaseURLConfigured {
                        Text("Configured")
                            .foregroundColor(AppColors.statusGreen)
                            .font(AppTypography.caption)
                    } else {
                        Text("Using Default")
                            .foregroundColor(AppColors.textSecondary)
                            .font(AppTypography.caption)
                    }
                }

                if viewModel.isApiConfigurationComplete {
                    Button(
                        action: { viewModel.clearApiConfiguration() },
                        label: {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(AppColors.primaryRed)
                                Text("Clear Custom Configuration")
                                    .foregroundColor(AppColors.primaryRed)
                            }
                        }
                    )
                }
            } header: {
                Text("API Configuration (Testing)")
            } footer: {
                Text("Configure custom API key and base URL for testing. Requires app restart to take effect.")
                    .font(AppTypography.caption)
            }

            // Logging Configuration
            Section("Logging Configuration") {
                Toggle("Log Analytics Locally", isOn: $viewModel.analyticsLogToLocal)

                Text("When enabled, analytics events will be saved locally on your device.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            // Performance
            Section("Performance") {
                NavigationLink(destination: BenchmarkDashboardView()) {
                    Label("Benchmarks", systemImage: "gauge.with.dots.needle.33percent")
                }
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

                if let docsURL = URL(string: "https://docs.runanywhere.ai") {
                    Link(destination: docsURL) {
                        Label("Documentation", systemImage: "book")
                    }
                }
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - macOS Layout

private struct MacOSSettingsContent: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var toolViewModel: ToolSettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxLarge) {
                Text("Settings")
                    .font(AppTypography.largeTitleBold)
                    .padding(.bottom, AppSpacing.medium)

                GenerationSettingsCard(viewModel: viewModel)
                ToolSettingsCard(viewModel: toolViewModel)
                APIConfigurationCard(viewModel: viewModel)
                LoggingConfigurationCard(viewModel: viewModel)
                BenchmarksCard()
                AboutCard()

                Spacer()
            }
            .padding(AppSpacing.xxLarge)
            .frame(maxWidth: AppLayout.maxContentWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - macOS Settings Cards

private struct GenerationSettingsCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard(title: "Generation Settings") {
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
                    Stepper(
                        "\(viewModel.maxTokens)",
                        value: $viewModel.maxTokens,
                        in: 500...20000,
                        step: 500
                    )
                    .frame(maxWidth: 200)
                }

                VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                    HStack(alignment: .top) {
                        Text("System Prompt")
                            .frame(width: 150, alignment: .leading)
                        TextField("Enter system prompt...", text: $viewModel.systemPrompt, axis: .vertical)
                            .lineLimit(3...8)
                            .textFieldStyle(.plain)
                            .padding(AppSpacing.small)
                            .background(AppColors.backgroundTertiary)
                            .cornerRadius(AppSpacing.cornerRadiusRegular)
                            .frame(maxWidth: 400)
                    }
                }
            }
        }
    }
}

private struct APIConfigurationCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard(title: "API Configuration (Testing)") {
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
                }

                HStack {
                    Text("Base URL")
                        .frame(width: 150, alignment: .leading)

                    if viewModel.isBaseURLConfigured {
                        Text("Configured")
                            .foregroundColor(AppColors.statusGreen)
                            .font(AppTypography.caption)
                    } else {
                        Text("Using Default")
                            .foregroundColor(AppColors.textSecondary)
                            .font(AppTypography.caption)
                    }

                    Spacer()
                }

                HStack {
                    Button("Configure") {
                        viewModel.showApiKeySheet()
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.primaryAccent)

                    if viewModel.isApiConfigurationComplete {
                        Button("Clear") {
                            viewModel.clearApiConfiguration()
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.primaryRed)
                    }
                }

                Text("Configure custom API key and base URL for testing. Requires app restart.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }
}

private struct StorageCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsCardWithTrailing(
            title: "Storage",
            trailing: {
                Button(
                    action: {
                        Task {
                            await viewModel.refreshStorageData()
                        }
                    },
                    label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                )
                .buttonStyle(.bordered)
                .tint(AppColors.primaryAccent)
            },
            content: {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    StorageOverviewRows(viewModel: viewModel)
                }
            }
        )
    }
}

private struct DownloadedModelsCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard(title: "Downloaded Models") {
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
    }
}

private struct StorageManagementCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard(title: "Storage Management") {
            VStack(spacing: AppSpacing.large) {
                StorageManagementButton(
                    title: "Clear Cache",
                    subtitle: "Free up space by clearing cached data",
                    icon: "trash",
                    color: AppColors.primaryRed
                ) {
                    await viewModel.clearCache()
                }

                StorageManagementButton(
                    title: "Clean Temporary Files",
                    subtitle: "Remove temporary files and logs",
                    icon: "trash",
                    color: AppColors.primaryOrange
                ) {
                    await viewModel.cleanTempFiles()
                }
            }
        }
    }
}

private struct LoggingConfigurationCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard(title: "Logging Configuration") {
            VStack(alignment: .leading, spacing: AppSpacing.padding15) {
                HStack {
                    Text("Log Analytics Locally")
                        .frame(width: 150, alignment: .leading)

                    Toggle("", isOn: $viewModel.analyticsLogToLocal)

                    Spacer()

                    Text(viewModel.analyticsLogToLocal ? "Enabled" : "Disabled")
                        .font(AppTypography.caption)
                        .foregroundColor(
                            viewModel.analyticsLogToLocal
                                ? AppColors.statusGreen
                                : AppColors.textSecondary
                        )
                }

                Text("When enabled, analytics events will be logged locally instead of being sent to the server.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }
}

private struct AboutCard: View {
    var body: some View {
        SettingsCard(title: "About") {
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

                if let docsURL = URL(string: "https://docs.runanywhere.ai") {
                    Link(destination: docsURL) {
                        HStack {
                            Image(systemName: "book")
                            Text("Documentation")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Reusable Components

private struct StorageOverviewRows: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
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
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
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
}

private struct SettingsCardWithTrailing<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
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
}

private struct StorageManagementButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () async -> Void

    var body: some View {
        Button(
            action: {
                Task {
                    await action()
                }
            },
            label: {
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
        )
        .buttonStyle(.plain)
        .padding(AppSpacing.mediumLarge)
        .background(color.opacity(0.1))
        .cornerRadius(AppSpacing.cornerRadiusRegular)
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                .stroke(color.opacity(0.3), lineWidth: AppSpacing.strokeRegular)
        )
    }
}

private struct ApiConfigurationSheet: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Enter API Key", text: $viewModel.apiKey)
                        .textContentType(.password)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Your API key for authenticating with the backend")
                        .font(AppTypography.caption)
                }

                Section {
                    TextField("https://api.example.com", text: $viewModel.baseURL)
                        .textContentType(.URL)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        #endif
                } header: {
                    Text("Base URL")
                } footer: {
                    Text("The backend API URL (e.g., https://api.runanywhere.ai)")
                        .font(AppTypography.caption)
                }

                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Label("Important", systemImage: "exclamationmark.triangle")
                            .foregroundColor(AppColors.primaryOrange)
                            .font(AppTypography.subheadlineMedium)

                        Text("After saving, you must restart the app for changes to take effect. The SDK will reinitialize with your custom configuration.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: AppLayout.macOSMinWidth, idealWidth: 500, minHeight: 350, idealHeight: 400)
            #endif
            .navigationTitle("API Configuration")
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
                        viewModel.saveApiConfiguration()
                    }
                    .disabled(viewModel.apiKey.isEmpty || viewModel.baseURL.isEmpty)
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
                        viewModel.saveApiConfiguration()
                    }
                    .disabled(viewModel.apiKey.isEmpty || viewModel.baseURL.isEmpty)
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

    private var isDeletable: Bool {
        // Platform models (built-in) can't be deleted
        guard let framework = model.framework else { return false }
        return framework != .foundationModels && framework != .systemTTS
    }

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

                        // ONLY show delete button if deletable
                        if isDeletable {
                            Button(
                                action: {
                                    showingDeleteConfirmation = true
                                },
                                label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(AppColors.primaryRed)
                                }
                            )
                            .font(AppTypography.caption2)
                            .buttonStyle(.bordered)
                            .tint(AppColors.primaryRed)
                            .controlSize(.mini)
                            .disabled(isDeleting)
                        }
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

private struct BenchmarksCard: View {
    var body: some View {
        SettingsCard(title: "Performance") {
            VStack(alignment: .leading, spacing: AppSpacing.padding15) {
                NavigationLink(destination: BenchmarkDashboardView()) {
                    HStack {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .foregroundColor(AppColors.primaryAccent)
                        Text("Benchmarks")
                        Spacer()
                        #if !os(macOS)
                        Image(systemName: "chevron.right")
                            .foregroundColor(AppColors.textSecondary)
                        #endif
                    }
                }
                .buttonStyle(.plain)

                Text("Measure performance of on-device AI models.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }
}

#Preview {
    NavigationView {
        CombinedSettingsView()
    }
}
