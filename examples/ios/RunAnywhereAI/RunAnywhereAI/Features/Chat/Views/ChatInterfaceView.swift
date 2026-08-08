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
            // One list, shared with the drop and paste paths, so the picker
            // cannot offer a type those refuse or hide one they accept.
            return ChatAttachmentLoader.documentContentTypes
        case .lora:
            return [.data]
        }
    }
}

// MARK: - Chat Interface View

struct ChatInterfaceView: View {
    // On the Mac the shell owns the view model so the sidebar and the transcript
    // agree on which conversation is open. On iOS there is no second column, so
    // the view creates its own.
    @State private var viewModel: LLMViewModel
    @StateObject private var conversationStore = ConversationStore.shared
    #if os(iOS)
    @State private var showingConversationList = false
    #endif
    @State private var showingModelSelection = false
    @State private var showingChatDetails = false
    #if os(iOS)
    // Both are Mac windows/destinations rather than sheets, so the state that
    // drives them does not exist there.
    @State private var showingSettings = false
    @State private var showingAdvancedHub = false
    #endif
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
    /// True while a drag is over the transcript, so the pane can say it will
    /// take the file before the user lets go.
    @State private var isDropTargeted = false
    @State private var selectedDocumentEmbeddingModel: RAModelInfo?
    @State private var selectedDocumentAnswerModel: RAModelInfo?
    @State private var isVisionModelReady = false
    @State private var errorMessage: String?
    @State private var showModelLoadedToast = false
    @State private var showingLoRAScaleSheet = false
    @State private var showingLoRAManagement = false
    @State private var openFilePickerAfterManagementDismiss = false
    @State private var pendingLoRAURL: URL?
    @State private var loraScale: Float = 1.0
    @ObservedObject private var toolSettingsViewModel = ToolSettingsViewModel.shared
    @ObservedObject private var settingsViewModel = SettingsViewModel.shared
    @ObservedObject private var modelListViewModel = ModelListViewModel.shared
    #if os(iOS)
    @ObservedObject private var connectController = ConnectClientController.shared
    #endif
    @FocusState private var isTextFieldFocused: Bool

    private let logger = Logger(
        subsystem: "com.runanywhere.RunAnywhereAI",
        category: "ChatInterfaceView"
    )

    // The default is `nil` rather than `LLMViewModel()`: a default argument is
    // evaluated in the *caller's* isolation, so a literal default would demand
    // main-actor context at every call site. Constructing inside this
    // `@MainActor` body keeps `ChatInterfaceView()` callable as written.
    @MainActor
    init(viewModel: LLMViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? LLMViewModel())
    }

    var hasModelSelected: Bool {
        viewModel.isModelLoaded && viewModel.loadedModelName != nil
    }

    var hasAssistantSurface: Bool {
        hasModelSelected || isVisionModelReady
    }

    var body: some View {
        Group {
            #if os(macOS)
            // The Mac reaches conversations through the window's sidebar, so the
            // slide-over drawer (and the dimming layer it needed) is gone.
            macOSView
            #else
            ZStack(alignment: .leading) {
                iOSView

                if showingConversationList {
                    conversationDrawerOverlay
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            // Scoped to the drawer it animates rather than applied to the whole
            // screen, so an unrelated state change can't drag chat content
            // through this curve.
            .animation(Motion.standardFade, value: showingConversationList)
            #endif
        }
        .adaptiveSheet(isPresented: $showingModelSelection) {
            ModelSelectionSheet(context: .llm) { model in
                await handleModelSelected(model)
            }
        }
        // Settings and Advanced are sheets only on iOS. On the Mac, Settings is
        // the app's own preferences window (⌘,) and Advanced is a sidebar
        // destination (⌘3) — presenting either over the chat there would be a
        // second, competing way to reach the same screen.
        #if os(iOS)
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
        #endif
        .adaptiveSheet(isPresented: $showingTalkMode) {
            VoiceAssistantView()
        }
        .adaptiveSheet(isPresented: $showingVisionWorkbench) {
#if os(macOS)
            NavigationStack { VLMCameraView() }
#else
            NavigationStack {
                VLMCameraView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingVisionWorkbench = false }
                        }
                    }
            }
#endif
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
            #if os(iOS)
            await synchronizeConnectState()
            #endif
        }
        #if os(iOS)
        .onChange(of: connectController.session.status) { _, _ in
            Task { await synchronizeConnectState() }
        }
        .onChange(of: connectController.session.activeHost?.id) { _, _ in
            Task { await synchronizeConnectState() }
        }
        .onChange(of: connectController.session.activeModel?.id) { _, _ in
            Task { await synchronizeConnectState() }
        }
        #endif
        .onChange(of: viewModel.isModelLoaded) { wasLoaded, isLoaded in
            if isLoaded && !wasLoaded {
                showModelLoadedToast = true
            }
        }
        // Errors are surfaced by the code that produces them and by observing the
        // view model, not by a Task that sleeps and then peeks at `error`. Three
        // such pollers used to race here; a generation failing faster or slower
        // than the fixed delay showed nothing at all.
        .onChange(of: viewModel.errorDescription) { _, description in
            guard let description else { return }
            errorMessage = description
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { clearError() } }
            )
        ) {
            Button("OK") { clearError() }
        } message: {
            Text(errorMessage ?? "")
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
        .adaptiveSheet(isPresented: $showingLoRAScaleSheet) {
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
        .adaptiveSheet(isPresented: $showingLoRAManagement, onDismiss: handleLoRAManagementDismiss) {
            loraManagementSheet
        }
    }

    private func clearError() {
        errorMessage = nil
        viewModel.setError(nil)
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
    #if os(macOS)
    var macOSView: some View {
        ZStack {
            VStack(spacing: 0) {
                contentArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.backgroundPrimary)

            modelRequiredOverlayIfNeeded
        }
        // The window's own title bar carries the conversation identity, so the
        // app no longer paints a second chrome strip beneath it.
        .navigationTitle(viewModel.currentConversation?.title ?? "New Chat")
        .navigationSubtitle(macSubtitle)
        .toolbar { macToolbar }
        // The composer takes the caret when a window opens or a chat is
        // selected: a chat window whose text field is not focused makes the user
        // click before they can type.
        .defaultFocus($isTextFieldFocused, true)
        .onChange(of: hasAssistantSurface, initial: true) { _, ready in
            guard ready else { return }
            focusComposer()
        }
        .onChange(of: viewModel.currentConversation?.id) { _, _ in
            focusComposer()
        }
        .focusedSceneValue(\.chatSceneActions, chatSceneActions)
    }

    /// Put the caret in the message field.
    ///
    /// `.defaultFocus` alone does not do it here. AppKit resolves a window's
    /// default focus the first time the window works out where focus goes, and
    /// at that moment this view does not exist — the SDK gate in
    /// `RunAnywhereAIApp` is still showing the loading view — so the declaration
    /// is evaluated against a chat that has no text field yet and the caret
    /// lands nowhere. Measured on the Mac build: at launch, typing went to the
    /// sidebar's list type-select and the message never reached the composer.
    ///
    /// Asking again from a fresh main-actor turn runs after SwiftUI has
    /// installed the field, which is what makes it stick. `.defaultFocus` stays
    /// because it is still the right answer for a second window opened later.
    private func focusComposer() {
        Task { @MainActor in isTextFieldFocused = true }
    }

    /// The subtitle answers "what is answering me, and is it busy" — the two
    /// facts the old bordered-button row spent 200pt of chrome to convey.
    private var macSubtitle: String {
        if viewModel.isGenerating { return "Generating…" }
        if isModelLoading { return "Loading model…" }
        guard let name = viewModel.loadedModelName else { return "No model loaded" }
        let backend = viewModel.isUsingConnect
            ? (viewModel.connectedHostName ?? "Host")
            : (viewModel.selectedFramework?.consumerBackendShortLabel ?? "Local")
        return "\(name) · \(backend)"
    }

    /// New Chat is deliberately absent: `MacSidebar` already owns it, and the two
    /// together put two identical `square.and.pencil` buttons a few points apart
    /// in one unified title bar. The sidebar is the conventional Mac home for it
    /// (Notes, Mail, Messages all put compose over the list), so that one stays.
    @ToolbarContentBuilder private var macToolbar: some ToolbarContent {
        ToolbarItemGroup {
            if viewModel.isGenerating {
                Button {
                    viewModel.stopGeneration()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop Generating (⌘.)")
            }

            macModelButton

            Button {
                showingChatDetails = true
            } label: {
                Label("Chat Details", systemImage: "chart.bar.doc.horizontal")
            }
            .disabled(viewModel.messages.isEmpty)
            .help("Chat Details (⌘I)")
        }
    }

    /// A glyph, not a card.
    ///
    /// `.navigationSubtitle` already reads "MLX Bonsai-27B 1-bit · Apple"; the
    /// shared `modelButton` repeated that same name and backend as a 36pt-logo
    /// chip 1300pt to its right, so the title bar named the model twice. Here the
    /// control keeps only the job the subtitle can't do — being clickable — and
    /// the model's own logo carries the identity at toolbar scale.
    private var macModelButton: some View {
        Button {
            showingModelSelection = true
        } label: {
            if isModelLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let modelName = viewModel.loadedModelName {
                Image(getModelLogo(for: modelName))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs / 2, style: .continuous))
            } else {
                Label("Choose Model", systemImage: "cube")
            }
        }
        .help(macModelButtonHelp)
        .accessibilityLabel(macModelButtonHelp)
    }

    private var macModelButtonHelp: String {
        guard let name = viewModel.loadedModelName else {
            return "Choose the model that answers (⇧⌘L)"
        }
        return "\(name) — choose a different model (⇧⌘L)"
    }

    private var chatSceneActions: ChatSceneActions {
        // Hoisted into locals rather than written inline: `trailing_closure` wants
        // the final closure argument moved out of the parentheses, and
        // `multiple_closures_with_trailing_closure` forbids exactly that on a call
        // carrying more than one. Named locals satisfy both.
        let focusComposer = { isTextFieldFocused = true }
        let importDocument = {
            activeFileImportKind = .document
            showingFileImporter = true
        }
        return ChatSceneActions(
            newConversation: { viewModel.createNewConversation() },
            loadModel: { showingModelSelection = true },
            showChatDetails: viewModel.messages.isEmpty ? nil : { showingChatDetails = true },
            importDocument: importDocument,
            // nil disables the menu item, so it never offers to attach a
            // clipboard that has nothing the chat can take.
            pasteAttachment: ChatAttachmentLoader.pasteboardHasAttachment
                ? { handleComposerAction(.pasteAttachment) }
                : nil,
            // nil disables the menu item, so ⌘. never claims to stop something
            // that isn't running.
            stopGeneration: viewModel.isGenerating ? { viewModel.stopGeneration() } : nil,
            focusComposer: focusComposer
        )
    }
    #endif

    #if os(iOS)
    var iOSView: some View {
        VStack(spacing: 0) {
            ChatTopBar(
                model: modelSummary,
                onOpenChats: { showingConversationList = true },
                onChooseModel: { showingModelSelection = true },
                onNewChat: { viewModel.createNewConversation() }
            )

            // The banner belongs to the chat surface, not the entire screen.
            // It therefore overlays content below the top bar without ever
            // obscuring the navigation, selected model, or settings controls.
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    contentArea
                }
                modelRequiredOverlayIfNeeded

                ConnectStatusBanner()
                    .padding(.top, AppSpacing.small)
                    .zIndex(1)
            }
        }
    }
    #endif
}

// MARK: - Toolbar + Content Shell

extension ChatInterfaceView {
    @ViewBuilder var contentArea: some View {
        if hasAssistantSurface {
            chatSurface
                // Dropping a screenshot on a chat box is something people try
                // without being told they can, and the web app already accepts
                // it. `.fileURL` covers Finder and Files; `.image` covers a drag
                // straight out of a browser or Preview, which carries bytes and
                // no file.
                .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                    acceptDroppedProviders(providers)
                }
                .overlay { dropCue }
        }
        // No `else`. With no model loaded, `ModelRequiredOverlay` is the screen —
        // it sits above this in the same ZStack and paints edge to edge, so a
        // placeholder here can only ever be a surface nobody sees. The enclosing
        // stack already claims the full pane, so nothing collapses without it.
        //
        // Pasting is not wired here either. It is reached from the composer's +
        // menu, and on the Mac also from Edit ▸ Paste Attachment (⇧⌘V).
        // Deliberately not plain ⌘V: the composer is a focused text field and
        // the responder chain hands it ⌘V first, so an `.onPasteCommand` on this
        // view never fires — verified by putting a PNG on the pasteboard and
        // pressing ⌘V, which did nothing at all. ⌘V continuing to paste *text*
        // into the message is also what a writer expects; attaching a file is a
        // different intent, and the two now have two keys.
    }

    @ViewBuilder private var chatSurface: some View {
        VStack(spacing: 0) {
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
        }
    }

    /// What a drag over the transcript looks like.
    ///
    /// Dashed rather than a solid brand ring so it cannot be mistaken for the
    /// composer's focus ring, which is the other brand-coloured outline on this
    /// screen. Inset so the dashes read as an invitation over the content rather
    /// than as a new edge for the pane.
    @ViewBuilder private var dropCue: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    AppColors.primaryAccent,
                    style: StrokeStyle(lineWidth: Stroke.emphasis, dash: [7, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(AppColors.primaryAccent.opacity(0.06))
                )
                .overlay {
                    Label("Drop to attach", systemImage: "arrow.down.doc")
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.primaryAccent)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.md)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(Space.md)
                .allowsHitTesting(false)
                .transition(.opacity)
                .motionAware(Motion.microFade, value: isDropTargeted)
        }
    }

    @ViewBuilder var modelRequiredOverlayIfNeeded: some View {
        if !hasAssistantSurface && !viewModel.isGenerating && !modelListViewModel.isLoadingModel {
            ModelRequiredOverlay(modality: .llm) { showingModelSelection = true }
        }
    }

    /// The facts `ChatTopBar` needs about the model that answers, resolved here
    /// so the header never reaches into the view model for them itself.
    #if os(iOS)
    var modelSummary: ChatModelSummary {
        ChatModelSummary(
            name: viewModel.loadedModelName,
            isLoading: modelListViewModel.isLoadingModel,
            backendLabel: viewModel.isUsingConnect
                ? (viewModel.connectedHostName ?? "Host")
                : (viewModel.selectedFramework?.consumerBackendShortLabel ?? "Ready"),
            backendIcon: viewModel.isUsingConnect
                ? "desktopcomputer"
                : (viewModel.selectedFramework?.consumerBackendIcon ?? "cube"),
            backendColor: viewModel.selectedFramework?.consumerBackendColor ?? AppColors.primaryAccent
        )
    }
    #endif

    private var isModelLoading: Bool {
        modelListViewModel.isLoadingModel && viewModel.loadedModelName == nil
    }
}

// MARK: - Helper Methods

extension ChatInterfaceView {
    #if os(iOS)
    private func synchronizeConnectState() async {
        if case .connected = connectController.session.status,
           let model = connectController.session.activeModel {
            viewModel.activateConnectModel(
                model,
                hostName: connectController.session.activeHost?.displayName ?? "Mac"
            )
        } else if viewModel.isUsingConnect {
            await viewModel.deactivateConnectModel()
        }
    }
    #endif

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

    #if os(iOS)
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
                    onOpenMore: {
                        showingConversationList = false
                        showingAdvancedHub = true
                    },
                    onClose: {
                        showingConversationList = false
                    }
                )
                .frame(width: min(geometry.size.width * 0.86, DeviceFormFactor.current == .desktop ? 360 : 330))
                .frame(maxHeight: .infinity)
                .shadow(color: AppColors.shadowMedium, radius: 12, x: 4, y: 0)
            }
        }
    }

    /// Direct call, not a NotificationCenter round trip: the selection is
    /// intra-app state with exactly one consumer, and a broadcast made the data
    /// flow untraceable and untyped for no benefit.
    private func selectConversation(_ conversation: Conversation) {
        let selected = conversationStore.loadConversation(conversation.id) ?? conversation
        viewModel.loadConversation(selected)
        showingConversationList = false
    }
    #endif

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
        case .pasteAttachment:
            Task { @MainActor in
                do {
                    guard let attachment = try await ChatAttachmentLoader.pasteboardAttachment() else {
                        errorMessage = "There's nothing on the clipboard the chat can use. "
                            + "Copy an image, or a PDF, .txt, .md, or .json file."
                        return
                    }
                    stage(attachment)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .talk:
            showingTalkMode = true
        }
    }

    // MARK: - Dropped and pasted files

    /// Stage one attachment, whichever way it arrived.
    ///
    /// The single funnel for the photo picker, the file importer, a drop, and a
    /// paste. Sharing it is what keeps a dropped file validated exactly as
    /// strictly as a picked one, and it is the only place that enforces "one
    /// attachment at a time" — two independent optionals made "an image and a
    /// document at once" representable, and the composer cannot send that.
    @MainActor
    private func stage(_ attachment: ChatPendingAttachment) {
        switch attachment {
        case .image(let image):
            pendingImageAttachment = image
            pendingDocumentAttachment = nil
            if !isVisionModelReady { showingVisionModelSelection = true }
        case .document(let document):
            pendingDocumentAttachment = document
            pendingImageAttachment = nil
            if !areDocumentModelsReady { showNextDocumentModelPicker() }
        }
        isTextFieldFocused = true
    }

    /// Accept the first item of a drop or a ⌘V.
    ///
    /// One item, not all of them: the composer holds one attachment, and quietly
    /// dropping the other nine of a ten-file drag would be worse than saying so.
    /// Returns `true` whenever the drag is claimed, so the pointer does not show
    /// a rejection animation while the async read is still running.
    private func acceptDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        Task { @MainActor in
            do {
                if let url = try await Self.loadFileURL(from: provider) {
                    stage(try await ChatAttachmentLoader.attachment(forFileAt: url))
                } else if let data = try await Self.loadImageData(from: provider) {
                    stage(.image(try ChatAttachmentLoader.imageAttachment(
                        from: data,
                        filename: provider.suggestedName ?? "Dropped image"
                    )))
                } else {
                    errorMessage = "That can't be attached. Use an image, or a PDF, .txt, .md, or .json file."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        return true
    }

    private static func loadFileURL(from provider: NSItemProvider) async throws -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: url)
                }
            }
        }
    }

    /// Bytes for an image dragged from somewhere with no file behind it — a
    /// browser, Preview, a screenshot thumbnail.
    private static func loadImageData(from provider: NSItemProvider) async throws -> Data? {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
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
            await viewModel.sendImageQuestion(attachment: attachment, prompt: viewModel.currentInput)
            await refreshVisionModelStatus()
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
        }
    }

    func handleModelSelected(_ model: RAModelInfo) async {
        #if os(iOS)
        // ModelSelectionSheet may already have disconnected before calling
        // onModelSelected; deactivate must not depend on isConnected.
        if connectController.isConnected {
            connectController.disconnect()
        }
        if viewModel.isUsingConnect {
            await viewModel.deactivateConnectModel()
        }
        #endif
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
            stage(.image(try await ChatAttachmentLoader.imageAttachment(from: item)))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshVisionModelStatus() async {
        let state = await RunAnywhere.models.state()
        isVisionModelReady = state.loaded[.multimodal] != nil
    }

    private func handleDocumentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { @MainActor in
                do {
                    // Through the same validating entry point a drop uses. The
                    // importer's `allowedContentTypes` filters the picker, but
                    // the user can switch it to "All Files" — so the type and
                    // size are still checked here.
                    stage(try await ChatAttachmentLoader.attachment(forFileAt: url))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
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
        await ModelListViewModel.shared.loadModelsFromRegistry()

        if selectedDocumentEmbeddingModel == nil {
            selectedDocumentEmbeddingModel = ModelListViewModel.shared.availableModels.first {
                $0.category == .embedding
                    && $0.framework == .onnx
                    && !$0.id.hasSuffix("-vocab")
                    && !$0.id.hasSuffix("-tokenizer")
                    && $0.isAvailableForUse
            }
        }

        if selectedDocumentAnswerModel == nil {
            if let currentModel = ModelListViewModel.shared.currentModel,
               currentModel.category == .language,
               currentModel.framework == .llamaCpp,
               currentModel.isAvailableForUse {
                selectedDocumentAnswerModel = currentModel
                return
            }

            selectedDocumentAnswerModel = ModelListViewModel.shared.availableModels.first {
                $0.category == .language
                    && $0.framework == .llamaCpp
                    && $0.isAvailableForUse
            }
        }
    }
}
