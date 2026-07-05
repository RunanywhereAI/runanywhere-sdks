//
//  ChatInterfaceView.swift
//  RunAnywhereAI
//
//  Chat interface shell + toolbar - all logic lives in LLMViewModel.
//

import SwiftUI
import RunAnywhere
import UniformTypeIdentifiers
import os.log
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Chat Interface View

struct ChatInterfaceView: View {
    @State private var viewModel = LLMViewModel()
    @StateObject private var conversationStore = ConversationStore.shared
    @State private var showingConversationList = false
    @State private var showingModelSelection = false
    @State private var showingChatDetails = false
    @State private var showingSettings = false
    @State private var showingAdvancedHub = false
    @State private var showingTalkMode = false
    @State private var showingVisionWorkbench = false
    @State private var showingDocuments = false
    @State private var showDebugAlert = false
    @State private var debugMessage = ""
    @State private var showModelLoadedToast = false
    @State private var showingLoRAFilePicker = false
    @State private var showingLoRAScaleSheet = false
    @State private var showingLoRAManagement = false
    @State private var openFilePickerAfterManagementDismiss = false
    @State private var pendingLoRAURL: URL?
    @State private var loraScale: Float = 1.0
    @ObservedObject private var toolSettingsViewModel = ToolSettingsViewModel.shared
    @ObservedObject private var settingsViewModel = SettingsViewModel.shared
    @FocusState private var isTextFieldFocused: Bool

    private let logger = Logger(
        subsystem: "com.runanywhere.RunAnywhereAI",
        category: "ChatInterfaceView"
    )

    var hasModelSelected: Bool {
        viewModel.isModelLoaded && viewModel.loadedModelName != nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                #if os(macOS)
                macOSView
                #else
                iOSView
                #endif
            }

            if showingConversationList {
                conversationDrawerOverlay
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .adaptiveSheet(isPresented: $showingModelSelection) {
            ModelSelectionSheet(context: .llm) { model in
                await handleModelSelected(model)
            }
        }
        .adaptiveSheet(isPresented: $showingSettings) {
            NavigationStack {
                CombinedSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingSettings = false }
                        }
                    }
            }
        }
        .adaptiveSheet(isPresented: $showingAdvancedHub) {
            NavigationStack {
                ConsumerAdvancedHubView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingAdvancedHub = false }
                        }
                    }
            }
        }
        .adaptiveSheet(isPresented: $showingTalkMode) {
            VoiceAssistantView()
        }
        .adaptiveSheet(isPresented: $showingVisionWorkbench) {
            NavigationStack {
                VLMCameraView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingVisionWorkbench = false }
                        }
                    }
            }
        }
        .adaptiveSheet(isPresented: $showingDocuments) {
            NavigationStack {
                DocumentRAGView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingDocuments = false }
                        }
                    }
            }
        }
        .adaptiveSheet(isPresented: $showingChatDetails) {
            ChatDetailsView(
                messages: viewModel.messages,
                conversation: viewModel.currentConversation
            )
        }
        .task {
            await viewModel.initialize()
        }
        .onChange(of: viewModel.isModelLoaded) { wasLoaded, isLoaded in
            if isLoaded && !wasLoaded {
                showModelLoadedToast = true
            }
        }
        .alert("Debug Info", isPresented: $showDebugAlert) {
            Button("OK") { }
        } message: {
            Text(debugMessage)
        }
        .modelLoadedToast(
            isShowing: $showModelLoadedToast,
            modelName: viewModel.loadedModelName ?? "Model"
        )
        .fileImporter(
            isPresented: $showingLoRAFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingLoRAURL = url
                loraScale = 1.0
                showingLoRAScaleSheet = true
            }
        }
        .sheet(isPresented: $showingLoRAScaleSheet) {
            LoRAScaleSheetView(
                url: pendingLoRAURL,
                scale: $loraScale,
                isLoading: viewModel.isLoadingLoRA
            ) {
                guard let url = pendingLoRAURL else { return }
                Task {
                    await viewModel.importAndLoadLoraAdapter(url: url, scale: loraScale)
                    showingLoRAScaleSheet = false
                }
            } onCancel: {
                showingLoRAScaleSheet = false
            }
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showingLoRAManagement, onDismiss: handleLoRAManagementDismiss) {
            loraManagementSheet
        }
        .animation(.easeInOut(duration: AppLayout.animationRegular), value: showingConversationList)
    }

    // Chain the file picker off the management sheet's dismissal instead of
    // racing it behind a fixed delay.
    private func handleLoRAManagementDismiss() {
        if openFilePickerAfterManagementDismiss {
            openFilePickerAfterManagementDismiss = false
            showingLoRAFilePicker = true
        }
    }

    private var loraManagementSheet: some View {
        LoRAManagementSheetView(
            viewModel: viewModel,
            onOpenFilePicker: {
                openFilePickerAfterManagementDismiss = true
                showingLoRAManagement = false
            },
            onDismiss: {
                showingLoRAManagement = false
            }
        )
        .presentationDetents([.large])
    }
}

// MARK: - Platform Views

extension ChatInterfaceView {
    var macOSView: some View {
        ZStack {
            VStack(spacing: 0) {
                macOSToolbar
                contentArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.backgroundPrimary)

            modelRequiredOverlayIfNeeded
        }
    }

    var iOSView: some View {
        VStack(spacing: 0) {
            consumerTopBar

            ZStack {
                VStack(spacing: 0) {
                    contentArea
                }
                modelRequiredOverlayIfNeeded
            }
        }
    }
}

// MARK: - Toolbar + Content Shell

extension ChatInterfaceView {
    var macOSToolbar: some View {
        HStack {
            Button {
                showingConversationList = true
            } label: {
                Label("Conversations", systemImage: "list.bullet")
            }
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)

            Button {
                showingChatDetails = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)
            .disabled(viewModel.messages.isEmpty)

            Spacer()

            modelButton

            Spacer()

            Button {
                showingAdvancedHub = true
            } label: {
                Label("Advanced", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.smallMedium)
        .background(AppColors.backgroundPrimary)
    }

    @ViewBuilder var contentArea: some View {
        if hasModelSelected {
            ChatMessageListView(
                viewModel: viewModel,
                isTextFieldFocused: $isTextFieldFocused,
                showingLoRAManagement: $showingLoRAManagement,
                settingsViewModel: settingsViewModel,
                toolSettingsViewModel: toolSettingsViewModel
            )
            ChatInputAreaView(
                viewModel: viewModel,
                isTextFieldFocused: $isTextFieldFocused,
                showingLoRAManagement: $showingLoRAManagement,
                settingsViewModel: settingsViewModel,
                toolSettingsViewModel: toolSettingsViewModel,
                onComposerAction: handleComposerAction,
                onSend: sendMessage
            )
        } else {
            Spacer()
        }
    }

    @ViewBuilder var modelRequiredOverlayIfNeeded: some View {
        if !hasModelSelected && !viewModel.isGenerating {
            ModelRequiredOverlay(modality: .llm) { showingModelSelection = true }
        }
    }

    private var modelButton: some View {
        Button {
            showingModelSelection = true
        } label: {
            HStack(spacing: 6) {
                if let modelName = viewModel.loadedModelName {
                    Image(getModelLogo(for: modelName))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "cube")
                        .font(.system(size: 14))
                }

                if let modelName = viewModel.loadedModelName {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modelName.shortModelName(maxLength: 13))
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        HStack(spacing: 3) {
                            Image(systemName: viewModel.selectedFramework?.consumerBackendIcon ?? "cube")
                                .font(.system(size: 7))
                            Text(viewModel.selectedFramework?.consumerBackendShortLabel ?? "Ready")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundColor(viewModel.selectedFramework?.consumerBackendColor ?? AppColors.primaryAccent)
                    }
                } else {
                    Text("Choose Model")
                        .font(AppTypography.caption)
                }
            }
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        .tint(AppColors.primaryAccent)
        #endif
    }
}

// MARK: - Helper Methods

extension ChatInterfaceView {
    private var consumerTopBar: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            iconCircleButton(systemImage: "line.3.horizontal") {
                showingConversationList = true
            }
            .accessibilityLabel("Chats")

            Spacer()

            modelButton

            Spacer()

            iconCircleButton(systemImage: "square.and.pencil") {
                viewModel.createNewConversation()
            }
            .accessibilityLabel("New Chat")

            iconCircleButton(systemImage: "gearshape") {
                showingSettings = true
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.mediumLarge)
        .background(AppColors.backgroundPrimary.opacity(0.96))
    }

    private func iconCircleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(AppColors.backgroundSecondary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var conversationDrawerOverlay: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                AppColors.overlayLight
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingConversationList = false
                    }

                ConversationDrawerView(
                    onSelectConversation: selectConversation,
                    onCreateConversation: {
                        viewModel.createNewConversation()
                        showingConversationList = false
                    },
                    onOpenSettings: {
                        showingConversationList = false
                        showingSettings = true
                    },
                    onClose: {
                        showingConversationList = false
                    }
                )
                .frame(width: min(geometry.size.width * 0.86, DeviceFormFactor.current == .desktop ? 360 : 330))
                .frame(maxHeight: .infinity)
                .shadow(color: AppColors.shadowDark, radius: 18, x: 8, y: 0)
            }
        }
    }

    private func selectConversation(_ conversation: Conversation) {
        let selected = conversationStore.loadConversation(conversation.id) ?? conversation
        NotificationCenter.default.post(name: Notification.Name("ConversationSelected"), object: selected)
        showingConversationList = false
    }

    private func handleComposerAction(_ action: ComposerAction) {
        switch action {
        case .attachFile:
            showingDocuments = true
        case .takePhoto, .attachPhoto:
            showingVisionWorkbench = true
        case .talk:
            showingTalkMode = true
        }
    }

    func sendMessage() {
        guard viewModel.canSend else { return }

        Task {
            await viewModel.sendMessage()

            Task {
                let sleepDuration = UInt64(AppLayout.animationSlow * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepDuration)
                if let error = viewModel.error {
                    await MainActor.run {
                        debugMessage = "Error occurred: \(error.localizedDescription)"
                        showDebugAlert = true
                    }
                }
            }
        }
    }

    func handleModelSelected(_ model: RAModelInfo) async {
        await MainActor.run {
            ModelListViewModel.shared.setCurrentModel(model)
        }

        await viewModel.checkModelStatus()
    }
}
