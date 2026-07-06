//
//  CombinedSettingsView.swift
//  RunAnywhereAI
//
//  Combined Settings and Storage view
//  Refactored to use SettingsViewModel (MVVM pattern)
//

// swiftlint:disable file_length

import SwiftUI
import RunAnywhere
import Combine

struct CombinedSettingsView: View {
    // ViewModel - all business logic is here
    @ObservedObject private var viewModel = SettingsViewModel.shared
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
            Text(
                "Please restart the app for the new API configuration to take effect. "
                + "The SDK will be reinitialized with your custom settings."
            )
        }
    }
}

// MARK: - Helpers

@MainActor
private func thinkingModeDescription(for viewModel: SettingsViewModel) -> String {
    guard viewModel.loadedModelSupportsThinking else {
        return "Not available for the currently loaded model."
    }
    return viewModel.thinkingModeEnabled
        ? "Model will use its default thinking/reasoning mode."
        : "Thinking disabled. The model will skip its reasoning step."
}

// MARK: - iOS Layout

private struct IOSSettingsContent: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var toolViewModel: ToolSettingsViewModel

    var body: some View {
        Form {
            Section {
                TextField("How should RunAnywhere respond?", text: $viewModel.systemPrompt, axis: .vertical)
                    .lineLimit(3...8)

                VStack(alignment: .leading) {
                    Text("Creativity: \(String(format: "%.2f", viewModel.temperature))")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                    Slider(value: $viewModel.temperature, in: 0...2, step: 0.1)
                }

                Toggle("Thinking Mode", isOn: $viewModel.thinkingModeEnabled)
                    .disabled(!viewModel.loadedModelSupportsThinking)

                Text(thinkingModeDescription(for: viewModel))
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            } header: {
                Text("Personalization")
            } footer: {
                Text("Customize tone, reasoning, and default assistant behavior.")
                    .font(AppTypography.caption)
            }

            Section {
                NavigationLink(destination: SimplifiedModelsView()) {
                    SettingsNavigationRow(
                        icon: "square.stack.3d.up",
                        color: AppColors.primaryAccent,
                        title: "Manage Downloads",
                        subtitle: "Choose, download, and remove local models"
                    )
                }

                HStack {
                    Label("Max Response Length", systemImage: "text.line.last.and.arrowtriangle.forward")
                    Spacer()
                    Stepper(
                        "\(viewModel.maxTokens)",
                        value: $viewModel.maxTokens,
                        in: 500...20000,
                        step: 500
                    )
                    .labelsHidden()
                }
            } header: {
                Text("Models")
            } footer: {
                Text("RunAnywhere supports multiple backends. Model labels explain which engine powers each capability.")
                    .font(AppTypography.caption)
            }

            Section("Voice & Input") {
                NavigationLink(destination: VoiceAssistantView()) {
                    SettingsNavigationRow(
                        icon: "mic.circle",
                        color: AppColors.primaryAccent,
                        title: "Talk Mode",
                        subtitle: "Set up speech, conversation, and voice models"
                    )
                }

                #if os(iOS)
                NavigationLink(destination: VoiceDictationManagementView()) {
                    SettingsNavigationRow(
                        icon: "keyboard",
                        color: .indigo,
                        title: "Private Dictation Keyboard",
                        subtitle: "Dictate into other apps on-device"
                    )
                }
                #endif
            }

            Section("Privacy") {
                Label("Chats and downloads stay on this device", systemImage: "lock.shield")
                    .foregroundColor(AppColors.textPrimary)
                Toggle("Log Analytics Locally", isOn: $viewModel.analyticsLogToLocal)

                Text("When enabled, analytics events are saved locally on your device.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Section {
                NavigationLink(destination: ConsumerAdvancedHubView()) {
                    SettingsNavigationRow(
                        icon: "slider.horizontal.3",
                        color: AppColors.primaryPurple,
                        title: "SDK Workbench",
                        subtitle: "Voice utilities, tools, storage, benchmarks, and diagnostics"
                    )
                }

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
                Text("Advanced")
            } footer: {
                Text("Developer controls are kept here so the main app stays assistant-first.")
                    .font(AppTypography.caption)
            }

            ToolSettingsSection(viewModel: toolViewModel)

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
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .cornerRadius(AppSpacing.cornerRadiusRegular)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
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

                AssistantSettingsCard()
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

private struct AssistantSettingsCard: View {
    var body: some View {
        SettingsCard(title: "Assistant") {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                NavigationLink(destination: SimplifiedModelsView()) {
                    SettingsNavigationRow(
                        icon: "square.stack.3d.up",
                        color: AppColors.primaryAccent,
                        title: "Manage Downloads",
                        subtitle: "Choose and identify models across all local backends"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(destination: VoiceAssistantView()) {
                    SettingsNavigationRow(
                        icon: "mic.circle",
                        color: AppColors.primaryAccent,
                        title: "Talk Mode",
                        subtitle: "Configure speech, conversation, and voice models"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(destination: ConsumerAdvancedHubView()) {
                    SettingsNavigationRow(
                        icon: "slider.horizontal.3",
                        color: AppColors.primaryPurple,
                        title: "SDK Workbench",
                        subtitle: "Voice utilities, storage, tools, benchmarks, and diagnostics"
                    )
                }
                .buttonStyle(.plain)

                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundColor(AppColors.statusGreen)
                    Text("Chats and downloads stay on this Mac unless you export or delete them.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }
}

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

                HStack {
                    Text("Thinking Mode")
                        .frame(width: 150, alignment: .leading)

                    Toggle("", isOn: $viewModel.thinkingModeEnabled)
                        .disabled(!viewModel.loadedModelSupportsThinking)

                    Spacer()

                    Text(viewModel.thinkingModeEnabled ? "Enabled" : "Disabled")
                        .font(AppTypography.caption)
                        .foregroundColor(
                            viewModel.thinkingModeEnabled
                                ? AppColors.primaryPurple
                                : AppColors.textSecondary
                        )
                }

                Text(thinkingModeDescription(for: viewModel))
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
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

                        Text(
                            "After saving, you must restart the app for changes to take effect. "
                            + "The SDK will reinitialize with your custom configuration."
                        )
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
            .navigationBarTitleDisplayModeCompat(.inline)
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
    let model: RAStoredModel
    let onDelete: () async -> Void
    @ObservedObject private var modelListViewModel = ModelListViewModel.shared
    @State private var showingDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    private var backend: InferenceFramework? {
        modelListViewModel.availableModels.first { $0.id == model.id }?.framework
    }

    private var isDeletable: Bool {
        !model.id.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(model.name)
                        .font(AppTypography.subheadlineMedium)

                    HStack(spacing: AppSpacing.small) {
                        Text(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .file))
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textSecondary)
                        if let backend {
                            backendBadge(backend)
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

    @ViewBuilder
    private func backendBadge(_ framework: InferenceFramework) -> some View {
        HStack(spacing: AppSpacing.xxSmall) {
            Image(systemName: framework.consumerBackendIcon)
            Text(framework.consumerBackendLabel)
        }
        .font(AppTypography.caption2Medium)
        .foregroundColor(framework.consumerBackendColor)
        .padding(.horizontal, AppSpacing.xSmall)
        .padding(.vertical, 2)
        .background(framework.consumerBackendColor.opacity(0.12))
        .cornerRadius(AppSpacing.cornerRadiusSmall)
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
