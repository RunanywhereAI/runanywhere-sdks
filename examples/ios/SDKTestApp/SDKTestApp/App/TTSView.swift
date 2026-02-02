//
//  TTSView.swift
//  SDKTestApp
//
//  TTS: list models from registry, download, load, then speak.
//

import SwiftUI
import RunAnywhere

struct TTSView: View {
    @State private var ttsModels: [ModelInfo] = []
    @State private var selectedModel: ModelInfo?
    @State private var isVoiceLoaded = false
    @State private var loadedVoiceName: String?
    @State private var isLoadingModels = false
    @State private var isLoadingVoice = false
    @State private var loadError: String?

    @State private var downloadingModelId: String?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?

    @State private var speakText = "Hello! This is a text to speech test."
    @State private var isSpeaking = false
    @State private var speakError: String?

    private var downloadedModelIds: Set<String> {
        Set(ttsModels.filter { model in
            RunAnywhere.isModelDownloaded(model.id, framework: model.framework)
        }.map(\.id))
    }

    var body: some View {
        List {
            Section("TTS Models") {
                if isLoadingModels {
                    HStack { ProgressView(); Text("Loading models…") }
                } else if ttsModels.isEmpty {
                    Text("No TTS models registered. Restart the app after SDK init.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ttsModels, id: \.id) { model in
                        TTSModelRow(
                            model: model,
                            isSelected: selectedModel?.id == model.id,
                            isDownloaded: downloadedModelIds.contains(model.id),
                            isLoaded: isVoiceLoaded && loadedVoiceName == model.name,
                            isDownloading: downloadingModelId == model.id,
                            downloadProgress: downloadingModelId == model.id ? downloadProgress : 0,
                            isLoading: isLoadingVoice && selectedModel?.id == model.id,
                            loadError: selectedModel?.id == model.id ? loadError : nil,
                            onSelect: {
                                selectedModel = model
                                loadError = nil
                                downloadError = nil
                            },
                            onDownload: { Task { await downloadModel(model) } },
                            onLoad: { Task { await loadVoice(model) } }
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

            Section("Speak") {
                if !isVoiceLoaded {
                    Text("Download a TTS model above, then tap Load. Then you can speak.")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Text to speak", text: $speakText, axis: .vertical)
                        .lineLimit(2...6)
                        .textFieldStyle(.roundedBorder)

                    Button(action: { Task { await speak() } }) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                            Text(isSpeaking ? "Speaking…" : "Speak")
                        }
                    }
                    .disabled(speakText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSpeaking)

                    if let err = speakError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Text to Speech")
        .task { await loadTTSModels() }
    }

    private func loadTTSModels() async {
        await MainActor.run { isLoadingModels = true }
        do {
            let all = try await RunAnywhere.availableModels()
            let tts = all.filter { $0.category == .speechSynthesis }
            await MainActor.run {
                ttsModels = tts.sorted { $0.name < $1.name }
                if selectedModel == nil, let first = ttsModels.first {
                    selectedModel = first
                }
                isLoadingModels = false
            }
        } catch {
            await MainActor.run {
                ttsModels = []
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

    private func loadVoice(_ model: ModelInfo) async {
        await MainActor.run {
            isLoadingVoice = true
            loadError = nil
        }
        do {
            try await RunAnywhere.loadTTSModel(model.id)
            await MainActor.run {
                isVoiceLoaded = true
                loadedVoiceName = model.name
                loadError = nil
                isLoadingVoice = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoadingVoice = false
            }
        }
    }

    private func speak() async {
        let text = speakText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isVoiceLoaded else { return }
        await MainActor.run {
            isSpeaking = true
            speakError = nil
        }
        do {
            _ = try await RunAnywhere.speak(text, options: TTSOptions())
            await MainActor.run {
                isSpeaking = false
                speakError = nil
            }
        } catch {
            await MainActor.run {
                isSpeaking = false
                speakError = error.localizedDescription
            }
        }
    }
}

// MARK: - TTS Model Row

private struct TTSModelRow: View {
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
        TTSView()
    }
}
