//
//  ChatInterfaceView.swift
//  RunAnywhereAI
//
//  Simplified chat interface
//

import SwiftUI
import RunAnywhereSDK

struct ChatInterfaceView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var conversationStore = ConversationStore.shared
    @State private var showingConversationList = false
    @State private var showAnalyticsInline = true  // Default to true for better visibility
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                VStack(spacing: 8) {
                                    MessageBubbleView(message: message)
                                        .id(message.id)

                                    // Show analytics for assistant messages when toggle is enabled
                                    if message.role == .assistant && showAnalyticsInline {
                                        SessionAnalyticsView(sessionId: viewModel.currentSessionId)
                                    }
                                }
                            }

                            if viewModel.isGenerating {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .id("typing")
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                    .onTapGesture {
                        isTextFieldFocused = false
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            if let lastMessage = viewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input area
                inputArea
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
                    Button(action: { viewModel.clearChat() }) {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.messages.isEmpty)
                }
            }
            .sheet(isPresented: $showingConversationList) {
                ConversationListView()
            }
            .onAppear {
                setupInitialState()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ModelLoaded"))) { _ in
                Task {
                    await viewModel.checkModelStatus()
                }
            }
        }
    }

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()

            // Analytics toggle - make it extremely visible
            VStack(spacing: 8) {
                Text("📊 ANALYTICS TOGGLE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)

                HStack {
                    Toggle("Show Analytics", isOn: $showAnalyticsInline)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .onChange(of: showAnalyticsInline) { newValue in
                            updateAnalyticsConfig(newValue)
                        }
                    Spacer()
                    Text(showAnalyticsInline ? "✅ ON" : "❌ OFF")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(showAnalyticsInline ? .green : .red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.1))
            .border(Color.blue, width: 2)

            Divider()

            HStack(spacing: 12) {
                TextField("Type a message...", text: $viewModel.currentInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(viewModel.canSend ? .accentColor : .gray)
                }
                .disabled(!viewModel.canSend)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }

    private func sendMessage() {
        guard viewModel.canSend else { return }

        Task {
            await viewModel.sendMessage()
        }
    }

    private func setupInitialState() {
        Task {
            await viewModel.checkModelStatus()
            // Also check analytics configuration and sync with UI
            let analyticsEnabled = await RunAnywhereSDK.shared.getAnalyticsEnabled()
            await MainActor.run {
                showAnalyticsInline = analyticsEnabled  // Sync with SDK configuration
            }
        }
    }

    private func updateAnalyticsConfig(_ enabled: Bool) {
        Task {
            await RunAnywhereSDK.shared.setAnalyticsEnabled(enabled)
        }
    }
}

// Simple message bubble view
struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? Color.accentColor : Color(.systemGray5))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
    }
}
