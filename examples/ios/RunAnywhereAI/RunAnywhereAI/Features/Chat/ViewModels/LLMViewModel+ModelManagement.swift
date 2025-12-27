//
//  LLMViewModel+ModelManagement.swift
//  RunAnywhereAI
//
//  Model loading and management functionality for LLMViewModel
//

import Foundation
import RunAnywhere
import os.log

extension LLMViewModel {
    // MARK: - Model Loading

    func loadModel(_ modelInfo: ModelInfo) async {
        do {
            try await RunAnywhere.loadModel(modelInfo.id)

            await MainActor.run {
                self.updateModelLoadedState(isLoaded: true)
                self.updateLoadedModelInfo(name: modelInfo.name, framework: modelInfo.framework)
                self.updateSystemMessageAfterModelLoad()
            }
        } catch {
            await MainActor.run {
                self.setError(error)
                self.updateModelLoadedState(isLoaded: false)
                self.clearLoadedModelInfo()
            }
        }
    }

    // MARK: - Model Status Checking

    func checkModelStatus() async {
        let modelListViewModel = ModelListViewModel.shared

        await MainActor.run {
            if let currentModel = modelListViewModel.currentModel {
                self.updateModelLoadedState(isLoaded: true)
                self.updateLoadedModelInfo(name: currentModel.name, framework: currentModel.framework)
                verifyModelLoaded(currentModel)
            } else {
                self.updateModelLoadedState(isLoaded: false)
                self.clearLoadedModelInfo()
            }

            self.updateSystemMessageAfterModelLoad()
        }
    }

    private func verifyModelLoaded(_ currentModel: ModelInfo) {
        Task {
            do {
                try await RunAnywhere.loadModel(currentModel.id)
                let supportsStreaming = await RunAnywhere.supportsLLMStreaming
                await MainActor.run {
                    self.updateStreamingSupport(supportsStreaming)
                }
            } catch {
                await MainActor.run {
                    self.updateModelLoadedState(isLoaded: false)
                    self.clearLoadedModelInfo()
                }
            }
        }
    }

    // MARK: - Conversation Management

    func loadConversation(_ conversation: Conversation) {
        setCurrentConversation(conversation)

        if conversation.messages.isEmpty {
            clearMessages()
            if isModelLoadedValue {
                addSystemMessage()
            }
        } else {
            setMessages(conversation.messages)
        }

        if let modelName = conversation.modelName {
            setLoadedModelName(modelName)
        }
    }

    // MARK: - Internal State Updates

    func updateStreamingSupport(_ supportsStreaming: Bool) {
        setModelSupportsStreaming(supportsStreaming)
    }

    func updateSystemMessageAfterModelLoad() {
        if messagesValue.first?.role == .system {
            removeFirstMessage()
        }
        if isModelLoadedValue {
            addSystemMessage()
        }
    }
}
