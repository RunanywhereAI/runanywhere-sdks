//
//  ChatInterfaceView.swift
//  RunAnywhereAI
//
//  Simplified chat interface
//

import SwiftUI
import RunAnywhereSDK
import os.log

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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                chatMessagesView
                inputArea
            }
            .navigationTitle(viewModel.isModelLoaded ? (viewModel.loadedModelName ?? "Chat") : "Chat")
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
            .sheet(isPresented: $showingConversationList) {
                ConversationListView()
            }
            .sheet(isPresented: $showingModelSelection) {
                ModelSelectionSheet { model in
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
    }

    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Minimalistic model info bar at top
                if viewModel.isModelLoaded, let modelName = viewModel.loadedModelName {
                    modelInfoBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    if viewModel.messages.isEmpty && !viewModel.isGenerating {
                        // Empty state view
                        VStack(spacing: 16) {
                            Spacer()

                            Image(systemName: "message.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary.opacity(0.6))

                            VStack(spacing: 8) {
                                Text("Start a conversation")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                if viewModel.isModelLoaded {
                                    Text("Type a message below to get started")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Select a model first, then start chatting")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LazyVStack(spacing: 16) {
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
                        .padding()
                    }
                }
                .defaultScrollAnchor(.bottom)
            }
            .background(Color(.systemGroupedBackground))
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
                    .foregroundColor(viewModel.messages.isEmpty ? .gray : .blue)
            }
            .disabled(viewModel.messages.isEmpty)

            Button(action: { showingModelSelection = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "cube")
                    if viewModel.isModelLoaded {
                        Text("Switch")
                            .font(.caption)
                    } else {
                        Text("Select")
                            .font(.caption)
                    }
                }
            }

            Button(action: { viewModel.clearChat() }) {
                Image(systemName: "trash")
            }
            .disabled(viewModel.messages.isEmpty)
        }
    }

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()

            // Show model selection prompt if no model is loaded
            if !viewModel.isModelLoaded {
                VStack(spacing: 8) {
                    Text("Welcome! Select and download a model to start chatting.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Select Model") {
                        showingModelSelection = true
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))

                Divider()
            }

            HStack(spacing: 12) {
                TextField("Type a message...", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(!viewModel.isModelLoaded)
                    .submitLabel(.send)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(viewModel.canSend ? .accentColor : .gray)
                }
                .disabled(!viewModel.canSend)
            }
            .padding()
            .background(Color(.systemBackground))
            .animation(.easeInOut(duration: 0.25), value: isTextFieldFocused)
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
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
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
        // Just update our view model to reflect the change
        await viewModel.checkModelStatus()
    }

    // MARK: - Scroll Management - Functions inlined to avoid typing issues

    // Minimalistic model info bar
    private var modelInfoBar: some View {
        HStack(spacing: 8) {
            // Framework indicator
            if let currentModel = ModelListViewModel.shared.currentModel {
                Text(currentModel.compatibleFrameworks.first?.rawValue.uppercased() ?? "AI")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                    )
            }

            // Model name (shortened)
            Text(viewModel.loadedModelName?.components(separatedBy: " ").first ?? "Model")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

            Spacer()

            // Key stats
            if let currentModel = ModelListViewModel.shared.currentModel {
                HStack(spacing: 12) {
                    // Model size
                    HStack(spacing: 3) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 8))
                        Text(formatModelSize(currentModel.estimatedMemory))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.secondary)

                    // Context length
                    HStack(spacing: 3) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 8))
                        Text("\(formatNumber(currentModel.contextLength))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            Rectangle()
                .fill(Color(.systemBackground).opacity(0.95))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(.separator))
                        .offset(y: 12)
                )
        )
    }

    // Helper functions for formatting
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
            Spacer(minLength: 60)

            HStack(spacing: 12) {
                // Animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == index ? 1.3 : 0.8)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: animationPhase
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray5))
                        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                )

                Text("AI is thinking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(0.8)
            }

            Spacer(minLength: 60)
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
                Spacer(minLength: 60)
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
                Spacer(minLength: 60)
            }
        }
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Simple thinking toggle button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isThinkingExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    // Simple icon
                    Image(systemName: "lightbulb.min")
                        .font(.caption)
                        .foregroundColor(.purple)

                    // Clean summary text
                    Text(isThinkingExpanded ? "Hide reasoning" : thinkingSummary)
                        .font(.caption)
                        .foregroundColor(.purple)
                        .lineLimit(1)

                    Spacer()

                    // Simple expand indicator
                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.purple.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color.purple.opacity(0.1), Color.purple.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .purple.opacity(0.2), radius: 2, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.purple.opacity(0.2), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable thinking content with cleaner design
            if isThinkingExpanded {
                VStack(spacing: 0) {
                    ScrollView {
                        Text(message.thinkingContent ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxHeight: 150) // Shorter max height
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                    )

                    // Subtle completion status
                    if isThinkingIncomplete {
                        HStack {
                            Spacer()
                            Text("Reasoning incomplete")
                                .font(.caption2)
                                .foregroundColor(.orange.opacity(0.8))
                                .italic()
                        }
                        .padding(.top, 4)
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
        HStack(spacing: 8) {
            // Animated thinking dots instead of brain icon
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isGenerating ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: isGenerating
                        )
                }
            }

            Text("Thinking...")
                .font(.caption)
                .foregroundColor(.purple.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color.purple.opacity(0.12), Color.purple.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .purple.opacity(0.2), radius: 2, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.purple.opacity(0.3), lineWidth: 0.5)
                )
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var modelBadgeSection: some View {
        HStack {
            if message.role == .assistant {
                Spacer()
            }

            HStack(spacing: 6) {
                // Model icon
                Image(systemName: "cube")
                    .font(.caption2)
                    .foregroundColor(.white)

                // Model name
                Text(message.modelInfo?.modelName ?? "Unknown")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                // Framework badge
                Text(message.modelInfo?.framework ?? "")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
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
                .font(.caption2)
                .foregroundColor(.secondary)

            // Analytics summary (if available)
            if let analytics = message.analytics {
                Group {
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    // Response time
                    Text("\(String(format: "%.1f", analytics.totalGenerationTime))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Tokens per second (if meaningful)
                    if analytics.averageTokensPerSecond > 0 {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("\(Int(analytics.averageTokensPerSecond)) tok/s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Thinking mode indicator
                    if analytics.wasThinkingMode {
                        Image(systemName: "lightbulb.min")
                            .font(.caption2)
                            .foregroundColor(.purple.opacity(0.7))
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
            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(message.role == .user ?
                              LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.9)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing) :
                              LinearGradient(colors: [Color(.systemGray5), Color(.systemGray6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(
                                    message.role == .user ?
                                    Color.white.opacity(0.3) :
                                    Color.black.opacity(0.05),
                                    lineWidth: 0.5
                                )
                        )
                )
                .foregroundColor(message.role == .user ? .white : .primary)
                .scaleEffect(isGenerating && message.role == .assistant && message.content.count < 50 ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isGenerating)
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
        NavigationView {
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
            .navigationTitle("Chat Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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
            VStack(spacing: 20) {
                // Conversation Summary Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Conversation Summary")
                        .font(.headline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "message.circle")
                                .foregroundColor(.blue)
                            Text(conversationSummary)
                                .font(.subheadline)
                        }

                        if let conversation = conversation {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.blue)
                                Text("Created \(conversation.createdAt, style: .relative)")
                                    .font(.subheadline)
                            }
                        }

                        if !analyticsMessages.isEmpty {
                            HStack {
                                Image(systemName: "cube")
                                    .foregroundColor(.blue)
                                let models = Set(analyticsMessages.map { $0.modelName })
                                Text("\(models.count) model\(models.count == 1 ? "" : "s") used")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )

                // Performance Highlights
                if !analyticsMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Performance Highlights")
                            .font(.headline)
                            .fontWeight(.semibold)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            PerformanceCard(
                                title: "Avg Response Time",
                                value: String(format: "%.1fs", averageResponseTime),
                                icon: "timer",
                                color: .green
                            )

                            PerformanceCard(
                                title: "Avg Speed",
                                value: "\(Int(averageTokensPerSecond)) tok/s",
                                icon: "speedometer",
                                color: .blue
                            )

                            PerformanceCard(
                                title: "Total Tokens",
                                value: "\(totalTokens)",
                                icon: "textformat.123",
                                color: .purple
                            )

                            PerformanceCard(
                                title: "Success Rate",
                                value: "\(Int(completionRate * 100))%",
                                icon: "checkmark.circle",
                                color: .orange
                            )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                }

                Spacer()
            }
            .padding()
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
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
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
            ForEach(Array(analyticsMessages.enumerated()), id: \.1.0.id) { index, messageWithAnalytics in
                let (message, analytics) = messageWithAnalytics
                MessageAnalyticsRow(
                    messageNumber: index + 1,
                    message: message,
                    analytics: analytics
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(analytics.modelName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)

                Text(analytics.framework)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
            }

            // Performance Metrics
            HStack(spacing: 16) {
                MetricView(
                    label: "Time",
                    value: String(format: "%.1fs", analytics.totalGenerationTime),
                    color: .green
                )

                if let ttft = analytics.timeToFirstToken {
                    MetricView(
                        label: "TTFT",
                        value: String(format: "%.1fs", ttft),
                        color: .blue
                    )
                }

                MetricView(
                    label: "Speed",
                    value: "\(Int(analytics.averageTokensPerSecond)) tok/s",
                    color: .purple
                )

                if analytics.wasThinkingMode {
                    Image(systemName: "lightbulb.min")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }

            // Content Preview
            Text(message.content.prefix(100))
                .font(.caption)
                .foregroundColor(.secondary)
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
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
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
            VStack(spacing: 20) {
                if !analyticsMessages.isEmpty {
                    // Models Used
                    VStack(alignment: .leading, spacing: 12) {
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
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text("\(modelMessages.count) message\(modelMessages.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(String(format: "%.1fs avg", avgTime))
                                        .font(.caption)
                                        .foregroundColor(.green)

                                    Text("\(Int(avgSpeed)) tok/s")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray6))
                            )
                        }
                    }

                    // Thinking Mode Analysis
                    if analyticsMessages.contains(where: { $0.wasThinkingMode }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Thinking Mode Analysis")
                                .font(.headline)
                                .fontWeight(.semibold)

                            let thinkingMessages = analyticsMessages.filter { $0.wasThinkingMode }
                            let thinkingPercentage = Double(thinkingMessages.count) / Double(analyticsMessages.count) * 100

                            HStack {
                                Image(systemName: "lightbulb.min")
                                    .foregroundColor(.purple)

                                Text("Used in \(thinkingMessages.count) messages (\(String(format: "%.0f", thinkingPercentage))%)")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.purple.opacity(0.1))
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }
}
