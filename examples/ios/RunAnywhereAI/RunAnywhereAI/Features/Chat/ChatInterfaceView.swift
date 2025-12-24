//
//  ChatInterfaceView.swift
//  RunAnywhereAI
//
//  Simplified chat interface
//

import SwiftUI
import RunAnywhere
import os.log
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Use centralized design system colors

struct ChatInterfaceView: View {
    @StateObject private var viewModel = ChatViewModel()
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
            // macOS: No NavigationView to avoid sidebar
            ZStack {
                VStack(spacing: 0) {
                    // Add a custom toolbar for macOS
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

                    // Model Status Banner - Always visible
                    ModelStatusBanner(
                        framework: viewModel.selectedFramework,
                        modelName: viewModel.loadedModelName,
                        isLoading: viewModel.isGenerating && !hasModelSelected,
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
                .background(Color(NSColor.windowBackgroundColor))

                // Overlay when no model is selected
                if !hasModelSelected && !viewModel.isGenerating {
                    ModelRequiredOverlay(
                        modality: .llm,
                        onSelectModel: { showingModelSelection = true }
                    )
                }
            }
        #else
        // iOS: Keep NavigationView
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Model Status Banner - Always visible
                    ModelStatusBanner(
                        framework: viewModel.selectedFramework,
                        modelName: viewModel.loadedModelName,
                        isLoading: viewModel.isGenerating && !hasModelSelected,
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

                // Overlay when no model is selected
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
        .alert("Details", isPresented: $showDebugAlert) {
            Button("OK") { }
        } message: {
            Text(debugMessage)
        }
    }

    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    if viewModel.messages.isEmpty && !viewModel.isGenerating {
                        // Empty state view - consumer-friendly welcome
                        VStack(spacing: AppSpacing.xLarge) {
                            Spacer()

                            // Friendly icon
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [AppColors.primaryBlue.opacity(0.15), AppColors.primaryPurple.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 100, height: 100)

                                Image(systemName: "sparkles")
                                    .font(.system(size: 44))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [AppColors.primaryBlue, AppColors.primaryPurple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }

                            VStack(spacing: AppSpacing.smallMedium) {
                                Text("Hi there! 👋")
                                    .font(AppTypography.title2Semibold)
                                    .foregroundColor(AppColors.textPrimary)

                                Text("I'm your private AI assistant.\nAsk me anything!")
                                    .font(AppTypography.body)
                                    .foregroundColor(AppColors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }

                            // Suggestion chips
                            VStack(spacing: AppSpacing.smallMedium) {
                                Text("Try asking:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textSecondary)

                                HStack(spacing: AppSpacing.smallMedium) {
                                    SuggestionChip(text: "Tell me a joke") {
                                        viewModel.currentInput = "Tell me a joke"
                                    }
                                    SuggestionChip(text: "Explain AI") {
                                        viewModel.currentInput = "Explain artificial intelligence in simple terms"
                                    }
                                }
                                HStack(spacing: AppSpacing.smallMedium) {
                                    SuggestionChip(text: "Write a poem") {
                                        viewModel.currentInput = "Write a short poem about nature"
                                    }
                                    SuggestionChip(text: "Fun fact") {
                                        viewModel.currentInput = "Tell me an interesting fun fact"
                                    }
                                }
                            }
                            .padding(.top, AppSpacing.medium)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, AppSpacing.large)
                    } else {
                        LazyVStack(spacing: AppSpacing.large) {
                            // Add spacer at top for better scrolling
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

                            // Add spacer at bottom for better keyboard handling
                            Spacer(minLength: 20)
                                .id("bottom-spacer")
                        }
                        .padding(AppSpacing.large)
                    }
                }
                .defaultScrollAnchor(.bottom)
            }
            .background(AppColors.backgroundGrouped)
            .contentShape(Rectangle()) // Makes entire area tappable
            .onTapGesture {
                // Dismiss keyboard when tapping outside
                isTextFieldFocused = false
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                // Auto-scroll to bottom when new messages arrive
                let scrollToId: String
                if viewModel.isGenerating {
                    scrollToId = "typing"
                } else if let lastMessage = viewModel.messages.last {
                    scrollToId = lastMessage.id.uuidString
                } else {
                    scrollToId = "bottom-spacer"
                }

                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(scrollToId, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isGenerating) { _, isGenerating in
                if isGenerating {
                    // Scroll to bottom when generation starts
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
            .onChange(of: isTextFieldFocused) { _, focused in
                if focused {
                    // Scroll to bottom when keyboard appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        let scrollToId: String
                        if viewModel.isGenerating {
                            scrollToId = "typing"
                        } else if let lastMessage = viewModel.messages.last {
                            scrollToId = lastMessage.id.uuidString
                        } else {
                            scrollToId = "bottom-spacer"
                        }

                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(scrollToId, anchor: .bottom)
                        }
                    }
                } else {
                    // Scroll to bottom when keyboard dismisses
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        let scrollToId: String
                        if viewModel.isGenerating {
                            scrollToId = "typing"
                        } else if let lastMessage = viewModel.messages.last {
                            scrollToId = lastMessage.id.uuidString
                        } else {
                            scrollToId = "bottom-spacer"
                        }

                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(scrollToId, anchor: .bottom)
                        }
                    }
                }
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                // Scroll to bottom when keyboard shows
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let scrollToId: String
                    if viewModel.isGenerating {
                        scrollToId = "typing"
                    } else if let lastMessage = viewModel.messages.last {
                        scrollToId = lastMessage.id.uuidString
                    } else {
                        scrollToId = "bottom-spacer"
                    }

                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(scrollToId, anchor: .bottom)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                // Scroll to bottom when keyboard hides
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let scrollToId: String
                    if viewModel.isGenerating {
                        scrollToId = "typing"
                    } else if let lastMessage = viewModel.messages.last {
                        scrollToId = lastMessage.id.uuidString
                    } else {
                        scrollToId = "bottom-spacer"
                    }

                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(scrollToId, anchor: .bottom)
                    }
                }
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MessageContentUpdated"))) { _ in
                // Scroll to bottom during streaming updates (less frequent to avoid jitter)
                if viewModel.isGenerating {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
        }
    }

    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            // Info icon for chat details
            Button(action: { showingChatDetails = true }) {
                Image(systemName: "info.circle")
                    .foregroundColor(viewModel.messages.isEmpty ? AppColors.statusGray : AppColors.primaryAccent)
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

    private func sendMessage() {
        logger.info("🎯 sendMessage() called")
        logger.info("📝 viewModel.canSend: \(viewModel.canSend)")
        logger.info("📝 viewModel.isModelLoaded: \(viewModel.isModelLoaded)")
        logger.info("📝 viewModel.currentInput: '\(viewModel.currentInput)'")
        logger.info("📝 viewModel.isGenerating: \(viewModel.isGenerating)")

        guard viewModel.canSend else {
            logger.error("❌ canSend is false, returning")
            return
        }

        logger.info("✅ Launching task to send message")
        Task {
            await viewModel.sendMessage()

            // Check for errors after a short delay
            Task {
                try? await Task.sleep(nanoseconds: UInt64(AppLayout.animationSlow * 1_000_000_000)) // Use AppLayout timing
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
        // The model loading is already handled in the ModelSelectionSheet
        // Now we need to ensure our view model state is properly updated

        // First, ensure the ModelListViewModel has the current model set
        await MainActor.run {
            ModelListViewModel.shared.setCurrentModel(model)
        }

        // Then update our ChatViewModel to reflect the change
        await viewModel.checkModelStatus()
    }

    // MARK: - Helper Functions
    private func formatModelSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1fG", gb)
        } else {
            let mb = Double(bytes) / (1024 * 1024)
            return String(format: "%.0fM", mb)
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            let k = Double(number) / 1000.0
            return String(format: "%.0fK", k)
        }
        return "\(number)"
    }
}

// Professional typing indicator with animation
struct TypingIndicatorView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack {
            Spacer(minLength: AppSpacing.padding60)

            HStack(spacing: AppSpacing.mediumLarge) {
                // Animated dots
                HStack(spacing: AppSpacing.xSmall) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(AppColors.typingIndicatorDots)
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

// Enhanced message bubble view with 3D effects and professional styling
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
                // Model badge (only for assistant messages)
                if message.role == .assistant && message.modelInfo != nil {
                    modelBadgeSection
                }

                // Thinking section (only for assistant messages with thinking content)
                if message.role == .assistant && hasThinking {
                    thinkingSection
                }

                // Show thinking indicator for empty messages (during streaming)
                if message.role == .assistant && message.content.isEmpty && message.thinkingContent != nil && !message.thinkingContent!.isEmpty && isGenerating {
                    thinkingProgressIndicator
                }

                // Main message content
                mainMessageBubble

                // Timestamp and analytics summary
                timestampAndAnalyticsSection
            }

            if message.role != .user {
                Spacer(minLength: AppSpacing.padding60)
            }
        }
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            // Simple thinking toggle button
            Button(action: {
                withAnimation(.easeInOut(duration: AppLayout.animationFast)) {
                    isThinkingExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    // Simple icon
                    Image(systemName: "lightbulb.min")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)

                    // Clean summary text
                    Text(isThinkingExpanded ? "Hide reasoning" : thinkingSummary)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)
                        .lineLimit(1)

                    Spacer()

                    // Simple expand indicator
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

            // Expandable thinking content with cleaner design
            if isThinkingExpanded {
                VStack(spacing: 0) {
                    ScrollView {
                        Text(message.thinkingContent ?? "")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxHeight: AppSpacing.minFrameHeight) // Shorter max height
                    .padding(AppSpacing.mediumLarge)
                    .background(
                        RoundedRectangle(cornerRadius: AppSpacing.medium)
                            .fill(AppColors.backgroundGray6)
                    )

                    // Subtle completion status
                    if isThinkingIncomplete {
                        HStack {
                            Spacer()
                            Text("Reasoning incomplete")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.primaryOrange.opacity(0.8))
                                .italic()
                        }
                        .padding(.top, AppSpacing.xSmall)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .slide),
                    removal: .opacity.combined(with: .slide)
                ))
            }
        }
    }

    // Check if thinking content appears to be incomplete (doesn't end with punctuation or common ending words)
    private var isThinkingIncomplete: Bool {
        guard let thinking = message.thinkingContent?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }

        // Don't show incomplete during generation to avoid flickering
        if isGenerating { return false }

        // Check if thinking content seems to end abruptly
        let endsWithPunctuation = thinking.hasSuffix(".") || thinking.hasSuffix("!") || thinking.hasSuffix("?") || thinking.hasSuffix(":")
        let endsWithCommonWords = thinking.lowercased().hasSuffix("response") ||
                                 thinking.lowercased().hasSuffix("answer") ||
                                 thinking.lowercased().hasSuffix("message") ||
                                 thinking.lowercased().hasSuffix("reply") ||
                                 thinking.lowercased().hasSuffix("helpful") ||
                                 thinking.lowercased().hasSuffix("appropriate")

        // If content is longer than 100 chars and doesn't end properly, likely incomplete
        return thinking.count > 100 && !endsWithPunctuation && !endsWithCommonWords
    }

    // Generate intelligent summary from thinking content
    private var thinkingSummary: String {
        guard let thinking = message.thinkingContent?.trimmingCharacters(in: .whitespacesAndNewlines) else { return "" }

        // Extract key concepts from thinking content
        let sentences = thinking.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if sentences.count >= 2 {
            // Take first meaningful sentence as summary
            let firstSentence = sentences[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if firstSentence.count > 20 {
                return firstSentence + "..."
            }
        }

        // Fallback to truncated version
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
            // Animated thinking dots instead of brain icon
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
                // Model icon
                Image(systemName: "cube")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textWhite)

                // Model name
                Text(message.modelInfo?.modelName ?? "Unknown")
                    .font(AppTypography.caption2Medium)
                    .foregroundColor(AppColors.textWhite)

                // Framework badge
                Text(message.modelInfo?.framework ?? "")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textWhite.opacity(0.8))
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.regular)
                    .fill(LinearGradient(colors: [AppColors.primaryAccent, AppColors.primaryAccent.opacity(0.8)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: AppColors.shadowModelBadge, radius: 2, x: 0, y: 1)
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

            // Timestamp
            Text(message.timestamp, style: .time)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)

            // Analytics summary (if available)
            if let analytics = message.analytics {
                Group {
                    Text("•")
                        .foregroundColor(AppColors.textSecondary.opacity(0.5))

                    // Response time
                    Text("\(String(format: "%.1f", analytics.totalGenerationTime))s")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)

                    // Tokens per second (if meaningful)
                    if analytics.averageTokensPerSecond > 0 {
                        Text("•")
                            .foregroundColor(AppColors.textSecondary.opacity(0.5))

                        Text("\(Int(analytics.averageTokensPerSecond)) tok/s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Thinking mode indicator
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
        // Only show message bubble if there's content
        if !message.content.isEmpty {
            // Intelligent adaptive rendering: Content analysis → Best renderer
            Group {
                if message.role == .assistant {
                    AdaptiveMarkdownText(
                        message.content,
                        font: AppTypography.body,
                        color: AppColors.textPrimary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(message.content)
                        .foregroundColor(AppColors.textWhite)
                }
            }
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
            .scaleEffect(isGenerating && message.role == .assistant && message.content.count < 50 ? 1.02 : 1.0)
            .animation(.easeInOut(duration: AppLayout.animationLoopSlow).repeatForever(autoreverses: true), value: isGenerating)
        }
    }
}

// MARK: - Chat Details View

struct ChatDetailsView: View {
    let messages: [Message]
    let conversation: Conversation?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            #if os(macOS)
            // macOS: Use segmented control picker instead of TabView for better appearance
            VStack(spacing: 0) {
                // Tab selector
                Picker("Analytics", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Messages").tag(1)
                    Text("Performance").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Tab content
                Group {
                    switch selectedTab {
                    case 0:
                        ChatOverviewTab(messages: messages, conversation: conversation)
                    case 1:
                        MessageAnalyticsTab(messages: messages)
                    case 2:
                        PerformanceTab(messages: messages)
                    default:
                        ChatOverviewTab(messages: messages, conversation: conversation)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            // iOS: Use standard TabView
            TabView(selection: $selectedTab) {
                // Overview Tab
                ChatOverviewTab(messages: messages, conversation: conversation)
                    .tabItem {
                        Label("Overview", systemImage: "chart.bar")
                    }
                    .tag(0)

                // Message Analytics Tab
                MessageAnalyticsTab(messages: messages)
                    .tabItem {
                        Label("Messages", systemImage: "message")
                    }
                    .tag(1)

                // Performance Tab
                PerformanceTab(messages: messages)
                    .tabItem {
                        Label("Performance", systemImage: "speedometer")
                    }
                    .tag(2)
            }
            #endif
        }
        .navigationTitle("Chat Analytics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
            #else
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            #endif
        }
        .adaptiveSheetFrame(
            minWidth: 500,
            idealWidth: 650,
            maxWidth: 800,
            minHeight: 450,
            idealHeight: 550,
            maxHeight: 700
        )
    }
}

// MARK: - Overview Tab

struct ChatOverviewTab: View {
    let messages: [Message]
    let conversation: Conversation?

    private var analyticsMessages: [MessageAnalytics] {
        messages.compactMap { $0.analytics }
    }

    private var conversationSummary: String {
        let messageCount = messages.count
        let userMessages = messages.filter { $0.role == .user }.count
        let assistantMessages = messages.filter { $0.role == .assistant }.count
        return "\(messageCount) messages • \(userMessages) from you, \(assistantMessages) from AI"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                // Conversation Summary Card
                VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                    Text("Conversation Summary")
                        .font(AppTypography.headlineSemibold)

                    VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
                        HStack {
                            Image(systemName: "message.circle")
                                .foregroundColor(AppColors.primaryAccent)
                            Text(conversationSummary)
                                .font(AppTypography.subheadline)
                        }

                        if let conversation = conversation {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(AppColors.primaryAccent)
                                Text("Created \(conversation.createdAt, style: .relative)")
                                    .font(AppTypography.subheadline)
                            }
                        }

                        if !analyticsMessages.isEmpty {
                            HStack {
                                Image(systemName: "cube")
                                    .foregroundColor(AppColors.primaryAccent)
                                let models = Set(analyticsMessages.map { $0.modelName })
                                Text("\(models.count) model\(models.count == 1 ? "" : "s") used")
                                    .font(AppTypography.subheadline)
                            }
                        }
                    }
                }
                .padding(AppSpacing.large)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.mediumLarge)
                        .fill(AppColors.backgroundGray6)
                )

                // Performance Highlights
                if !analyticsMessages.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                        Text("Performance Highlights")
                            .font(.headline)
                            .fontWeight(.semibold)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: AppSpacing.mediumLarge) {
                            PerformanceCard(
                                title: "Avg Response Time",
                                value: String(format: "%.1fs", averageResponseTime),
                                icon: "timer",
                                color: AppColors.statusGreen
                            )

                            PerformanceCard(
                                title: "Avg Speed",
                                value: "\(Int(averageTokensPerSecond)) tok/s",
                                icon: "speedometer",
                                color: AppColors.statusBlue
                            )

                            PerformanceCard(
                                title: "Total Tokens",
                                value: "\(totalTokens)",
                                icon: "textformat.123",
                                color: AppColors.primaryPurple
                            )

                            PerformanceCard(
                                title: "Success Rate",
                                value: "\(Int(completionRate * 100))%",
                                icon: "checkmark.circle",
                                color: AppColors.statusOrange
                            )
                        }
                    }
                    .padding(AppSpacing.large)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppColors.backgroundGray6)
                    )
                }

                Spacer()
            }
            .padding(AppSpacing.large)
        }
    }

    private var averageResponseTime: Double {
        guard !analyticsMessages.isEmpty else { return 0 }
        return analyticsMessages.map { $0.totalGenerationTime }.reduce(0, +) / Double(analyticsMessages.count)
    }

    private var averageTokensPerSecond: Double {
        guard !analyticsMessages.isEmpty else { return 0 }
        return analyticsMessages.map { $0.averageTokensPerSecond }.reduce(0, +) / Double(analyticsMessages.count)
    }

    private var totalTokens: Int {
        return analyticsMessages.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }

    private var completionRate: Double {
        guard !analyticsMessages.isEmpty else { return 0 }
        let completed = analyticsMessages.filter { $0.completionStatus == .complete }.count
        return Double(completed) / Double(analyticsMessages.count)
    }
}

// MARK: - Performance Card

struct PerformanceCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: AppSpacing.smallMedium) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(AppTypography.title2Semibold)

                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                .fill(color.opacity(0.1))
                .strokeBorder(color.opacity(0.3), lineWidth: AppSpacing.strokeRegular)
        )
    }
}

// MARK: - Message Analytics Tab

struct MessageAnalyticsTab: View {
    let messages: [Message]

    private var analyticsMessages: [(Message, MessageAnalytics)] {
        messages.compactMap { message in
            if let analytics = message.analytics {
                return (message, analytics)
            }
            return nil
        }
    }

    var body: some View {
        List {
            ForEach(analyticsMessages.indices, id: \.self) { index in
                let messageWithAnalytics = analyticsMessages[index]
                let (message, analytics) = messageWithAnalytics
                MessageAnalyticsRow(
                    messageNumber: index + 1,
                    message: message,
                    analytics: analytics
                )
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Message Analytics Row

struct MessageAnalyticsRow: View {
    let messageNumber: Int
    let message: Message
    let analytics: MessageAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Message #\(messageNumber)")
                    .font(AppTypography.subheadlineSemibold)

                Spacer()

                Text(analytics.modelName)
                    .font(AppTypography.caption)
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, AppSpacing.xxSmall)
                    .background(AppColors.badgeBlue)
                    .cornerRadius(AppSpacing.cornerRadiusSmall)

                Text(analytics.framework)
                    .font(AppTypography.caption)
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, AppSpacing.xxSmall)
                    .background(AppColors.badgePurple)
                    .cornerRadius(AppSpacing.cornerRadiusSmall)
            }

            // Performance Metrics
            HStack(spacing: AppSpacing.large) {
                MetricView(
                    label: "Time",
                    value: String(format: "%.1fs", analytics.totalGenerationTime),
                    color: AppColors.statusGreen
                )

                if let ttft = analytics.timeToFirstToken {
                    MetricView(
                        label: "TTFT",
                        value: String(format: "%.1fs", ttft),
                        color: AppColors.statusBlue
                    )
                }

                MetricView(
                    label: "Speed",
                    value: "\(Int(analytics.averageTokensPerSecond)) tok/s",
                    color: AppColors.primaryPurple
                )

                if analytics.wasThinkingMode {
                    Image(systemName: "lightbulb.min")
                        .foregroundColor(AppColors.statusOrange)
                        .font(.caption)
                }
            }

            // Content Preview
            Text(message.content.prefix(100))
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Metric View

struct MetricView: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: AppSpacing.xxSmall) {
            Text(value)
                .font(AppTypography.captionMedium)
                .foregroundColor(color)

            Text(label)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Performance Tab

struct PerformanceTab: View {
    let messages: [Message]

    private var analyticsMessages: [MessageAnalytics] {
        messages.compactMap { $0.analytics }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                if !analyticsMessages.isEmpty {
                    // Models Used
                    VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                        Text("Models Used")
                            .font(.headline)
                            .fontWeight(.semibold)

                        let modelGroups = Dictionary(grouping: analyticsMessages) { $0.modelName }

                        ForEach(modelGroups.keys.sorted(), id: \.self) { modelName in
                            let modelMessages = modelGroups[modelName]!
                            let avgSpeed = modelMessages.map { $0.averageTokensPerSecond }.reduce(0, +) / Double(modelMessages.count)
                            let avgTime = modelMessages.map { $0.totalGenerationTime }.reduce(0, +) / Double(modelMessages.count)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(modelName)
                                        .font(AppTypography.subheadline)
                                        .fontWeight(.medium)

                                    Text("\(modelMessages.count) message\(modelMessages.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(String(format: "%.1fs avg", avgTime))
                                        .font(.caption)
                                        .foregroundColor(AppColors.statusGreen)

                                    Text("\(Int(avgSpeed)) tok/s")
                                        .font(.caption)
                                        .foregroundColor(AppColors.primaryAccent)
                                }
                            }
                            .padding(AppSpacing.large)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.backgroundGray6)
                            )
                        }
                    }

                    // Thinking Mode Analysis
                    if analyticsMessages.contains(where: { $0.wasThinkingMode }) {
                        VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                            Text("Thinking Mode Analysis")
                                .font(.headline)
                                .fontWeight(.semibold)

                            let thinkingMessages = analyticsMessages.filter { $0.wasThinkingMode }
                            let thinkingPercentage = Double(thinkingMessages.count) / Double(analyticsMessages.count) * 100

                            HStack {
                                Image(systemName: "lightbulb.min")
                                    .foregroundColor(AppColors.primaryPurple)

                                Text("Used in \(thinkingMessages.count) messages (\(String(format: "%.0f", thinkingPercentage))%)")
                                    .font(AppTypography.subheadline)
                            }
                            .padding(AppSpacing.large)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.primaryPurple.opacity(0.1))
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding(AppSpacing.large)
        }
    }
}

// MARK: - Suggestion Chip

/// A tappable suggestion chip for quick conversation starters
struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(AppTypography.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.primaryBlue)
                .padding(.horizontal, AppSpacing.mediumLarge)
                .padding(.vertical, AppSpacing.smallMedium)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
                        .fill(AppColors.primaryBlue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
                                .strokeBorder(AppColors.primaryBlue.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
