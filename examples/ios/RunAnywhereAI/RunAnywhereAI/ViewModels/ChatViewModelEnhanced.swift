//
//  ChatViewModelEnhanced.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ChatViewModelEnhanced: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var selectedFramework: LLMFramework = .llamaCpp
    @Published var selectedModel: RunAnywhereAI.ModelInfo?
    @Published var currentTokensPerSecond: Double?
    @Published var settings = ChatSettings()
    @Published var currentInput = ""
    @Published var error: Error?
    
    // MARK: - Private Properties
    private let unifiedService = UnifiedLLMService.shared
    private let performanceMonitor = RealtimePerformanceMonitor.shared
    private let logger = Logger.shared
    private var cancellables = Set<AnyCancellable>()
    private var generationTask: Task<Void, Never>?
    
    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }
    
    // MARK: - Initialization
    init() {
        setupSubscriptions()
        addWelcomeMessage()
    }
    
    // MARK: - Public Methods
    
    func sendMessage() async {
        guard canSend else { return }
        
        let userMessage = ChatMessage(
            role: .user,
            content: currentInput,
            timestamp: Date()
        )
        messages.append(userMessage)
        
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
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1
        
        generationTask = Task {
            do {
                // Switch framework if needed
                unifiedService.selectService(named: selectedFramework.displayName)
                
                if settings.streamResponses {
                    // Stream generation
                    try await streamGeneration(prompt: prompt, messageIndex: messageIndex)
                } else {
                    // Non-streaming generation
                    let response = try await generateResponse(prompt: prompt)
                    messages[messageIndex].content = response.text
                    messages[messageIndex].generationMetrics = response.metrics
                }
                
            } catch {
                await MainActor.run {
                    self.error = error
                    if messageIndex < self.messages.count {
                        self.messages[messageIndex].content = "Error: \(error.localizedDescription)"
                        self.messages[messageIndex].isError = true
                    }
                }
                logger.log("Generation failed: \(error)", level: .error, category: "Chat")
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
    }
    
    private func addWelcomeMessage() {
        let welcomeMessage = ChatMessage(
            role: .assistant,
            content: "Welcome! I'm ready to chat using \(selectedFramework.displayName). You can switch frameworks anytime using the selector above.",
            timestamp: Date()
        )
        messages.append(welcomeMessage)
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
        
        var generatedTokens: [String] = []
        let startTime = CFAbsoluteTimeGetCurrent()
        
        try await unifiedService.streamGenerate(
            prompt: prompt,
            options: options
        ) { [weak self] token in
            guard let self = self else { return }
            
            // Record token
            self.performanceMonitor.recordToken(token)
            generatedTokens.append(token)
            
            Task { @MainActor in
                if messageIndex < self.messages.count {
                    self.messages[messageIndex].content += token
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