//
//  ChatView.swift
//  LocalAIPlayground
//
//  =============================================================================
//  CHAT VIEW - ON-DEVICE LLM INTERACTION
//  =============================================================================
//
//  This view demonstrates how to use the RunAnywhere SDK's LLM capabilities
//  for on-device text generation with streaming support.
//
//  KEY CONCEPTS DEMONSTRATED:
//
//  1. MODEL LOADING
//     - Models must be registered, downloaded, and loaded via ModelService
//     - The view checks modelService.isLLMLoaded before enabling chat
//
//  2. TEXT GENERATION
//     - RunAnywhere.generateStream() for streaming token generation
//     - LLMGenerationOptions for configuring temperature, max tokens, etc.
//
//  3. STREAMING UI
//     - Real-time token display as they're generated
//     - Performance metrics (tokens/second)
//     - Graceful handling of generation state
//
//  RUNANYWHERE SDK METHODS USED:
//  - RunAnywhere.generateStream() - Streaming generation
//  - LLMGenerationOptions        - Configure generation parameters
//
//  =============================================================================

import SwiftUI
import RunAnywhere

// =============================================================================
// MARK: - Chat View
// =============================================================================
/// A chat interface for interacting with the on-device LLM.
///
/// This view provides a familiar chat UI where users can send messages
/// and receive AI-generated responses with real-time streaming.
// =============================================================================
struct ChatView: View {
    // -------------------------------------------------------------------------
    // MARK: - Environment & State Properties
    // -------------------------------------------------------------------------
    
    /// Model service for checking LLM state and loading
    @EnvironmentObject var modelService: ModelService
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    /// List of messages in the conversation
    @State private var messages: [ChatMessage] = []
    
    /// Current text in the input field
    @State private var inputText = ""
    
    /// Whether the AI is currently generating a response
    @State private var isGenerating = false
    
    /// Current response being streamed
    @State private var currentResponse = ""
    
    /// Task for streaming generation (so we can cancel it)
    @State private var streamingTask: Task<Void, Never>?
    
    /// Focus state for the input field
    @FocusState private var isInputFocused: Bool
    
    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.98))
                    .ignoresSafeArea()
                
                // Check if model is loaded
                if !modelService.isLLMLoaded {
                    // Show model loader
                    modelLoaderOverlay
                } else {
                    // Show chat interface
                    chatInterface
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        streamingTask?.cancel()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !messages.isEmpty {
                        Button(action: clearChat) {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .onDisappear {
            streamingTask?.cancel()
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Model Loader Overlay
    // -------------------------------------------------------------------------
    
    private var modelLoaderOverlay: some View {
        VStack(spacing: AISpacing.xl) {
            Spacer()
            
            ModelLoaderView(
                modelName: "LiquidAI LFM2 350M",
                modelDescription: "Compact on-device language model optimized for mobile inference with Q4_K_M quantization.",
                modelSize: "~250MB",
                state: modelLoaderState,
                onLoad: {
                    Task {
                        await modelService.downloadAndLoadLLM()
                    }
                },
                onRetry: {
                    Task {
                        await modelService.downloadAndLoadLLM()
                    }
                }
            )
            .padding(.horizontal)
            
            // Info text
            VStack(spacing: AISpacing.sm) {
                Text("First-time setup")
                    .font(.aiHeadingSmall)
                
                Text("The model will be downloaded once and cached locally for future use.")
                    .font(.aiBodySmall)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AISpacing.xl)
            
            Spacer()
        }
    }
    
    /// Converts ModelService state to ModelState for the loader view
    private var modelLoaderState: ModelState {
        if modelService.isLLMLoaded {
            return .ready
        } else if modelService.isLLMLoading {
            return .loading
        } else if modelService.isLLMDownloading {
            return .downloading(progress: modelService.llmDownloadProgress)
        } else {
            return .notLoaded
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Chat Interface
    // -------------------------------------------------------------------------
    
    private var chatInterface: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AISpacing.md) {
                        if messages.isEmpty {
                            // Empty state
                            EmptyChatView(
                                title: "Start Chatting",
                                subtitle: "Ask questions, get explanations, or just have a conversation with the AI.",
                                suggestions: [
                                    "Tell me a joke",
                                    "What is AI?",
                                    "Write a haiku"
                                ],
                                onSuggestionTap: { suggestion in
                                    inputText = suggestion
                                    sendMessage()
                                }
                            )
                            .padding(.top, AISpacing.xxl)
                        } else {
                            // Message bubbles
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            // Streaming message
                            if isGenerating {
                                MessageBubble(message: ChatMessage(
                                    role: .assistant,
                                    content: currentResponse.isEmpty ? "..." : currentResponse,
                                    isStreaming: true
                                ))
                                .id("streaming")
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: currentResponse) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            
            // Input field
            MessageInputField(
                text: $inputText,
                placeholder: "Ask me anything...",
                isLoading: isGenerating,
                onSend: sendMessage
            )
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isGenerating {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    // =========================================================================
    // MARK: - Message Sending & Generation
    // =========================================================================
    
    /// Sends the current input as a user message and generates a response.
    // -------------------------------------------------------------------------
    private func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty && !isGenerating else { return }
        
        // Add user message
        let userMessage = ChatMessage(role: .user, content: userText)
        messages.append(userMessage)
        
        // Clear input
        inputText = ""
        isInputFocused = false
        
        // Start generation
        isGenerating = true
        currentResponse = ""
        
        streamingTask = Task {
            await generateResponse(to: userText)
        }
    }
    
    /// Generates an AI response to the given prompt using streaming.
    ///
    /// ## RunAnywhere SDK Usage
    ///
    /// This method demonstrates `RunAnywhere.generateStream()` which:
    /// 1. Takes a prompt and generation options
    /// 2. Returns a stream of tokens as they're generated
    /// 3. Provides final metrics after generation completes
    ///
    /// - Parameter prompt: The user's message to respond to
    // -------------------------------------------------------------------------
    private func generateResponse(to prompt: String) async {
        do {
            // -----------------------------------------------------------------
            // Configure Generation Options
            // -----------------------------------------------------------------
            // LLMGenerationOptions controls how the model generates text:
            //
            // - maxTokens: Limits response length
            // - temperature: Higher = more creative, lower = more focused
            //   - 0.0-0.3: Factual, deterministic responses
            //   - 0.4-0.7: Balanced creativity and coherence
            //   - 0.8-1.0: Creative, varied responses
            // -----------------------------------------------------------------
            let options = LLMGenerationOptions(
                maxTokens: 256,
                temperature: 0.8
            )
            
            // -----------------------------------------------------------------
            // Start Streaming Generation
            // -----------------------------------------------------------------
            // generateStream() returns a StreamingResult containing:
            // - stream: AsyncStream<String> of tokens
            // - result: Task<GenerationResult, Error> with final metrics
            // -----------------------------------------------------------------
            let result = try await RunAnywhere.generateStream(
                prompt,
                options: options
            )
            
            // -----------------------------------------------------------------
            // Process Streaming Tokens
            // -----------------------------------------------------------------
            for try await token in result.stream {
                guard !Task.isCancelled else { break }
                
                await MainActor.run {
                    currentResponse += token
                }
            }
            
            // -----------------------------------------------------------------
            // Get Final Metrics
            // -----------------------------------------------------------------
            let metrics = try await result.result.value
            
            await MainActor.run {
                if !Task.isCancelled {
                    // Add assistant message with metrics
                    let aiMessage = ChatMessage(
                        role: .assistant,
                        content: currentResponse
                    )
                    messages.append(aiMessage)
                    
                    print("✅ Generation: \(metrics.tokensUsed) tokens at \(String(format: "%.1f", metrics.tokensPerSecond)) tok/s")
                }
                
                isGenerating = false
                currentResponse = ""
            }
            
        } catch {
            await MainActor.run {
                // Add error message
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "Error: \(error.localizedDescription)"
                )
                messages.append(errorMessage)
                
                isGenerating = false
                currentResponse = ""
            }
            
            print("❌ Generation failed: \(error)")
        }
    }
    
    /// Clears all messages from the conversation.
    // -------------------------------------------------------------------------
    private func clearChat() {
        streamingTask?.cancel()
        messages.removeAll()
        currentResponse = ""
        isGenerating = false
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================
#Preview {
    ChatView()
        .environmentObject(ModelService())
}
