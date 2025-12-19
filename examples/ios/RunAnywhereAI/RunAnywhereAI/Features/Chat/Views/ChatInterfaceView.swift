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
    @FocusState private var isTextFieldFocused: Bool

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ChatInterfaceView")

    private var hasModelSelected: Bool {
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ModelLoaded"))) { _ in
            Task {
                await viewModel.checkModelStatus()
            }
        }
        .alert("Debug Info", isPresented: $showDebugAlert) {
            Button("OK") { }
        } message: {
            Text(debugMessage)
        }
    }

    // MARK: - macOS View

    private var macOSView: some View {
        ZStack {
            VStack(spacing: 0) {
                // Custom toolbar
                HStack {
                    Button(action: { showingConversationList = true }) {
                        Label("Conversations", systemImage: "list.bullet")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("Chat")
                        .font(AppTypography.headline)

                    Spacer()

                    toolbarButtons
                }
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.smallMedium)
                .background(AppColors.backgroundPrimary)

                ModelStatusBanner(
                    framework: viewModel.selectedFramework,
                    modelName: viewModel.loadedModelName,
                    isLoading: viewModel.isGenerating && !hasModelSelected,
                    supportsStreaming: viewModel.modelSupportsStreaming,
                    onSelectModel: { showingModelSelection = true }
                )
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if hasModelSelected {
                    chatMessagesView
                    inputArea
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.backgroundPrimary)

            if !hasModelSelected && !viewModel.isGenerating {
                ModelRequiredOverlay(
                    modality: .llm,
                    onSelectModel: { showingModelSelection = true }
                )
            }
        }
    }

    // MARK: - iOS View

    private var iOSView: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    ModelStatusBanner(
                        framework: viewModel.selectedFramework,
                        modelName: viewModel.loadedModelName,
                        isLoading: viewModel.isGenerating && !hasModelSelected,
                        supportsStreaming: viewModel.modelSupportsStreaming,
                        onSelectModel: { showingModelSelection = true }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    if hasModelSelected {
                        chatMessagesView
                        inputArea
                    } else {
                        Spacer()
                    }
                }

                if !hasModelSelected && !viewModel.isGenerating {
                    ModelRequiredOverlay(
                        modality: .llm,
                        onSelectModel: { showingModelSelection = true }
                    )
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingConversationList = true }) {
                        Image(systemName: "list.bullet")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    toolbarButtons
                }
            }
        }
    }

    // MARK: - Chat Messages View

    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    if viewModel.messages.isEmpty && !viewModel.isGenerating {
                        emptyStateView
                    } else {
                        messageListView
                    }
                }
                .defaultScrollAnchor(.bottom)
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
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MessageContentUpdated"))) { _ in
                if viewModel.isGenerating {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "message.circle")
                .font(AppTypography.system60)
                .foregroundColor(AppColors.textSecondary.opacity(0.6))

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

    // MARK: - Message List

    private var messageListView: some View {
        LazyVStack(spacing: AppSpacing.large) {
            Spacer(minLength: 20)
                .id("top-spacer")

            ForEach(viewModel.messages) { message in
                MessageBubbleView(message: message, isGenerating: viewModel.isGenerating)
                    .id(message.id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
            }

            if viewModel.isGenerating {
                TypingIndicatorView()
                    .id("typing")
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
            }

            Spacer(minLength: 20)
                .id("bottom-spacer")
        }
        .padding(AppSpacing.large)
    }

    // MARK: - Toolbar

    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            Button(action: { showingChatDetails = true }) {
                Image(systemName: "info.circle")
                    .foregroundColor(viewModel.messages.isEmpty ? .gray : .blue)
            }
            .disabled(viewModel.messages.isEmpty)
            #if os(macOS)
            .buttonStyle(.bordered)
            #endif

            Button(action: { showingModelSelection = true }) {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: "cube")
                    if viewModel.isModelLoaded {
                        Text("Switch Model")
                            .font(AppTypography.caption)
                    } else {
                        Text("Select Model")
                            .font(AppTypography.caption)
                    }
                }
            }
            #if os(macOS)
            .buttonStyle(.bordered)
            #endif

            Button(action: { viewModel.clearChat() }) {
                Image(systemName: "trash")
            }
            .disabled(viewModel.messages.isEmpty)
            #if os(macOS)
            .buttonStyle(.bordered)
            #endif
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
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
                        .foregroundColor(viewModel.canSend ? AppColors.primaryAccent : AppColors.statusGray)
                }
                .disabled(!viewModel.canSend)
            }
            .padding(AppSpacing.large)
            .background(AppColors.backgroundPrimary)
            .animation(.easeInOut(duration: AppLayout.animationFast), value: isTextFieldFocused)
        }
    }

    // MARK: - Helper Methods

    private func sendMessage() {
        guard viewModel.canSend else { return }

        Task {
            await viewModel.sendMessage()

            Task {
                try? await Task.sleep(nanoseconds: UInt64(AppLayout.animationSlow * 1_000_000_000))
                if let error = viewModel.error {
                    await MainActor.run {
                        debugMessage = "Error occurred: \(error.localizedDescription)"
                        showDebugAlert = true
                    }
                }
            }
        }
    }

    private func setupInitialState() {
        Task {
            await viewModel.checkModelStatus()
        }
    }

    private func handleModelSelected(_ model: ModelInfo) async {
        await MainActor.run {
            ModelListViewModel.shared.setCurrentModel(model)
        }

        await viewModel.checkModelStatus()
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
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

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack {
            Spacer(minLength: AppSpacing.padding60)

            HStack(spacing: AppSpacing.mediumLarge) {
                HStack(spacing: AppSpacing.xSmall) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(AppColors.primaryBlue.opacity(0.7))
                            .frame(width: AppSpacing.iconSmall, height: AppSpacing.iconSmall)
                            .scaleEffect(animationPhase == index ? 1.3 : 0.8)
                            .animation(
                                Animation.easeInOut(duration: AppLayout.animationVerySlow)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: animationPhase
                            )
                    }
                }
                .padding(.horizontal, AppSpacing.mediumLarge)
                .padding(.vertical, AppSpacing.smallMedium)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.large)
                        .fill(AppColors.backgroundGray5)
                        .shadow(color: AppColors.shadowLight, radius: 3, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppSpacing.large)
                                .strokeBorder(AppColors.borderLight, lineWidth: AppSpacing.strokeThin)
                        )
                )

                Text("AI is thinking...")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .opacity(0.8)
            }

            Spacer(minLength: AppSpacing.padding60)
        }
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    let isGenerating: Bool
    @State private var isThinkingExpanded = false

    var hasThinking: Bool {
        message.thinkingContent != nil && !(message.thinkingContent?.isEmpty ?? true)
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: AppSpacing.padding60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .assistant && message.modelInfo != nil {
                    modelBadgeSection
                }

                if message.role == .assistant && hasThinking {
                    thinkingSection
                }

                if message.role == .assistant &&
                    message.content.isEmpty &&
                    message.thinkingContent != nil &&
                    !message.thinkingContent!.isEmpty &&
                    isGenerating {
                    thinkingProgressIndicator
                }

                mainMessageBubble

                timestampAndAnalyticsSection
            }

            if message.role != .user {
                Spacer(minLength: AppSpacing.padding60)
            }
        }
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Button(action: {
                withAnimation(.easeInOut(duration: AppLayout.animationFast)) {
                    isThinkingExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.min")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)

                    Text(isThinkingExpanded ? "Hide reasoning" : thinkingSummary)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.right")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.primaryPurple.opacity(0.6))
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.padding9)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.mediumLarge)
                        .fill(LinearGradient(colors: [AppColors.primaryPurple.opacity(0.1), AppColors.primaryPurple.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: AppColors.primaryPurple.opacity(0.2), radius: 2, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppSpacing.mediumLarge)
                                .strokeBorder(AppColors.primaryPurple.opacity(0.2), lineWidth: AppSpacing.strokeThin)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())

            if isThinkingExpanded {
                ScrollView {
                    Text(message.thinkingContent ?? "")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxHeight: AppSpacing.minFrameHeight)
                .padding(AppSpacing.mediumLarge)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.medium)
                        .fill(AppColors.backgroundGray6)
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .slide),
                    removal: .opacity.combined(with: .slide)
                ))
            }
        }
    }

    private var thinkingSummary: String {
        guard let thinking = message.thinkingContent?.trimmingCharacters(in: .whitespacesAndNewlines) else { return "" }

        let sentences = thinking.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if sentences.count >= 2 {
            let firstSentence = sentences[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if firstSentence.count > 20 {
                return firstSentence + "..."
            }
        }

        if thinking.count > 80 {
            let truncated = String(thinking.prefix(80))
            if let lastSpace = truncated.lastIndex(of: " ") {
                return String(truncated[..<lastSpace]) + "..."
            }
            return truncated + "..."
        }

        return thinking
    }

    private var thinkingProgressIndicator: some View {
        HStack(spacing: AppSpacing.smallMedium) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(AppColors.primaryPurple)
                        .frame(width: AppSpacing.small, height: AppSpacing.small)
                        .scaleEffect(isGenerating ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: AppLayout.animationVerySlow)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: isGenerating
                        )
                }
            }

            Text("Thinking...")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.primaryPurple.opacity(0.8))
        }
        .padding(.horizontal, AppSpacing.mediumLarge)
        .padding(.vertical, AppSpacing.smallMedium)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.medium)
                .fill(LinearGradient(colors: [AppColors.primaryPurple.opacity(0.12), AppColors.primaryPurple.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: AppColors.primaryPurple.opacity(0.2), radius: 2, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.medium)
                        .strokeBorder(AppColors.primaryPurple.opacity(0.3), lineWidth: AppSpacing.strokeThin)
                )
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var modelBadgeSection: some View {
        HStack {
            if message.role == .assistant {
                Spacer()
            }

            HStack(spacing: AppSpacing.small) {
                Image(systemName: "cube")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textWhite)

                Text(message.modelInfo?.modelName ?? "Unknown")
                    .font(AppTypography.caption2Medium)
                    .foregroundColor(AppColors.textWhite)

                Text(message.modelInfo?.framework ?? "")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textWhite.opacity(0.8))
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.regular)
                    .fill(LinearGradient(colors: [AppColors.primaryBlue, AppColors.primaryBlue.opacity(0.8)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: AppColors.primaryBlue.opacity(0.3), radius: 2, x: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppSpacing.regular)
                            .strokeBorder(AppColors.textWhite.opacity(0.2), lineWidth: AppSpacing.strokeThin)
                    )
            )

            if message.role == .user {
                Spacer()
            }
        }
    }

    private var timestampAndAnalyticsSection: some View {
        HStack(spacing: 8) {
            if message.role == .assistant {
                Spacer()
            }

            Text(message.timestamp, style: .time)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)

            if let analytics = message.analytics {
                Group {
                    Text("•")
                        .foregroundColor(AppColors.textSecondary.opacity(0.5))

                    Text("\(String(format: "%.1f", analytics.totalGenerationTime))s")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)

                    if analytics.averageTokensPerSecond > 0 {
                        Text("•")
                            .foregroundColor(AppColors.textSecondary.opacity(0.5))

                        Text("\(Int(analytics.averageTokensPerSecond)) tok/s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if analytics.wasThinkingMode {
                        Image(systemName: "lightbulb.min")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.primaryPurple.opacity(0.7))
                    }
                }
            }

            if message.role == .user {
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var mainMessageBubble: some View {
        if !message.content.isEmpty {
            Text(message.content)
                .padding(.horizontal, AppSpacing.large)
                .padding(.vertical, AppSpacing.mediumLarge)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusBubble)
                        .fill(message.role == .user ?
                              LinearGradient(colors: [AppColors.userBubbleGradientStart, AppColors.userBubbleGradientEnd],
                                           startPoint: .topLeading, endPoint: .bottomTrailing) :
                              LinearGradient(colors: [AppColors.backgroundGray5, AppColors.backgroundGray6],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: AppColors.shadowMedium, radius: 4, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusBubble)
                                .strokeBorder(
                                    message.role == .user ?
                                    AppColors.borderLight :
                                    AppColors.borderMedium,
                                    lineWidth: AppSpacing.strokeThin
                                )
                        )
                )
                .foregroundColor(message.role == .user ? AppColors.textWhite : AppColors.textPrimary)
                .scaleEffect(isGenerating && message.role == .assistant && message.content.count < 50 ? 1.02 : 1.0)
                .animation(.easeInOut(duration: AppLayout.animationLoopSlow).repeatForever(autoreverses: true), value: isGenerating)
        }
    }
}
