//
//  ChatViewModelEnhanced.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ChatViewModelEnhanced: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var selectedFramework: LLMFramework = .mlx
    @Published var selectedModel: RunAnywhereAI.ModelInfo? {
        didSet {
            if oldValue?.id != selectedModel?.id {
                // Model changed, unload the previous model
                if oldValue != nil {
                    Task {
                        await unloadCurrentModel()
                    }
                }
                // Don't load the new model yet - wait for first message
            }
        }
    }
    @Published var currentTokensPerSecond: Double?
    @Published var settings = ChatSettings()
    @Published var currentInput = ""
    @Published var error: Error?
    @Published var isLoadingModel = false
    @Published var modelLoadingProgress: String = ""

    // MARK: - Private Properties
    private let unifiedService = UnifiedLLMService.shared
    private let performanceMonitor = RealtimePerformanceMonitor.shared
    private let logger = Logger.shared
    private let conversationStore = ConversationStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var generationTask: Task<Void, Never>?
    private var currentConversation: Conversation?

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    // MARK: - Initialization
    init() {
        setupSubscriptions()
        createNewConversation()
        addWelcomeMessage()
    }

    // MARK: - Public Methods

    func sendMessage() async {
        guard canSend else { return }

        // Check if model is selected
        guard let model = selectedModel else {
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "Please select a model before chatting.",
                timestamp: Date()
            )
            messages.append(errorMessage)
            return
        }

        // Ensure the service is selected for the current framework
        unifiedService.selectService(named: selectedFramework.displayName)

        // Check if model is loaded, if not, load it now (lazy loading)
        if let service = unifiedService.currentService {
            switch service.modelState {
            case .unloaded:
                // Load the model now
                await MainActor.run {
                    isLoadingModel = true
                    modelLoadingProgress = "Loading \(model.name)..."
                }

                do {
                    try await loadSelectedModel(model)
                } catch {
                    let errorMessage = ChatMessage(
                        role: .assistant,
                        content: "Failed to load model: \(error.localizedDescription)",
                        timestamp: Date()
                    )
                    messages.append(errorMessage)
                    return
                }

            case .loading:
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "Model is still loading. Please wait...",
                    timestamp: Date()
                )
                messages.append(errorMessage)
                return

            case .failed(let error):
                // Try to reload the model
                await MainActor.run {
                    isLoadingModel = true
                    modelLoadingProgress = "Retrying to load \(model.name)..."
                }

                do {
                    try await loadSelectedModel(model)
                } catch {
                    let errorMessage = ChatMessage(
                        role: .assistant,
                        content: "Model failed to load: \(error.localizedDescription)",
                        timestamp: Date()
                    )
                    messages.append(errorMessage)
                    return
                }

            case .loaded:
                // Model is ready, continue with message
                break
            }
        } else {
            // No service available for this framework - try to load the model which will create the service
            await MainActor.run {
                isLoadingModel = true
                modelLoadingProgress = "Initializing \(selectedFramework.displayName) service..."
            }

            do {
                try await loadSelectedModel(model)
            } catch {
                let errorMessage = ChatMessage(
                    role: .assistant,
                    content: "Failed to initialize \(selectedFramework.displayName): \(error.localizedDescription)",
                    timestamp: Date()
                )
                messages.append(errorMessage)
                return
            }
        }

        let userMessage = ChatMessage(
            role: .user,
            content: currentInput,
            timestamp: Date()
        )
        messages.append(userMessage)

        // Save to conversation store
        if let conversation = currentConversation {
            conversationStore.addMessage(userMessage, to: conversation)
        }

        let prompt = currentInput
        currentInput = ""
        isGenerating = true
        error = nil
        currentTokensPerSecond = nil

        // Start performance monitoring
        performanceMonitor.beginGeneration(framework: selectedFramework, prompt: prompt)

        // Create assistant message placeholder
        var assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            timestamp: Date()
        )
        assistantMessage.framework = selectedFramework
        if let model = selectedModel {
            assistantMessage.modelName = model.name
            assistantMessage.modelId = model.id
            assistantMessage.modelInfo = model
        }
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        generationTask = Task {
            do {
                print("📝 Starting generation for prompt: \(prompt)")
                print("📱 Framework: \(selectedFramework.displayName)")
                print("🤖 Model: \(selectedModel?.name ?? "unknown")")

                // Switch framework if needed
                unifiedService.selectService(named: selectedFramework.displayName)

                if settings.streamResponses {
                    print("🌊 Using streaming generation")
                    // Stream generation
                    try await streamGeneration(prompt: prompt, messageIndex: messageIndex)
                } else {
                    print("📦 Using non-streaming generation")
                    // Non-streaming generation
                    let response = try await generateResponse(prompt: prompt)
                    messages[messageIndex].content = response.text
                    messages[messageIndex].generationMetrics = response.metrics
                }

                // Save the completed message to conversation store
                if let conversation = currentConversation {
                    conversationStore.addMessage(messages[messageIndex], to: conversation)

                    // Update conversation with current model and framework
                    var updated = conversation
                    updated.framework = selectedFramework
                    updated.modelInfo = selectedModel
                    conversationStore.updateConversation(updated)
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    if messageIndex < self.messages.count {
                        // Provide detailed error information
                        var errorMessage = "❌ Generation failed:\n"
                        errorMessage += "\(error.localizedDescription)\n\n"

                        // Add framework-specific details
                        errorMessage += "Framework: \(self.selectedFramework.displayName)\n"
                        if let model = self.selectedModel {
                            errorMessage += "Model: \(model.name)\n"
                        }

                        // Add error type details
                        if let llmError = error as? LLMError {
                            errorMessage += "Error type: \(llmError)\n"
                        }

                        errorMessage += "\nPlease check:\n"
                        errorMessage += "• Model is properly downloaded\n"
                        errorMessage += "• Device supports \(self.selectedFramework.displayName)\n"
                        errorMessage += "• Sufficient memory available"

                        self.messages[messageIndex].content = errorMessage
                        self.messages[messageIndex].isError = true
                    }
                }
                logger.log("Generation failed with error: \(error)", level: .error, category: "Chat")
                logger.log("Error details - Framework: \(selectedFramework.displayName), Model: \(selectedModel?.name ?? "none")", level: .error, category: "Chat")
            }

            // End monitoring
            performanceMonitor.endGeneration()

            await MainActor.run {
                self.isGenerating = false
                self.currentTokensPerSecond = nil
            }
        }
    }

    func clearChat() {
        generationTask?.cancel()
        messages.removeAll()
        createNewConversation()
        addWelcomeMessage()
        currentInput = ""
        isGenerating = false
        error = nil
    }

    func stopGeneration() {
        generationTask?.cancel()
        isGenerating = false
    }

    func regenerateLastMessage() async {
        guard messages.count >= 2 else { return }

        // Remove last assistant message
        if messages.last?.role == .assistant {
            messages.removeLast()
        }

        // Get last user message
        if let lastUserMessage = messages.last(where: { $0.role == .user }) {
            currentInput = lastUserMessage.content
            await sendMessage()
        }
    }

    func switchFramework(_ framework: LLMFramework) async {
        selectedFramework = framework

        unifiedService.selectService(named: framework.displayName)
        logger.log("Switched to \(framework.displayName)", level: .info, category: "Chat")
    }

    // MARK: - Private Methods

    private func createNewConversation() {
        currentConversation = conversationStore.createConversation(title: "New Chat")
        currentConversation?.framework = selectedFramework
        currentConversation?.modelInfo = selectedModel
    }

    private func setupSubscriptions() {
        // Monitor performance metrics
        performanceMonitor.$currentMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                if metrics.currentTokensPerSecond > 0 {
                    self?.currentTokensPerSecond = metrics.currentTokensPerSecond
                }
            }
            .store(in: &cancellables)

        // Listen for model download completion to refresh available services
        NotificationCenter.default.publisher(for: Notification.Name("ModelDownloadCompleted"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Force the unified service to refresh its available services
                self?.unifiedService.setupServices()
            }
            .store(in: &cancellables)
    }

    private func addWelcomeMessage() {
        let welcomeMessage = ChatMessage(
            role: .assistant,
            content: "Welcome to RunAnywhere AI! Please select a framework and model to start chatting.",
            timestamp: Date()
        )
        messages.append(welcomeMessage)
    }

    private func unloadCurrentModel() async {
        // Unload the current model to free memory
        if let service = unifiedService.currentService {
            logger.info("Unloading current model to free memory")
            service.cleanup()

            await MainActor.run {
                // Update UI to show model is no longer loaded
                isLoadingModel = false
                modelLoadingProgress = ""
            }
        }
    }

    private func loadSelectedModel(_ model: RunAnywhereAI.ModelInfo) async throws {
        await MainActor.run {
            isLoadingModel = true
            modelLoadingProgress = "Loading \(model.name)..."
            error = nil
        }

        do {
            await MainActor.run {
                modelLoadingProgress = "Initializing \(selectedFramework.displayName) service..."
            }

            // Use the unified service's loadModel method which handles service creation
            NSLog("🚀 ChatViewModel calling unifiedService.loadModel with model: %@, framework: %@", model.name, selectedFramework.displayName)
            try await unifiedService.loadModel(model, framework: selectedFramework)

            logger.info("Successfully loaded model: \(model.name)")

            await MainActor.run {
                isLoadingModel = false
                modelLoadingProgress = ""
                // Update welcome message
                if !messages.isEmpty && messages[0].role == .assistant {
                    messages[0].content = "Model loaded successfully! I'm ready to chat using \(model.name) with \(selectedFramework.displayName)."
                }
            }
        } catch {
            logger.error("Failed to load model \(model.name): \(error)")
            await MainActor.run {
                self.error = error
                isLoadingModel = false
                modelLoadingProgress = ""
            }
            throw error
        }
    }

    private func streamGeneration(prompt: String, messageIndex: Int) async throws {
        let options = GenerationOptions(
            maxTokens: settings.maxTokens,
            temperature: Float(settings.temperature),
            topP: Float(settings.topP ?? 0.95),
            topK: settings.topK ?? 40,
            repetitionPenalty: 1.1,
            stopSequences: []
        )

        print("🚀 Starting stream generation with options:")
        print("   - Max tokens: \(options.maxTokens)")
        print("   - Temperature: \(options.temperature)")

        var generatedTokens: [String] = []
        let startTime = CFAbsoluteTimeGetCurrent()

        try await unifiedService.streamGenerate(
            prompt: prompt,
            options: options
        ) { [weak self] token in
            guard let self = self else { return }

            print("🔤 Received token: '\(token)'")

            // Record token
            self.performanceMonitor.recordToken(token)
            generatedTokens.append(token)

            Task { @MainActor in
                if messageIndex < self.messages.count {
                    self.messages[messageIndex].content += token
                    print("📝 Updated message content, length: \(self.messages[messageIndex].content.count)")
                }

                // Update metrics
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                if elapsed > 0 {
                    self.currentTokensPerSecond = Double(generatedTokens.count) / elapsed
                }
            }
        }

        // Final metrics
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime

        messages[messageIndex].generationMetrics = EnhancedGenerationMetrics(
            tokenCount: generatedTokens.count,
            totalTime: totalTime,
            tokensPerSecond: Double(generatedTokens.count) / totalTime,
            timeToFirstToken: performanceMonitor.currentMetrics.timeToFirstToken
        )

        // Save the completed streamed message to conversation store
        if let conversation = currentConversation, messageIndex < messages.count {
            conversationStore.addMessage(messages[messageIndex], to: conversation)

            // Update conversation with current model and framework
            var updated = conversation
            updated.framework = selectedFramework
            updated.modelInfo = selectedModel
            conversationStore.updateConversation(updated)
        }
    }

    private func generateResponse(prompt: String) async throws -> (text: String, metrics: EnhancedGenerationMetrics) {
        let options = GenerationOptions(
            maxTokens: settings.maxTokens,
            temperature: Float(settings.temperature),
            topP: Float(settings.topP ?? 0.95),
            topK: settings.topK ?? 40,
            repetitionPenalty: 1.1,
            stopSequences: []
        )

        let startTime = CFAbsoluteTimeGetCurrent()

        let response = try await unifiedService.generate(
            prompt: prompt,
            options: options
        )

        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime

        // Estimate token count (rough approximation)
        let estimatedTokens = response.split(separator: " ").count

        let metrics = EnhancedGenerationMetrics(
            tokenCount: estimatedTokens,
            totalTime: totalTime,
            tokensPerSecond: Double(estimatedTokens) / totalTime,
            timeToFirstToken: 0
        )

        return (response, metrics)
    }
}

// MARK: - Supporting Types

struct EnhancedGenerationMetrics {
    let tokenCount: Int
    let totalTime: TimeInterval
    let tokensPerSecond: Double
    let timeToFirstToken: TimeInterval
}

struct ChatSettings {
    var maxTokens: Int = 150
    var temperature: Double = 0.7
    var topP: Double? = 0.9
    var topK: Int? = 40
    var streamResponses: Bool = true
    var showMetrics: Bool = true
    var enableProfiling: Bool = false
}
