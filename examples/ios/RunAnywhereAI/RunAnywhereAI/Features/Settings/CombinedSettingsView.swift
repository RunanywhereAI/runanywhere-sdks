//
//  CombinedSettingsView.swift
//  RunAnywhereAI
//
//  Settings. A `Form` on both platforms.
//
//  The Mac path used to be a `ScrollView` of hand-drawn cards in which every
//  label sat in a `Text(...).frame(width: 150)` gutter — so "Save Performance
//  History" wrapped to two lines inside a 150pt box while the switch it belonged
//  to floated 150pt away from it, and the two-column rhythm broke on every row
//  whose label happened to be longer. `Form` + `.formStyle(.grouped)` gets the
//  alignment, the row separators, the group insets, and the label/control
//  pairing from AppKit for free, and it is the only thing on the Mac that looks
//  like System Settings rather than like a web page.
//
//  On the Mac this view is the content of the `Settings { }` scene, so it lives
//  behind ⌘, in its own window with real preference tabs. On iOS it is one
//  scrolling `Form` pushed from the chat drawer, because a phone has no
//  preferences window and tabs inside a sheet are a maze.
//

import SwiftUI
import RunAnywhere
import Combine

struct CombinedSettingsView: View {
    // ViewModel - all business logic is here
    @ObservedObject private var viewModel = SettingsViewModel.shared
    @StateObject private var toolViewModel = ToolSettingsViewModel.shared
    @StateObject private var storageViewModel = StorageViewModel.shared

    var body: some View {
        Group {
            #if os(macOS)
            MacSettingsTabs(
                viewModel: viewModel,
                toolViewModel: toolViewModel,
                storageViewModel: storageViewModel
            )
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
        // A `.constant(...)` binding cannot write `false` back, so the previous
        // version of this alert could be dismissed visually and then reappear on
        // the next redraw — the OK button cleared the message, but nothing
        // cleared it if the alert was dismissed any other way.
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Restart Required", isPresented: $viewModel.showRestartAlert) {
            Button("OK") {
                viewModel.showRestartAlert = false
            }
        } message: {
            Text(
                "Please restart the app for the new API configuration to take effect. "
                + "RunAnywhere will use your custom connection after restarting."
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
                    Label(
                        "Creativity: \(String(format: "%.2f", viewModel.temperature))",
                        systemImage: "dial.medium"
                    )
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    Slider(value: $viewModel.temperature, in: 0...2, step: 0.1)
                }

                Toggle(isOn: $viewModel.thinkingModeEnabled) {
                    Label("Thinking Mode", systemImage: "brain")
                }
                .disabled(!viewModel.loadedModelSupportsThinking)
                .onChange(of: viewModel.thinkingModeEnabled) { _, _ in
                    Haptics.light()
                }

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
                Text(
                    "Each model is labeled with the technology it uses, "
                    + "so you can choose what fits your device."
                )
                .font(AppTypography.caption)
            }

            ToolSettingsSection(viewModel: toolViewModel)

            Section {
                Label("Chats and downloads stay on this device", systemImage: "lock.shield")
                    .foregroundColor(AppColors.textPrimary)
                Toggle(isOn: $viewModel.analyticsLogToLocal) {
                    Label("Log Analytics Locally", systemImage: "chart.bar.doc.horizontal")
                }
                .onChange(of: viewModel.analyticsLogToLocal) { _, _ in
                    Haptics.light()
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("When enabled, analytics events are saved locally on your device.")
                    .font(AppTypography.caption)
            }

            Section {
                NavigationLink(destination: ConsumerAdvancedHubView()) {
                    SettingsNavigationRow(
                        icon: "slider.horizontal.3",
                        color: AppColors.primaryPurple,
                        title: "AI Tools",
                        subtitle: "Voice, performance, and model controls"
                    )
                }

                #if DEBUG
                Button(
                    action: { viewModel.showApiKeySheet() },
                    label: {
                        HStack {
                            Label("API Key", systemImage: "key")
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
                    Label("Base URL", systemImage: "link")
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
                #endif

                DisclosureGroup {
                    PrivateDownloadsControls(viewModel: viewModel)
                } label: {
                    Label("Private Downloads", systemImage: "key.icloud")
                }
            } header: {
                Text("Advanced")
            } footer: {
                #if DEBUG
                Text(
                    "Connection controls are kept here so the main app stays assistant-first. "
                    + "Add a Hugging Face token to download models from private repos."
                )
                .font(AppTypography.caption)
                #else
                Text("Add a Hugging Face token to download models from private repos.")
                    .font(AppTypography.caption)
                #endif
            }

            // About
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                    Label("RunAnywhere", systemImage: "app")
                        .font(AppTypography.headline)
                    Text(Bundle.main.displayVersion)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                if let docsURL = URL(string: "https://docs.runanywhere.ai") {
                    Link(destination: docsURL) {
                        Label("Documentation", systemImage: "book")
                    }
                }

                if let xURL = URL(string: "https://x.com/RunanywhereAI") {
                    Link(destination: xURL) {
                        Label("Follow on X", systemImage: "person.crop.circle.badge.plus")
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

#if os(macOS)

/// Which preference pane is showing. Persisted so ⌘, reopens where you left.
private enum SettingsPane: String {
    case general
    case models
    case tools
    case advanced
    case about
}

private struct MacSettingsTabs: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var toolViewModel: ToolSettingsViewModel
    @ObservedObject var storageViewModel: StorageViewModel

    @AppStorage("mac.settings.pane") private var storedPane: String = SettingsPane.general.rawValue

    private var pane: Binding<SettingsPane> {
        Binding(
            get: { SettingsPane(rawValue: storedPane) ?? .general },
            set: { storedPane = $0.rawValue }
        )
    }

    var body: some View {
        // The value-based `Tab(...)` DSL is macOS 15+; this app's floor is 14.5,
        // so panes are declared with `.tabItem` + `.tag`.
        TabView(selection: pane) {
            GeneralPane(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsPane.general)

            ModelsPane(viewModel: viewModel, storageViewModel: storageViewModel)
                .tabItem { Label("Models", systemImage: "square.stack.3d.up") }
                .tag(SettingsPane.models)

            ToolsPane(toolViewModel: toolViewModel)
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsPane.tools)

            AdvancedPane(viewModel: viewModel)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsPane.advanced)

            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsPane.about)
        }
        // A preferences window is sized by its content, not dragged to fit. One
        // frame for every pane keeps the window from resizing under the pointer
        // each time a tab is clicked.
        .frame(width: 560, height: 460)
    }
}

private struct GeneralPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Creativity") {
                    HStack(spacing: Space.md) {
                        Slider(value: $viewModel.temperature, in: 0...2, step: 0.1)
                        Text(viewModel.temperature, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: viewModel.temperature))
                            .foregroundStyle(AppColors.primaryAccent)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                LabeledContent("Max Response Length") {
                    Stepper(
                        value: $viewModel.maxTokens,
                        in: 500...20000,
                        step: 500
                    ) {
                        Text("\(viewModel.maxTokens) tokens")
                            .monospacedDigit()
                    }
                }

                Toggle("Thinking Mode", isOn: $viewModel.thinkingModeEnabled)
                    .disabled(!viewModel.loadedModelSupportsThinking)
            } header: {
                Text("Responses")
            } footer: {
                Text(thinkingModeDescription(for: viewModel))
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Section {
                TextField("How should RunAnywhere respond?", text: $viewModel.systemPrompt, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("System Prompt")
            } footer: {
                Text("Sent ahead of every conversation to set tone and behavior.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Section {
                Toggle("Save Performance History", isOn: $viewModel.analyticsLogToLocal)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Chats, downloads, and performance history stay on this Mac.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelsPane: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var storageViewModel: StorageViewModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Models on This Mac", value: storageViewModel.formattedModelStorage)
                LabeledContent("Free Space", value: storageViewModel.formattedAvailableSpace)
                LabeledContent("Downloaded", value: "\(storageViewModel.storedModels.count)")
            } header: {
                HStack {
                    Text("Storage")
                    Spacer()
                    Button {
                        Task { await storageViewModel.refreshData() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Recount storage")
                }
            }

            Section("Downloaded Models") {
                if storageViewModel.storedModels.isEmpty {
                    Text("No models downloaded yet.")
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(storageViewModel.storedModels, id: \.id) { model in
                        StoredModelRow(model: model) {
                            await storageViewModel.deleteModel(model)
                        }
                    }
                }
            }

            Section {
                Button("Clear Cache") {
                    Task { await storageViewModel.clearCache() }
                }
                Button("Clean Temporary Files") {
                    Task { await storageViewModel.cleanTempFiles() }
                }
            } header: {
                Text("Maintenance")
            } footer: {
                Text("Neither removes a downloaded model. Delete those above.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .formStyle(.grouped)
        .task { await storageViewModel.loadData() }
    }
}

private struct ToolsPane: View {
    @ObservedObject var toolViewModel: ToolSettingsViewModel

    var body: some View {
        Form {
            ToolSettingsSection(viewModel: toolViewModel)
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                PrivateDownloadsControls(viewModel: viewModel)
            } header: {
                Text("Private Downloads")
            }

            #if DEBUG
            Section {
                LabeledContent("API Key") {
                    StatusText(
                        viewModel.isApiKeyConfigured ? "Configured" : "Not Set",
                        isSet: viewModel.isApiKeyConfigured
                    )
                }
                LabeledContent("Base URL") {
                    StatusText(
                        viewModel.isBaseURLConfigured ? "Configured" : "Using Default",
                        isSet: viewModel.isBaseURLConfigured
                    )
                }

                HStack {
                    Button("Configure…") { viewModel.showApiKeySheet() }
                    if viewModel.isApiConfigurationComplete {
                        Button("Clear") { viewModel.clearApiConfiguration() }
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Requires a restart to take effect.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            #endif
        }
        .formStyle(.grouped)
    }
}

/// A configured/not-configured value, colored the same way everywhere.
private struct StatusText: View {
    let text: String
    let isSet: Bool

    init(_ text: String, isSet: Bool) {
        self.text = text
        self.isSet = isSet
    }

    var body: some View {
        Text(text)
            .appType(.caption)
            .foregroundStyle(isSet ? AppColors.statusGreen : AppColors.textSecondary)
    }
}

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("RunAnywhere", value: Bundle.main.displayVersion)

                if let docsURL = URL(string: "https://docs.runanywhere.ai") {
                    Link("Documentation", destination: docsURL)
                }
                if let xURL = URL(string: "https://x.com/RunanywhereAI") {
                    Link("Follow on X", destination: xURL)
                }
            } footer: {
                Text("An example app for the RunAnywhere on-device AI SDK.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .formStyle(.grouped)
    }
}

#endif

// MARK: - Reusable Components

private struct PrivateDownloadsControls: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.padding15) {
            HStack {
                Text("Hugging Face Token")
                Spacer()
                Text(viewModel.isHfTokenConfigured ? "Configured" : "Not Set")
                    .font(AppTypography.caption)
                    .foregroundColor(viewModel.isHfTokenConfigured ? AppColors.statusGreen : AppColors.statusOrange)
            }

            SecureField("hf_...", text: $viewModel.hfToken)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isSavingHfToken)

            Text("Used only for downloading models from private Hugging Face repos.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: AppSpacing.smallMedium) {
                Button("Save Token") {
                    viewModel.saveHfToken()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.primaryAccent)
                .disabled(viewModel.isSavingHfToken)

                Button("Clear") {
                    viewModel.clearHfToken()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.primaryRed)
                .disabled(viewModel.isSavingHfToken)

                if viewModel.isSavingHfToken {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let message = viewModel.hfTokenMessage {
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundColor(viewModel.hfTokenMessageIsError ? AppColors.primaryRed : AppColors.statusGreen)
            }
        }
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
                            + "RunAnywhere will use your custom connection after restarting."
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

#if os(macOS)
/// One downloaded model: what it is, how big, and how to remove it.
///
/// Deliberately a single `LabeledContent`-shaped row rather than the previous
/// expanding "Details" disclosure that showed the size a second time next to
/// the size it was already showing.
private struct StoredModelRow: View {
    let model: ModelInfo
    let onDelete: () async -> Void

    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    private var displayName: String {
        model.name.isEmpty ? model.id : model.name
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: model.downloadSizeBytes, countStyle: .file)
        return "\(size) · \(model.framework.consumerBackendLabel)"
    }

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .appType(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: Space.sm)

            if isDeleting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete \(displayName) from this Mac")
                .disabled(model.id.isEmpty)
            }
        }
        .confirmationDialog(
            "Delete \(displayName)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    await onDelete()
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is removed from this Mac. You can download it again later.")
        }
    }
}
#endif

private extension Bundle {
    var displayVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        CombinedSettingsView()
    }
}
