//
//  ChatViewModel.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var currentInput = ""
    @Published var error: Error?
    
    private let llmService: UnifiedLLMService
    private var generationTask: Task<Void, Never>?
    private let performanceMonitor = PerformanceMonitor()
    
    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }
    
    @MainActor
    init(llmService: UnifiedLLMService = .shared) {
        self.llmService = llmService
        addSystemMessage()
    }
    
    private func addSystemMessage() {
        let systemMessage = ChatMessage(
            role: .system,
            content: "Welcome! Select a model from the Models tab to start chatting."
        )
        messages.append(systemMessage)
    }
    
    func sendMessage() async {
        guard canSend else { return }
        
        let userMessage = ChatMessage(role: .user, content: currentInput)
        messages.append(userMessage)
        
        let prompt = currentInput
        currentInput = ""
        isGenerating = true
        error = nil
        
        // Create assistant message that we'll update with streaming tokens
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1
        
        performanceMonitor.startMeasurement()
        
        generationTask = Task {
            do {
                try await llmService.streamGenerate(
                    prompt: prompt,
                    options: .default
                ) { [weak self] token in
                    guard let self = self else { return }
                    self.performanceMonitor.recordToken()
                    Task { @MainActor in
                        if messageIndex < self.messages.count {
                            self.messages[messageIndex].content += token
                        }
                    }
                }
                
                let metrics = self.performanceMonitor.endMeasurement()
                print("Generation completed - \(metrics.tokenCount) tokens at \(String(format: "%.1f", metrics.tokensPerSecond)) tokens/sec")
            } catch {
                await MainActor.run {
                    self.error = error
                    if messageIndex < self.messages.count {
                        self.messages[messageIndex].content = "Error: \(error.localizedDescription)"
                    }
                }
            }
            
            await MainActor.run {
                self.isGenerating = false
            }
        }
    }
    
    func clearChat() {
        generationTask?.cancel()
        messages.removeAll()
        addSystemMessage()
        currentInput = ""
        isGenerating = false
        error = nil
    }
    
    func stopGeneration() {
        generationTask?.cancel()
        isGenerating = false
    }
}