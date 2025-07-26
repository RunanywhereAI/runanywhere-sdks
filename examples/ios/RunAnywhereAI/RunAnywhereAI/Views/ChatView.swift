//
//  ChatView.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var conversationStore = ConversationStore.shared
    @FocusState private var isInputFocused: Bool
    @State private var showingConversationList = false
    @State private var showingExportView = false
    
    @MainActor
    init(llmService: UnifiedLLMService? = nil) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(llmService: llmService))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if viewModel.isGenerating {
                            TypingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation {
                        if let lastMessage = viewModel.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input bar
            HStack(spacing: 12) {
                TextField("Type a message...", text: $viewModel.currentInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isInputFocused)
                    .onSubmit {
                        Task {
                            await viewModel.sendMessage()
                        }
                    }
                
                Button(action: {
                    Task {
                        await viewModel.sendMessage()
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.canSend ? .blue : .gray)
                }
                .disabled(!viewModel.canSend)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(conversationStore.currentConversation?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showingConversationList = true
                }) {
                    Image(systemName: "sidebar.left")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        newConversation()
                    }) {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    
                    Button(action: {
                        showingExportView = true
                    }) {
                        Label("Export Chat", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.messages.isEmpty)
                    
                    Divider()
                    
                    Button(action: viewModel.clearChat) {
                        Label("Clear Chat", systemImage: "trash")
                    }
                    .disabled(viewModel.messages.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingConversationList) {
            ConversationListView()
        }
        .sheet(isPresented: $showingExportView) {
            if let conversation = conversationStore.currentConversation {
                ConversationExportView(
                    conversation: conversation,
                    conversations: []
                )
            }
        }
        .onAppear {
            loadCurrentConversation()
        }
        .onChange(of: viewModel.messages) { _, _ in
            saveCurrentConversation()
        }
    }
    
    private func loadCurrentConversation() {
        if let conversation = conversationStore.currentConversation {
            viewModel.messages = conversation.messages
        } else {
            // Create a new conversation if none exists
            let conversation = conversationStore.createConversation()
            viewModel.messages = []
        }
    }
    
    private func newConversation() {
        let conversation = conversationStore.createConversation()
        viewModel.messages = []
    }
    
    private func saveCurrentConversation() {
        guard var conversation = conversationStore.currentConversation else { return }
        
        conversation.messages = viewModel.messages
        conversation.framework = UnifiedLLMService.shared.currentFramework
        conversation.modelInfo = UnifiedLLMService.shared.currentModel
        
        conversationStore.updateConversation(conversation)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    .cornerRadius(16)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: alignment)
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.blue
        case .assistant:
            return Color(.secondarySystemBackground)
        case .system:
            return Color.orange.opacity(0.2)
        }
    }
    
    private var textColor: Color {
        switch message.role {
        case .user:
            return .white
        case .assistant, .system:
            return .primary
        }
    }
    
    private var alignment: Alignment {
        message.role == .user ? .trailing : .leading
    }
}

struct TypingIndicator: View {
    @State private var animationAmount = 0.0
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundColor(.gray)
                        .scaleEffect(animationAmount)
                        .opacity(animationAmount)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animationAmount
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            
            Spacer()
        }
        .onAppear {
            animationAmount = 1.0
        }
    }
}

#Preview {
    NavigationView {
        ChatView()
    }
}
