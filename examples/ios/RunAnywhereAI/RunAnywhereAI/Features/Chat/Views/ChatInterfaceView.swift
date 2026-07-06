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
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

private enum ChatFileImportKind {
    case document
    case lora

    var allowedContentTypes: [UTType] {
        switch self {
        case .document:
            return [.pdf, .json]
        case .lora:
            return [.data]
        }
    }
}

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
    @State private var showingFileImporter = false
    @State private var activeFileImportKind: ChatFileImportKind = .document
    @State private var showingDocumentEmbeddingModelSelection = false
    @State private var showingDocumentAnswerModelSelection = false
    @State private var showingVisionModelSelection = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingImageAttachment: ChatImageAttachment?
    @State private var pendingDocumentAttachment: ChatDocumentAttachment?
    @State private var selectedDocumentEmbeddingModel: RAModelInfo?
    @State private var selectedDocumentAnswerModel: RAModelInfo?
    @State private var isVisionModelReady = false
    @State private var showDebugAlert = false
    @State private var debugMessage = ""
    @State private var showModelLoadedToast = false
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

    var hasAssistantSurface: Bool {
        hasModelSelected || isVisionModelReady
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
        .adaptiveSheet(isPresented: $showingVisionModelSelection) {
            ModelSelectionSheet(context: .vlm) { _ in
                await refreshVisionModelStatus()
            }
        }
        .adaptiveSheet(isPresented: $showingDocumentEmbeddingModelSelection) {
            ModelSelectionSheet(context: .ragEmbedding) { model in
                selectedDocumentEmbeddingModel = model
            }
        }
        .adaptiveSheet(isPresented: $showingDocumentAnswerModelSelection) {
            ModelSelectionSheet(context: .ragLLM) { model in
                selectedDocumentAnswerModel = model
            }
        }
        .adaptiveSheet(isPresented: $showingChatDetails) {
            ChatDetailsView(
                messages: viewModel.messages,
                conversation: viewModel.currentConversation
            )
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            Task { await handlePhotoSelection(item) }
        }
        .task {
            await viewModel.initialize()
            await refreshVisionModelStatus()
            await hydrateDefaultDocumentModels()
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
            isPresented: $showingFileImporter,
            allowedContentTypes: activeFileImportKind.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result, kind: activeFileImportKind)
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
            activeFileImportKind = .lora
            showingFileImporter = true
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
        if hasAssistantSurface {
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
                imageAttachment: pendingImageAttachment,
                documentAttachment: pendingDocumentAttachment,
                isVisionModelReady: isVisionModelReady,
                areDocumentModelsReady: areDocumentModelsReady,
                canSendCurrentTurn: canSendCurrentTurn,
                onRemoveImageAttachment: {
                    pendingImageAttachment = nil
                },
                onRemoveDocumentAttachment: {
                    pendingDocumentAttachment = nil
                },
                onChooseVisionModel: {
                    showingVisionModelSelection = true
                },
                onChooseDocumentModels: {
                    showNextDocumentModelPicker()
                },
                onComposerAction: handleComposerAction,
                onSend: sendMessage
            )
        } else {
            Spacer()
        }
    }

    @ViewBuilder var modelRequiredOverlayIfNeeded: some View {
        if !hasAssistantSurface && !viewModel.isGenerating {
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
    private var canSendCurrentTurn: Bool {
        let hasText = !viewModel.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if pendingImageAttachment != nil {
            return hasText && isVisionModelReady && !viewModel.isGenerating
        }
        if pendingDocumentAttachment != nil {
            return hasText && areDocumentModelsReady && !viewModel.isGenerating
        }
        return viewModel.canSend
    }

    private var areDocumentModelsReady: Bool {
        selectedDocumentEmbeddingModel?.isAvailableForUse == true
            && selectedDocumentAnswerModel?.isAvailableForUse == true
    }

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

    private func handleFileImport(_ result: Result<[URL], Error>, kind: ChatFileImportKind) {
        switch kind {
        case .document:
            handleDocumentImport(result)
        case .lora:
            if case .success(let urls) = result, let url = urls.first {
                pendingLoRAURL = url
                loraScale = 1.0
                showingLoRAScaleSheet = true
            }
        }
    }

    private func handleComposerAction(_ action: ComposerAction) {
        switch action {
        case .attachFile:
            activeFileImportKind = .document
            showingFileImporter = true
        case .attachPhoto:
            showingPhotoPicker = true
        case .takePhoto:
            showingVisionWorkbench = true
        case .talk:
            showingTalkMode = true
        }
    }

    func sendMessage() {
        if let pendingImageAttachment {
            sendImageQuestion(pendingImageAttachment)
            return
        }

        if let pendingDocumentAttachment {
            sendDocumentQuestion(pendingDocumentAttachment)
            return
        }

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

    private func sendImageQuestion(_ attachment: ChatImageAttachment) {
        guard canSendCurrentTurn else {
            if !isVisionModelReady {
                showingVisionModelSelection = true
            }
            return
        }

        pendingImageAttachment = nil

        Task {
            await viewModel.sendImageQuestion(image: attachment.image, prompt: viewModel.currentInput)
            await refreshVisionModelStatus()

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

    private func sendDocumentQuestion(_ attachment: ChatDocumentAttachment) {
        guard canSendCurrentTurn,
              let embeddingModel = selectedDocumentEmbeddingModel,
              let answerModel = selectedDocumentAnswerModel else {
            showNextDocumentModelPicker()
            return
        }

        Task {
            await viewModel.sendDocumentQuestion(
                document: attachment,
                embeddingModel: embeddingModel,
                answerModel: answerModel,
                prompt: viewModel.currentInput
            )

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

    @MainActor
    private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedPhotoItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw LLMError.custom("The selected image could not be loaded.")
            }

            let image: RAVLMImage?
            #if canImport(UIKit)
            image = UIImage(data: data).flatMap { RAVLMImage.fromUIImage($0) }
            #elseif canImport(AppKit)
            image = NSImage(data: data).flatMap { RAVLMImage.fromNSImage($0) }
            #else
            image = nil
            #endif

            guard let image else {
                throw LLMError.custom("The selected image could not be prepared for the vision model.")
            }

            pendingImageAttachment = ChatImageAttachment(
                data: data,
                image: image,
                filename: item.itemIdentifier ?? "Selected image"
            )
            pendingDocumentAttachment = nil

            if !isVisionModelReady {
                showingVisionModelSelection = true
            }
        } catch {
            debugMessage = error.localizedDescription
            showDebugAlert = true
        }
    }

    @MainActor
    private func refreshVisionModelStatus() async {
        var request = RACurrentModelRequest()
        request.category = .multimodal
        isVisionModelReady = RunAnywhere.currentModel(request).found
    }

    private func handleDocumentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let text = try DocumentService.extractText(from: url)
                pendingDocumentAttachment = ChatDocumentAttachment(
                    filename: url.lastPathComponent,
                    text: text
                )
                pendingImageAttachment = nil

                if !areDocumentModelsReady {
                    showNextDocumentModelPicker()
                }
            } catch {
                debugMessage = error.localizedDescription
                showDebugAlert = true
            }
        case .failure(let error):
            debugMessage = error.localizedDescription
            showDebugAlert = true
        }
    }

    private func showNextDocumentModelPicker() {
        if selectedDocumentEmbeddingModel?.isAvailableForUse != true {
            showingDocumentEmbeddingModelSelection = true
        } else if selectedDocumentAnswerModel?.isAvailableForUse != true {
            showingDocumentAnswerModelSelection = true
        }
    }

    @MainActor
    private func hydrateDefaultDocumentModels() async {
        await ModelListViewModel.shared.loadModels()

        if selectedDocumentEmbeddingModel == nil {
            selectedDocumentEmbeddingModel = ModelListViewModel.shared.availableModels.first(where: {
                $0.category == .embedding
                    && $0.framework == .onnx
                    && !$0.id.hasSuffix("-vocab")
                    && !$0.id.hasSuffix("-tokenizer")
                    && $0.isAvailableForUse
            })
        }

        if selectedDocumentAnswerModel == nil {
            if let currentModel = ModelListViewModel.shared.currentModel,
               currentModel.category == .language,
               currentModel.framework == .llamaCpp,
               currentModel.isAvailableForUse {
                selectedDocumentAnswerModel = currentModel
                return
            }

            selectedDocumentAnswerModel = ModelListViewModel.shared.availableModels.first(where: {
                $0.category == .language
                    && $0.framework == .llamaCpp
                    && $0.isAvailableForUse
            })
        }
    }
}
