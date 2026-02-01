//
//  ChatInterfaceView.swift
//  RunAnywhereAI
//
//  Chat interface view - UI only, all logic in LLMViewModel
//

import SwiftUI
import RunAnywhere
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
        .sheet(isPresented: $showingConversationList) {
            ConversationListView()
        }
        .sheet(isPresented: $showingModelSelection) {
            ModelSelectionSheet(context: .llm) { model in
                await handleModelSelected(model)
            }
        }
        .sheet(isPresented: $showingChatDetails) {
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
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(!hasModelSelected)
            .toolbar {
                if hasModelSelected {
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
                }
            }
        }
        .navigationViewStyle(.stack)
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
                    if #available(iOS 26.0, *) {
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
