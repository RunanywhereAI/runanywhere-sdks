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
        do {
            try await RunAnywhere.models.load(id: modelInfo.id)
            await MainActor.run {
                self.updateModelLoadedState(isLoaded: true)
                self.updateLoadedModelInfo(name: modelInfo.name, framework: modelInfo.framework)
                self.setLoadedModelSupportsThinking(modelInfo.supportsThinking)
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
        #if os(iOS)
        guard !isUsingConnect else { return }
        #endif

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
            do {
                try await RunAnywhere.models.load(id: currentModel.id)
                // All LLM inference goes through the canonical generate/generateStream
                // entry points which negotiate streaming per-request.
                await MainActor.run {
                    self.updateStreamingSupport(true)
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
        // Re-selecting the already-open conversation is a no-op. Reloading its
        // stored messages here would wipe an in-flight streaming assistant slot
        // (persisted only at finalize), silently losing the response.
        guard conversation.id != currentConversation?.id else { return }

        // Switching to a DIFFERENT conversation: cancel + detach the in-flight
        // generation so its streaming tokens and finalization can't corrupt the
        // one being selected.
        cancelActiveGeneration()

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
