//
//  MessageBubble.swift
//  LocalAIPlayground
//
//  =============================================================================
//  MESSAGE BUBBLE - CHAT UI COMPONENT
//  =============================================================================
//
//  A reusable chat message bubble component for displaying conversation
//  messages between the user and the AI assistant.
//
//  FEATURES:
//  - Distinct styling for user vs. assistant messages
//  - Support for streaming text with typing indicator
//  - Timestamp display
//  - Copy to clipboard functionality
//  - Smooth entrance animations
//
//  =============================================================================

import SwiftUI

// =============================================================================
// MARK: - Message Model
// =============================================================================
/// Represents a single message in a conversation.
// =============================================================================
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    
    /// Who sent this message
    enum MessageRole: Equatable {
        case user
        case assistant
        case system
    }
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

// =============================================================================
// MARK: - Message Bubble View
// =============================================================================
/// A chat bubble that displays a message with appropriate styling.
///
/// User messages appear on the right with the primary color.
/// Assistant messages appear on the left with a neutral background.
// =============================================================================
struct MessageBubble: View {
    let message: ChatMessage
    
    @Environment(\.colorScheme) var colorScheme
    @State private var showTimestamp = false
    @State private var appeared = false
    
    // -------------------------------------------------------------------------
    // MARK: - Computed Properties
    // -------------------------------------------------------------------------
    
    private var isUser: Bool {
        message.role == .user
    }
    
    private var bubbleColor: Color {
        if isUser {
            return .aiPrimary
        } else {
            return colorScheme == .dark 
                ? Color(white: 0.2) 
                : Color(white: 0.95)
        }
    }
    
    private var textColor: Color {
        if isUser {
            return .white
        } else {
            return colorScheme == .dark ? .white : .primary
        }
    }
    
    private var alignment: HorizontalAlignment {
        isUser ? .trailing : .leading
    }
    
    private var bubbleAlignment: Alignment {
        isUser ? .trailing : .leading
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------
    
    var body: some View {
        VStack(alignment: alignment, spacing: AISpacing.xs) {
            // Role indicator
            HStack(spacing: AISpacing.xs) {
                if !isUser {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Assistant")
                        .font(.aiCaption)
                        .foregroundStyle(.secondary)
                }
                
                if isUser {
                    Text("You")
                        .font(.aiCaption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Message bubble
            HStack {
                if isUser { Spacer(minLength: 60) }
                
                VStack(alignment: .leading, spacing: AISpacing.xs) {
                    // Message content
                    if message.content.isEmpty && message.isStreaming {
                        // Typing indicator when streaming with no content yet
                        TypingIndicator()
                    } else {
                        Text(message.content)
                            .font(.aiBody)
                            .foregroundStyle(textColor)
                            .textSelection(.enabled)
                        
                        // Streaming indicator
                        if message.isStreaming {
                            HStack(spacing: AISpacing.xs) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Generating...")
                                    .font(.aiCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, AISpacing.md)
                .padding(.vertical, AISpacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(bubbleColor)
                )
                .contextMenu {
                    Button(action: copyMessage) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                
                if !isUser { Spacer(minLength: 60) }
            }
            
            // Timestamp (shown on tap)
            if showTimestamp {
                Text(formattedTimestamp)
                    .font(.aiCaption)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: bubbleAlignment)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showTimestamp.toggle()
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Helper Methods
    // -------------------------------------------------------------------------
    
    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
    
    private func copyMessage() {
        UIPasteboard.general.string = message.content
    }
}

// =============================================================================
// MARK: - Typing Indicator
// =============================================================================
/// An animated typing indicator (three bouncing dots).
// =============================================================================
struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .offset(y: animating ? -4 : 4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// =============================================================================
// MARK: - Message Input Field
// =============================================================================
/// A text input field with send button for composing messages.
// =============================================================================
struct MessageInputField: View {
    @Binding var text: String
    let placeholder: String
    let isLoading: Bool
    let onSend: () -> Void
    
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: AISpacing.sm) {
            // Text input
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.aiBody)
                .lineLimit(1...5)
                .padding(.horizontal, AISpacing.md)
                .padding(.vertical, AISpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(colorScheme == .dark 
                              ? Color(white: 0.15) 
                              : Color(white: 0.95))
                )
                .focused($isFocused)
                .onSubmit {
                    if !text.isEmpty && !isLoading {
                        onSend()
                    }
                }
            
            // Send button
            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(text.isEmpty || isLoading 
                              ? Color.secondary.opacity(0.3) 
                              : Color.aiPrimary)
                        .frame(width: 40, height: 40)
                    
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(text.isEmpty || isLoading)
        }
        .padding(.horizontal, AISpacing.md)
        .padding(.vertical, AISpacing.sm)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
    }
}

// =============================================================================
// MARK: - Empty State View
// =============================================================================
/// Displayed when there are no messages in the chat.
// =============================================================================
struct EmptyChatView: View {
    let title: String
    let subtitle: String
    let suggestions: [String]
    let onSuggestionTap: (String) -> Void
    
    var body: some View {
        VStack(spacing: AISpacing.lg) {
            // Icon
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            // Title
            Text(title)
                .font(.aiHeading)
                .foregroundStyle(.primary)
            
            // Subtitle
            Text(subtitle)
                .font(.aiBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Suggestions
            if !suggestions.isEmpty {
                VStack(spacing: AISpacing.sm) {
                    Text("Try asking:")
                        .font(.aiCaption)
                        .foregroundStyle(.tertiary)
                    
                    VStack(spacing: AISpacing.sm) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: { onSuggestionTap(suggestion) }) {
                                Text(suggestion)
                                    .font(.aiBodySmall)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, AISpacing.md)
                                    .padding(.vertical, AISpacing.sm)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: AIRadius.md)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AISpacing.xl)
                }
            }
        }
        .padding()
    }
}

// =============================================================================
// MARK: - Previews
// =============================================================================
#Preview("Message Bubbles") {
    VStack(spacing: AISpacing.md) {
        MessageBubble(message: ChatMessage(
            role: .user,
            content: "Hello! Can you explain what on-device AI means?"
        ))
        
        MessageBubble(message: ChatMessage(
            role: .assistant,
            content: "On-device AI means all the AI processing happens locally on your device, rather than being sent to cloud servers. This provides better privacy and works offline!"
        ))
        
        MessageBubble(message: ChatMessage(
            role: .assistant,
            content: "",
            isStreaming: true
        ))
    }
    .padding()
}

#Preview("Message Input") {
    VStack {
        Spacer()
        MessageInputField(
            text: .constant(""),
            placeholder: "Ask me anything...",
            isLoading: false,
            onSend: {}
        )
    }
}

#Preview("Empty State") {
    EmptyChatView(
        title: "Start a Conversation",
        subtitle: "Ask questions and get responses from the on-device AI.",
        suggestions: [
            "What is the capital of France?",
            "Explain quantum computing simply",
            "Write a haiku about coding"
        ],
        onSuggestionTap: { _ in }
    )
}
