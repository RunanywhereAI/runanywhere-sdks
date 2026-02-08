//
//  ChatView.swift
//  SDKTestApp
//
//  LLM chat: list LLMs from registry, download, load, then chat.
//

import SwiftUI
import RunAnywhere

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

struct ChatView: View {
    @State private var llmModels: [ModelInfo] = []
    @State private var selectedModel: ModelInfo?
    @State private var isModelLoaded = false
    @State private var loadedModelName: String?
    @State private var isLoadingModels = false
    @State private var isLoadingModel = false
    @State private var loadError: String?

    @State private var downloadingModelId: String?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var generationError: String?

    private var downloadedModelIds: Set<String> {
        Set(llmModels.filter { model in
            RunAnywhere.isModelDownloaded(model.id, framework: model.framework)
        }.map(\.id))
    }

    var body: some View {
        List {
            Section("LLM Models") {
                if isLoadingModels {
                    HStack { ProgressView(); Text("Loading models…") }
                } else if llmModels.isEmpty {
                    Text("No LLM models registered. Restart the app after SDK init.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(llmModels, id: \.id) { model in
                        LLMModelRow(
                            model: model,
                            isSelected: selectedModel?.id == model.id,
                            isDownloaded: downloadedModelIds.contains(model.id),
                            isLoaded: isModelLoaded && loadedModelName == model.name,
                            isDownloading: downloadingModelId == model.id,
                            downloadProgress: downloadingModelId == model.id ? downloadProgress : 0,
                            isLoading: isLoadingModel && selectedModel?.id == model.id,
                            loadError: selectedModel?.id == model.id ? loadError : nil,
                            onSelect: {
                                selectedModel = model
                                loadError = nil
                                downloadError = nil
                            },
                            onDownload: { Task { await downloadModel(model) } },
                            onLoad: { Task { await loadModel(model) } }
                        )
                    }
                }
            }
            if let err = downloadError {
                Section {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Chat") {
                if !isModelLoaded {
                    Text("Download an LLM model above, then tap Load. Then you can chat.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(messages) { msg in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: msg.role == "user" ? "person.circle.fill" : "cpu.fill")
                                .foregroundStyle(msg.role == "user" ? .blue : .green)
                            Text(msg.content)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }

                    if let err = generationError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        TextField("Message", text: $inputText, axis: .vertical)
                            .lineLimit(2...6)
                            .textFieldStyle(.roundedBorder)
                        Button("Send") {
                            Task { await sendMessage() }
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    }
                    if isGenerating {
                        HStack { ProgressView(); Text("Generating…") }
                    }
                }
            }
        }
        .navigationTitle("Chat")
        .task { await loadLLMModels() }
    }

    private func loadLLMModels() async {
        await MainActor.run { isLoadingModels = true }
        do {
            let all = try await RunAnywhere.availableModels()
            let llms = all.filter { $0.category == .language || $0.category == .multimodal }
            await MainActor.run {
                llmModels = llms.sorted { $0.name < $1.name }
                if selectedModel == nil, let first = llmModels.first {
                    selectedModel = first
                }
                isLoadingModels = false
            }
        } catch {
            await MainActor.run {
                llmModels = []
                isLoadingModels = false
            }
        }
    }

    private func downloadModel(_ model: ModelInfo) async {
        await MainActor.run {
            downloadingModelId = model.id
            downloadProgress = 0
            downloadError = nil
        }
        do {
            let stream = try await RunAnywhere.downloadModel(model.id)
            for await progress in stream {
                await MainActor.run {
                    downloadProgress = progress.overallProgress
                    if progress.stage == .completed {
                        downloadingModelId = nil
                        downloadError = nil
                    }
                }
            }
            await MainActor.run { downloadingModelId = nil }
        } catch {
            await MainActor.run {
                downloadingModelId = nil
                downloadError = error.localizedDescription
            }
        }
    }

    private func loadModel(_ model: ModelInfo) async {
        await MainActor.run {
            isLoadingModel = true
            loadError = nil
        }
        do {
            try await RunAnywhere.loadModel(model.id)
            await MainActor.run {
                isModelLoaded = true
                loadedModelName = model.name
                loadError = nil
                isLoadingModel = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoadingModel = false
            }
        }
    }

    private func sendMessage() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, isModelLoaded else { return }
        await MainActor.run {
            inputText = ""
            messages.append(ChatMessage(role: "user", content: prompt))
            messages.append(ChatMessage(role: "assistant", content: ""))
            isGenerating = true
            generationError = nil
        }
        let assistantIndex = messages.count - 1

        do {
            let options = LLMGenerationOptions(maxTokens: 256, temperature: 0.7)
            let result = try await RunAnywhere.generate(prompt, options: options)
            await MainActor.run {
                if assistantIndex < messages.count {
                    messages[assistantIndex] = ChatMessage(role: "assistant", content: result.text)
                }
                isGenerating = false
                generationError = nil
            }
        } catch {
            await MainActor.run {
                if assistantIndex < messages.count {
                    messages[assistantIndex] = ChatMessage(role: "assistant", content: "Error: \(error.localizedDescription)")
                }
                isGenerating = false
                generationError = error.localizedDescription
            }
        }
    }
}

// MARK: - LLM Model Row

private struct LLMModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let isLoaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let isLoading: Bool
    let loadError: String?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onLoad: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(model.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                if isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: downloadProgress)
                            .progressViewStyle(.linear)
                        Text("Downloading… \(Int(downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if !isDownloaded {
                    Button("Download", action: onDownload)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else if isLoaded {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Load", action: onLoad)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLoading)
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                if let err = loadError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ChatView()
    }
}
