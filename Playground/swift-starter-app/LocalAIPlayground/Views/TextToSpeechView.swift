//
//  TextToSpeechView.swift
//  LocalAIPlayground
//
//  =============================================================================
//  TEXT TO SPEECH VIEW - ON-DEVICE VOICE SYNTHESIS
//  =============================================================================
//
//  This view demonstrates how to use the RunAnywhere SDK's Text-to-Speech
//  capabilities powered by Piper neural TTS, running entirely on-device.
//
//  KEY CONCEPTS DEMONSTRATED:
//
//  1. TTS VOICE LOADING
//     - Models must be registered, downloaded, and loaded via ModelService
//
//  2. SPEECH SYNTHESIS
//     - Converting text to natural-sounding speech
//     - Configuring voice parameters (rate, pitch, volume)
//
//  3. AUDIO PLAYBACK
//     - Playing synthesized audio
//
//  RUNANYWHERE SDK METHODS USED:
//  - RunAnywhere.synthesize() - Convert text to audio
//  - TTSOptions              - Configure synthesis parameters
//
//  =============================================================================

import SwiftUI
import RunAnywhere
import AVFoundation

// =============================================================================
// MARK: - Text to Speech View
// =============================================================================
/// A view for synthesizing and playing speech from text input.
// =============================================================================
struct TextToSpeechView: View {
    // -------------------------------------------------------------------------
    // MARK: - State Properties
    // -------------------------------------------------------------------------
    
    @EnvironmentObject var modelService: ModelService
    @StateObject private var audioService = AudioService.shared
    
    @State private var inputText = ""
    @State private var isSynthesizing = false
    @State private var synthesizedAudio: Data?
    @State private var errorMessage: String?
    
    @State private var rate: Double = 1.0
    @State private var pitch: Double = 1.0
    @State private var volume: Double = 1.0
    
    @State private var showSettings = false
    @State private var history: [SynthesisEntry] = []
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private let sampleTexts = [
        "Hello! I'm an AI assistant running entirely on your device.",
        "The quick brown fox jumps over the lazy dog.",
        "Privacy matters. That's why all processing happens locally.",
        "Welcome to the future of mobile AI.",
    ]
    
    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !modelService.isTTSLoaded {
                    modelLoaderView
                } else {
                    ttsInterface
                }
            }
            .navigationTitle("Text to Speech")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                ttsSettingsSheet
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Model Loader State
    // -------------------------------------------------------------------------
    
    private var modelLoaderState: ModelState {
        if modelService.isTTSLoaded {
            return .ready
        } else if modelService.isTTSLoading {
            return .loading
        } else if modelService.isTTSDownloading {
            return .downloading(progress: modelService.ttsDownloadProgress)
        } else {
            return .notLoaded
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Model Loader View
    // -------------------------------------------------------------------------
    
    private var modelLoaderView: some View {
        VStack(spacing: AISpacing.xl) {
            Spacer()
            
            ModelLoaderView(
                modelName: "Piper TTS (US English)",
                modelDescription: "Neural text-to-speech using Piper with the Lessac voice. Natural-sounding speech synthesis on-device.",
                modelSize: "~65MB",
                state: modelLoaderState,
                onLoad: {
                    Task { await modelService.downloadAndLoadTTS() }
                },
                onRetry: {
                    Task { await modelService.downloadAndLoadTTS() }
                }
            )
            .padding(.horizontal)
            
            InfoCard(
                icon: "speaker.wave.2",
                title: "Natural Voice Synthesis",
                description: "Piper uses VITS neural architecture to generate human-like speech with proper intonation and rhythm."
            )
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - TTS Interface
    // -------------------------------------------------------------------------
    
    private var ttsInterface: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AISpacing.lg) {
                    textInputSection
                    sampleTextsSection
                    
                    if synthesizedAudio != nil {
                        playbackSection
                    }
                    
                    if !history.isEmpty {
                        historySection
                    }
                }
                .padding()
            }
            
            synthesizeButton
        }
    }
    
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: AISpacing.sm) {
            Text("Enter Text")
                .font(.aiHeadingSmall)
            
            TextEditor(text: $inputText)
                .font(.aiBody)
                .frame(minHeight: 120)
                .padding(AISpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AIRadius.md)
                        .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AIRadius.md)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            
            HStack {
                Text("\(inputText.count) characters")
                    .font(.aiCaption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !inputText.isEmpty {
                    Button("Clear") { inputText = "" }
                        .font(.aiCaption)
                        .foregroundStyle(Color.aiPrimary)
                }
            }
        }
    }
    
    private var sampleTextsSection: some View {
        VStack(alignment: .leading, spacing: AISpacing.sm) {
            Text("Quick Samples")
                .font(.aiCaption)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AISpacing.sm) {
                    ForEach(sampleTexts, id: \.self) { sample in
                        Button { inputText = sample } label: {
                            Text(sample)
                                .font(.aiBodySmall)
                                .lineLimit(1)
                                .padding(.horizontal, AISpacing.md)
                                .padding(.vertical, AISpacing.sm)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var playbackSection: some View {
        VStack(spacing: AISpacing.md) {
            if audioService.state == .playing {
                WaveformVisualizer(
                    level: audioService.outputLevel,
                    isActive: true,
                    color: .aiAccent
                )
                .frame(height: 50)
            }
            
            HStack(spacing: AISpacing.lg) {
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(Color.aiAccent)
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: audioService.state == .playing ? "stop.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to play")
                        .font(.aiLabel)
                    
                    if let audio = synthesizedAudio {
                        Text("\(audio.count / 1000) KB audio")
                            .font(.aiCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AIRadius.lg)
                    .fill(Color.aiAccent.opacity(0.1))
            )
        }
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: AISpacing.sm) {
            HStack {
                Text("History")
                    .font(.aiHeadingSmall)
                
                Spacer()
                
                Button("Clear") { history.removeAll() }
                    .font(.aiCaption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(history) { entry in
                HistoryCard(entry: entry) {
                    if let audio = entry.audioData {
                        try? audioService.playAudio(audio)
                    }
                }
            }
        }
    }
    
    private var synthesizeButton: some View {
        VStack(spacing: AISpacing.sm) {
            HStack(spacing: AISpacing.md) {
                SettingBadge(icon: "speedometer", value: String(format: "%.1fx", rate))
                SettingBadge(icon: "waveform.path", value: String(format: "%.1f", pitch))
                SettingBadge(icon: "speaker.wave.2", value: String(format: "%.0f%%", volume * 100))
            }
            
            Button(action: synthesize) {
                HStack {
                    if isSynthesizing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    Text(isSynthesizing ? "Synthesizing..." : "Speak")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.aiPrimary)
            .disabled(inputText.isEmpty || isSynthesizing)
        }
        .padding()
        .background(Rectangle().fill(.ultraThinMaterial).ignoresSafeArea())
    }
    
    private var ttsSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Voice Settings") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.1fx", rate)).foregroundStyle(.secondary)
                        }
                        Slider(value: $rate, in: 0.5...2.0, step: 0.1).tint(Color.aiPrimary)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Pitch")
                            Spacer()
                            Text(String(format: "%.1f", pitch)).foregroundStyle(.secondary)
                        }
                        Slider(value: $pitch, in: 0.5...1.5, step: 0.1).tint(Color.aiPrimary)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Volume")
                            Spacer()
                            Text(String(format: "%.0f%%", volume * 100)).foregroundStyle(.secondary)
                        }
                        Slider(value: $volume, in: 0.1...1.0, step: 0.1).tint(Color.aiPrimary)
                    }
                }
                
                Section("Reset") {
                    Button("Reset to Defaults") {
                        rate = 1.0
                        pitch = 1.0
                        volume = 1.0
                    }
                }
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // =========================================================================
    // MARK: - Actions
    // =========================================================================
    
    /// Synthesizes speech from the input text.
    ///
    /// ## RunAnywhere SDK Usage
    /// RunAnywhere.synthesize() converts text to audio using Piper TTS.
    // -------------------------------------------------------------------------
    private func synthesize() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isSynthesizing = true
        
        Task {
            do {
                let options = TTSOptions(
                    rate: Float(rate),
                    pitch: Float(pitch),
                    volume: Float(volume)
                )
                
                print("🔊 Synthesizing: \"\(text.prefix(50))...\"")
                
                let startTime = Date()
                
                // ---------------------------------------------------------
                // Synthesize with RunAnywhere SDK
                // ---------------------------------------------------------
                let output = try await RunAnywhere.synthesize(text, options: options)
                
                let duration = Date().timeIntervalSince(startTime)
                
                synthesizedAudio = output.audioData
                
                let entry = SynthesisEntry(
                    text: text,
                    audioData: output.audioData,
                    duration: output.duration,
                    synthesisTime: duration
                )
                history.insert(entry, at: 0)
                
                if history.count > 10 {
                    history.removeLast()
                }
                
                print("✅ Synthesized \(output.audioData.count) bytes in \(String(format: "%.2f", duration))s")
                
                try audioService.playAudio(output.audioData)
                
            } catch {
                print("❌ Synthesis failed: \(error)")
                errorMessage = error.localizedDescription
            }
            
            isSynthesizing = false
        }
    }
    
    private func togglePlayback() {
        if audioService.state == .playing {
            audioService.stopPlayback()
        } else if let audio = synthesizedAudio {
            try? audioService.playAudio(audio)
        }
    }
}

// =============================================================================
// MARK: - Supporting Types
// =============================================================================

struct SynthesisEntry: Identifiable {
    let id = UUID()
    let text: String
    let audioData: Data?
    let duration: TimeInterval
    let synthesisTime: TimeInterval
    let timestamp = Date()
}

struct SettingBadge: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(value).font(.aiCaption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, AISpacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.1)))
    }
}

struct HistoryCard: View {
    let entry: SynthesisEntry
    let onPlay: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: AISpacing.md) {
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.aiAccent)
            }
            .disabled(entry.audioData == nil)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.aiBodySmall)
                    .lineLimit(2)
                
                HStack(spacing: AISpacing.sm) {
                    Text(String(format: "%.1fs", entry.duration))
                    Text("•")
                    Text(formattedTime)
                }
                .font(.aiCaption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(AISpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AIRadius.md)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
        )
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================
#Preview {
    TextToSpeechView()
        .environmentObject(ModelService())
}
