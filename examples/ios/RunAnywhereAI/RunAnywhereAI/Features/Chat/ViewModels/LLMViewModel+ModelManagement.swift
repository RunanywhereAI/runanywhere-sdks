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

    func loadModel(_ modelInfo: RAModelInfo) async {
        var request = RAModelLoadRequest()
        request.modelID = modelInfo.id
        request.category = .language
        let result = await RunAnywhere.loadModel(request)
        if result.success {
            await MainActor.run {
                self.updateModelLoadedState(isLoaded: true)
                self.updateLoadedModelInfo(name: modelInfo.name, framework: modelInfo.framework)
                self.setLoadedModelSupportsThinking(modelInfo.supportsThinking)
                self.updateSystemMessageAfterModelLoad()
            }
        } else {
            await MainActor.run {
                self.setError(SDKException(code: .unknown, message: result.errorMessage, category: .internal))
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
                self.setLoadedModelSupportsThinking(currentModel.supportsThinking)
                verifyModelLoaded(currentModel)
            } else {
                self.updateModelLoadedState(isLoaded: false)
                self.clearLoadedModelInfo()
            }

            self.updateSystemMessageAfterModelLoad()
        }
    }

    private func verifyModelLoaded(_ currentModel: RAModelInfo) {
        Task {
            var request = RAModelLoadRequest()
            request.modelID = currentModel.id
            request.category = .language
            let result = await RunAnywhere.loadModel(request)
            if result.success {
                // All LLM inference goes through the canonical generate/generateStream
                // entry points which negotiate streaming per-request.
                await MainActor.run {
                    self.updateStreamingSupport(true)
                }
            } else {
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
