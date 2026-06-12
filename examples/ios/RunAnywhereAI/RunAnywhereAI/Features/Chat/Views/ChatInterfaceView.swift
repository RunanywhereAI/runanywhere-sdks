//
//  ChatInterfaceView.swift
//  RunAnywhereAI
//
//  Chat interface shell + toolbar — all logic lives in LLMViewModel.
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
        Group {
            #if os(macOS)
            macOSView
            #else
            iOSView
            #endif
        }
        .adaptiveSheet(isPresented: $showingConversationList) {
            ConversationListView()
        }
        .adaptiveSheet(isPresented: $showingModelSelection) {
            ModelSelectionSheet(context: .llm) { model in
                await handleModelSelected(model)
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
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    contentArea
                }
                modelRequiredOverlayIfNeeded
            }
            .navigationTitle(hasModelSelected ? "Chat" : "")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            .navigationBarHidden(!hasModelSelected)
            #endif
            .toolbar {
                if hasModelSelected {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingConversationList = true
                        } label: {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                    }

                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingChatDetails = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(viewModel.messages.isEmpty ? .gray : AppColors.primaryAccent)
                        }
                        .disabled(viewModel.messages.isEmpty)
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        modelButton
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button {
                            showingConversationList = true
                        } label: {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                    }

                    ToolbarItem(placement: .automatic) {
                        Button {
                            showingChatDetails = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(viewModel.messages.isEmpty ? .gray : AppColors.primaryAccent)
                        }
                        .disabled(viewModel.messages.isEmpty)
                    }

                    ToolbarItem(placement: .automatic) {
                        modelButton
                    }
                    #endif
                }
            }
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
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

            Text("Chat")
                .font(AppTypography.headline)

            Spacer()

            modelButton
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
                            Image(systemName: viewModel.modelSupportsStreaming ? "bolt.fill" : "square.fill")
                                .font(.system(size: 7))
                            Text(viewModel.modelSupportsStreaming ? "Streaming" : "Batch")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundColor(viewModel.modelSupportsStreaming ? .green : .orange)
                    }
                } else {
                    Text("Select Model")
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
