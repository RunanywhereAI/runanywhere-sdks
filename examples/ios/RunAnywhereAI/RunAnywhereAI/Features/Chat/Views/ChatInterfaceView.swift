//
//  ChatInterfaceView.swift
//  RunAnywhereAI
//
//  Chat interface view - UI only, all logic in LLMViewModel
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
    @State private var pendingLoRAURL: URL?
    @State private var loraScale: Float = 1.0
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
        .onAppear {
            setupInitialState()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("ModelLoaded"))
        ) { _ in
            Task {
                await viewModel.checkModelStatus()
                // Show toast when model is loaded
                if viewModel.isModelLoaded {
                    await MainActor.run {
                        showModelLoadedToast = true
                    }
                }
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
                let accessed = url.startAccessingSecurityScopedResource()
                Task {
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    await viewModel.loadLoraAdapter(path: url.path, scale: loraScale)
                    showingLoRAScaleSheet = false
                }
            } onCancel: {
                showingLoRAScaleSheet = false
            }
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showingLoRAManagement) {
            LoRAManagementSheetView(
                viewModel: viewModel,
                onOpenFilePicker: {
                    showingLoRAManagement = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingLoRAFilePicker = true
                    }
                },
                onDismiss: {
                    showingLoRAManagement = false
                }
            )
            .presentationDetents([.large])
        }
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
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - View Components

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
            chatMessagesView
            inputArea
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
                // Model logo instead of cube icon
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

                        // Streaming indicator
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

// MARK: - Chat Content Views

extension ChatInterfaceView {
    var chatMessagesView: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    if viewModel.messages.isEmpty && !viewModel.isGenerating {
                        emptyStateView
                    } else {
                        messageListView
                    }
                }
                .scrollDisabled(viewModel.messages.isEmpty && !viewModel.isGenerating)
                .defaultScrollAnchor(viewModel.messages.isEmpty && !viewModel.isGenerating ? .center : .bottom)
            }
            .background(AppColors.backgroundGrouped)
            .contentShape(Rectangle())
            .onTapGesture {
                isTextFieldFocused = false
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isGenerating) { _, isGenerating in
                if isGenerating {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: isTextFieldFocused) { _, focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }
            #if os(iOS)
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            #endif
            .onReceive(
                NotificationCenter.default.publisher(for: Notification.Name("MessageContentUpdated"))
            ) { _ in
                if viewModel.isGenerating {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("runanywhere_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(AppTypography.title2Semibold)
                    .foregroundColor(AppColors.textPrimary)

                Text("Type a message below to get started")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var messageListView: some View {
        LazyVStack(spacing: AppSpacing.large) {
            Spacer(minLength: 20)
                .id("top-spacer")

            ForEach(viewModel.messages) { message in
                MessageBubbleView(message: message, isGenerating: viewModel.isGenerating)
                    .id(message.id)
                    .transition(messageTransition)
                    .animation(nil, value: message.content)
            }

            if viewModel.isGenerating {
                TypingIndicatorView()
                    .id("typing")
                    .transition(typingTransition)
            }

            Spacer(minLength: 20)
                .id("bottom-spacer")
        }
        .padding(AppSpacing.large)
        .animation(.default, value: viewModel.messages.count)
    }

    private var messageTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8)
                .combined(with: .opacity)
                .combined(with: .move(edge: .bottom)),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }

    private var typingTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }

    var inputArea: some View {
        VStack(spacing: 0) {
            Divider()

            // Status badges (tool calling + LoRA)
            HStack(spacing: 8) {
                if viewModel.useToolCalling {
                    toolCallingBadge
                }

                if !viewModel.loraAdapters.isEmpty {
                    loraAdapterBadge
                }

                if hasModelSelected {
                    loraAddButton
                }
            }
            .padding(.top, (viewModel.useToolCalling || !viewModel.loraAdapters.isEmpty || hasModelSelected) ? 8 : 0)

            HStack(spacing: AppSpacing.mediumLarge) {
                TextField("Type a message...", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        sendMessage()
                    }
                    .submitLabel(.send)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(AppTypography.system28)
                        .foregroundColor(
                            viewModel.canSend ? AppColors.primaryAccent : AppColors.statusGray
                        )
                }
                .disabled(!viewModel.canSend)
                .background {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        Circle()
                            .fill(.clear)
                            .glassEffect(.regular.interactive())
                    }
                }
            }
            .padding(AppSpacing.large)
            .background(AppColors.backgroundPrimary)
            .animation(.easeInOut(duration: AppLayout.animationFast), value: isTextFieldFocused)
        }
    }

    var toolCallingBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 10))
            Text("Tools enabled")
                .font(AppTypography.caption2)
        }
        .foregroundColor(AppColors.primaryAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AppColors.primaryAccent.opacity(0.1))
        .cornerRadius(6)
    }

    var loraAdapterBadge: some View {
        Button {
            viewModel.refreshAvailableDemoAdapters()
            showingLoRAManagement = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("LoRA x\(viewModel.loraAdapters.count)")
                    .font(AppTypography.caption2)
            }
            .foregroundColor(.purple)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(6)
        }
    }

    var loraAddButton: some View {
        Button {
            viewModel.refreshAvailableDemoAdapters()
            showingLoRAManagement = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("LoRA")
                    .font(AppTypography.caption2)
            }
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(6)
        }
    }
}

// MARK: - LoRA Scale Sheet

private struct LoRAScaleSheetView: View {
    let url: URL?
    @Binding var scale: Float
    let isLoading: Bool
    let onLoad: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(.purple)

                    Text(url?.lastPathComponent ?? "LoRA Adapter")
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    Text("Scale: \(String(format: "%.1f", scale))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Slider(value: $scale, in: 0...2, step: 0.1)
                        .tint(.purple)

                    HStack {
                        Text("0.0")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("1.0")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("2.0")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)

                    Button {
                        onLoad()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(width: 60)
                        } else {
                            Text("Load")
                                .frame(width: 60)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isLoading)
                }
            }
            .padding()
            .navigationTitle("Load LoRA Adapter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - LoRA Management Sheet (Redesigned)

private struct LoRAManagementSheetView: View {
    @Bindable var viewModel: LLMViewModel
    let onOpenFilePicker: () -> Void
    let onDismiss: () -> Void

    @State private var selectedAdapterScale: [String: Float] = [:]

    var body: some View {
        NavigationView {
            List {
                availableAdaptersSection
                loadedAdaptersSection
                customAdapterSection
            }
            .navigationTitle("LoRA Adapters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Available Adapters (OTA Download)
    // TODO: [Portal Integration] Replace demo adapter section with portal-provided adapter catalog.

    @ViewBuilder
    private var availableAdaptersSection: some View {
        if !viewModel.availableDemoAdapters.isEmpty {
            Section {
                ForEach(viewModel.availableDemoAdapters) { adapter in
                    availableAdapterRow(adapter)
                }
            } header: {
                Text("Available for This Model")
            } footer: {
                Text("These adapters are downloaded from HuggingFace and stored locally.")
            }
        }
    }

    private func availableAdapterRow(_ adapter: DemoLoRAAdapter) -> some View {
        let isDownloaded = viewModel.isAdapterDownloaded(adapter)
        let isDownloading = viewModel.isDownloadingAdapter[adapter.id] == true
        let progress = viewModel.adapterDownloadProgress[adapter.id] ?? 0.0
        let scale = selectedAdapterScale[adapter.id] ?? adapter.defaultScale
        let isAlreadyApplied = viewModel.loraAdapters.contains {
            $0.path == viewModel.localPath(for: adapter)
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(adapter.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(adapter.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(adapter.fileSizeFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isAlreadyApplied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if isDownloaded {
                    Label("Downloaded", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .tint(.purple)
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if !isAlreadyApplied {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scale: \(String(format: "%.1f", scale))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(
                            value: Binding(
                                get: { selectedAdapterScale[adapter.id] ?? adapter.defaultScale },
                                set: { selectedAdapterScale[adapter.id] = $0 }
                            ),
                            in: 0...2,
                            step: 0.1
                        )
                        .tint(.purple)
                    }

                    Button {
                        let applyScale = selectedAdapterScale[adapter.id] ?? adapter.defaultScale
                        Task {
                            await viewModel.downloadAndLoadAdapter(adapter, scale: applyScale)
                        }
                    } label: {
                        Text(isDownloaded ? "Apply" : "Download & Apply")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(minWidth: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(viewModel.isLoadingLoRA)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Loaded Adapters

    @ViewBuilder
    private var loadedAdaptersSection: some View {
        if !viewModel.loraAdapters.isEmpty {
            Section("Loaded Adapters") {
                ForEach(viewModel.loraAdapters, id: \.path) { adapter in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: adapter.path).lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text("Scale: \(String(format: "%.1f", adapter.scale))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if adapter.applied {
                                    Text("Applied")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            Task { await viewModel.removeLoraAdapter(path: adapter.path) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(role: .destructive) {
                    Task {
                        await viewModel.clearLoraAdapters()
                    }
                } label: {
                    Label("Clear All Adapters", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Custom File Picker

    private var customAdapterSection: some View {
        Section {
            Button {
                onOpenFilePicker()
            } label: {
                Label("Load from Files...", systemImage: "folder")
            }
        } footer: {
            Text("Select a .gguf LoRA adapter file from your device.")
        }
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

    func setupInitialState() {
        Task {
            await viewModel.checkModelStatus()
        }
    }

    func handleModelSelected(_ model: ModelInfo) async {
        await MainActor.run {
            ModelListViewModel.shared.setCurrentModel(model)
        }

        await viewModel.checkModelStatus()
    }

    func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let scrollToId: String
        if viewModel.isGenerating {
            scrollToId = "typing"
        } else if let lastMessage = viewModel.messages.last {
            scrollToId = lastMessage.id.uuidString
        } else {
            scrollToId = "bottom-spacer"
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo(scrollToId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(scrollToId, anchor: .bottom)
        }
    }
}
