//
//  VoicePipelineView.swift
//  LocalAIPlayground
//
//  =============================================================================
//  VOICE PIPELINE VIEW - FULL VOICE AGENT DEMO
//  =============================================================================
//
//  This view demonstrates the complete voice agent pipeline combining:
//  - STT (Speech-to-Text / Whisper)
//  - LLM (Language Model)
//  - TTS (Text-to-Speech / Piper)
//
//  THE VOICE AGENT FLOW:
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │                                                                      │
//  │   🎤 User speaks  →  📝 Whisper transcribes  →  🤖 LLM responds     │
//  │                                                                      │
//  │                              ↓                                       │
//  │                                                                      │
//  │   🔊 Piper speaks response  ←  📝 LLM generates text                │
//  │                                                                      │
//  └──────────────────────────────────────────────────────────────────────┘
//
//  =============================================================================

import SwiftUI
import RunAnywhere
import AVFoundation

// =============================================================================
// MARK: - Voice Pipeline State
// =============================================================================
enum PipelineState: Equatable {
    case idle
    case listening
    case transcribing
    case thinking
    case synthesizing
    case speaking
    case error(message: String)
    
    var description: String {
        switch self {
        case .idle: return "Tap to start"
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .thinking: return "Thinking..."
        case .synthesizing: return "Preparing response..."
        case .speaking: return "Speaking..."
        case .error(let message): return "Error: \(message)"
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .listening: return .aiPrimary
        case .transcribing: return .aiSecondary
        case .thinking: return .purple
        case .synthesizing, .speaking: return .aiAccent
        case .error: return .aiError
        }
    }
}

// =============================================================================
// MARK: - Conversation Turn
// =============================================================================
struct ConversationTurn: Identifiable {
    let id = UUID()
    let userText: String
    let assistantText: String
    let timestamp: Date
    var audioData: Data?
}

// =============================================================================
// MARK: - Voice Pipeline View
// =============================================================================
struct VoicePipelineView: View {
    @EnvironmentObject var modelService: ModelService
    @StateObject private var audioService = AudioService.shared
    
    @State private var pipelineState: PipelineState = .idle
    @State private var conversation: [ConversationTurn] = []
    @State private var currentTranscript = ""
    @State private var currentResponse = ""
    @State private var showPermissionAlert = false
    
    // VAD (Voice Activity Detection) state
    @State private var vadEnabled = true
    @State private var isSpeechDetected = false
    @State private var silenceStartTime: Date?
    @State private var vadTimer: Timer?
    
    // VAD thresholds
    private let speechThreshold: Float = 0.02      // Level to detect speech start
    private let silenceThreshold: Float = 0.01    // Level to detect silence
    private let silenceDuration: TimeInterval = 1.5 // Seconds of silence before auto-stop
    private let minRecordingDuration: TimeInterval = 0.5 // Minimum recording before VAD kicks in
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var allModelsReady: Bool {
        modelService.isLLMLoaded && modelService.isSTTLoaded && modelService.isTTSLoaded
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !allModelsReady {
                    modelLoadingView
                } else if !audioService.hasPermission {
                    permissionView
                } else {
                    pipelineInterface
                }
            }
            .navigationTitle("Voice Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        stopPipeline()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // VAD toggle
                        Button {
                            vadEnabled.toggle()
                        } label: {
                            Image(systemName: vadEnabled ? "waveform.badge.mic" : "waveform.badge.minus")
                                .foregroundStyle(vadEnabled ? Color.aiSuccess : .secondary)
                        }
                        .help(vadEnabled ? "Auto-detect speech (ON)" : "Auto-detect speech (OFF)")
                        
                        if !conversation.isEmpty {
                            Button { conversation.removeAll() } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Voice assistant requires microphone access.")
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Model Loading View
    // -------------------------------------------------------------------------
    
    private var modelLoadingView: some View {
        VStack(spacing: AISpacing.xl) {
            Spacer()
            
            VStack(spacing: AISpacing.md) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)
                
                Text("Voice Assistant")
                    .font(.aiDisplay)
                
                Text("The voice pipeline requires three AI models to be loaded.")
                    .font(.aiBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Model status list
            VStack(spacing: AISpacing.md) {
                Text("Required Models")
                    .font(.aiHeadingSmall)
                
                VStack(spacing: AISpacing.sm) {
                    PipelineModelRow(
                        name: "LLM - LFM2 350M",
                        isLoaded: modelService.isLLMLoaded,
                        isLoading: modelService.isLLMLoading || modelService.isLLMDownloading,
                        progress: modelService.llmDownloadProgress
                    )
                    
                    PipelineModelRow(
                        name: "STT - Whisper Tiny",
                        isLoaded: modelService.isSTTLoaded,
                        isLoading: modelService.isSTTLoading || modelService.isSTTDownloading,
                        progress: modelService.sttDownloadProgress
                    )
                    
                    PipelineModelRow(
                        name: "TTS - Piper Lessac",
                        isLoaded: modelService.isTTSLoaded,
                        isLoading: modelService.isTTSLoading || modelService.isTTSDownloading,
                        progress: modelService.ttsDownloadProgress
                    )
                }
                
                if !modelService.isAnyDownloading && !modelService.isAnyLoading {
                    Button {
                        Task { await modelService.downloadAndLoadAllModels() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Load All Models")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.aiPrimary)
                }
            }
            .padding()
            .aiCardStyle()
            .padding(.horizontal)
            
            Text("First-time download may take a few minutes.")
                .font(.aiCaption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Permission View
    // -------------------------------------------------------------------------
    
    private var permissionView: some View {
        VStack(spacing: AISpacing.xl) {
            Spacer()
            
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("Microphone Required")
                .font(.aiHeading)
            
            Text("The voice assistant needs microphone access to hear your voice.")
                .font(.aiBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AISpacing.xl)
            
            Button {
                Task {
                    let granted = await audioService.requestPermission()
                    if !granted { showPermissionAlert = true }
                }
            } label: {
                HStack {
                    Image(systemName: "mic.fill")
                    Text("Enable Microphone")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.aiPrimary)
            .padding(.horizontal, AISpacing.xl)
            
            Spacer()
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Pipeline Interface
    // -------------------------------------------------------------------------
    
    private var pipelineInterface: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AISpacing.lg) {
                        if conversation.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(conversation) { turn in
                                ConversationTurnView(turn: turn) {
                                    if let audio = turn.audioData {
                                        try? audioService.playAudio(audio)
                                    }
                                }
                                .id(turn.id)
                            }
                        }
                        
                        if pipelineState != .idle {
                            currentActivityView
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation.count) { _, _ in
                    if let lastTurn = conversation.last {
                        withAnimation { proxy.scrollTo(lastTurn.id, anchor: .bottom) }
                    }
                }
            }
            
            Divider()
            pipelineControls
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AISpacing.lg) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("Voice Assistant Ready")
                .font(.aiHeading)
            
            Text("Tap the microphone button and speak naturally. I'll listen, understand, and respond with my voice.")
                .font(.aiBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // VAD info
            HStack(spacing: AISpacing.sm) {
                Image(systemName: "waveform.badge.mic")
                    .foregroundStyle(Color.aiSuccess)
                Text("Auto-detect: \(vadEnabled ? "ON" : "OFF")")
                    .font(.aiCaption)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(vadEnabled ? "Will auto-stop when you pause" : "Tap ✓ to confirm")
                    .font(.aiCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AISpacing.md)
            .padding(.vertical, AISpacing.sm)
            .background(Capsule().fill(Color.aiSuccess.opacity(0.1)))
            
            VStack(alignment: .leading, spacing: AISpacing.sm) {
                PipelineStep(number: 1, title: "Speak", description: vadEnabled ? "Auto-detects when you start & stop" : "I listen to your voice")
                PipelineStep(number: 2, title: "Transcribe", description: "Whisper converts speech to text")
                PipelineStep(number: 3, title: "Think", description: "LLM generates a response")
                PipelineStep(number: 4, title: "Speak", description: "Piper reads the response aloud")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AIRadius.lg)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .padding(.top, AISpacing.xl)
    }
    
    private var currentActivityView: some View {
        VStack(spacing: AISpacing.md) {
            HStack(spacing: AISpacing.sm) {
                if pipelineState == .listening {
                    // Show VAD-aware audio visualization
                    VStack(spacing: 4) {
                        AudioLevelBars(
                            level: audioService.inputLevel,
                            activeColor: isSpeechDetected ? Color.aiSuccess : pipelineState.color
                        )
                        
                        // VAD status indicator
                        if vadEnabled {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isSpeechDetected ? Color.aiSuccess : Color.secondary)
                                    .frame(width: 6, height: 6)
                                Text(isSpeechDetected ? "Speech" : "Waiting")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    ProgressView().tint(pipelineState.color)
                }
                
                Text(pipelineState.description)
                    .font(.aiLabel)
                    .foregroundStyle(pipelineState.color)
            }
            
            if !currentTranscript.isEmpty && pipelineState != .listening {
                VStack(alignment: .leading, spacing: AISpacing.xs) {
                    Text("You said:")
                        .font(.aiCaption)
                        .foregroundStyle(.secondary)
                    Text(currentTranscript)
                        .font(.aiBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: AIRadius.md).fill(Color.aiPrimary.opacity(0.1)))
            }
            
            if !currentResponse.isEmpty {
                VStack(alignment: .leading, spacing: AISpacing.xs) {
                    Text("Response:")
                        .font(.aiCaption)
                        .foregroundStyle(.secondary)
                    Text(currentResponse)
                        .font(.aiBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: AIRadius.md).fill(Color.purple.opacity(0.1)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AIRadius.lg)
                .stroke(pipelineState.color.opacity(0.3), lineWidth: 2)
        )
    }
    
    private var pipelineControls: some View {
        VStack(spacing: AISpacing.md) {
            HStack(spacing: AISpacing.xl) {
                if pipelineState != .idle {
                    Button(action: stopPipeline) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.secondary))
                    }
                }
                
                VoicePipelineButton(
                    state: pipelineState,
                    audioLevel: audioService.inputLevel,
                    onTap: handleMainButtonTap
                )
                
                if pipelineState == .listening {
                    Button(action: confirmAndProcess) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.aiSuccess))
                    }
                }
            }
            
            Text(instructionText)
                .font(.aiCaption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Rectangle().fill(.ultraThinMaterial).ignoresSafeArea())
    }
    
    private var instructionText: String {
        switch pipelineState {
        case .idle: return "Tap the microphone to start"
        case .listening:
            if vadEnabled {
                if isSpeechDetected {
                    return silenceStartTime != nil ? "Silence detected... processing soon" : "Listening... will auto-stop when you pause"
                } else {
                    return "Start speaking..."
                }
            } else {
                return "Tap ✓ when done speaking, or ✕ to cancel"
            }
        case .transcribing: return "Converting your speech to text..."
        case .thinking: return "Generating a response..."
        case .synthesizing: return "Preparing to speak..."
        case .speaking: return "Tap to stop playback"
        case .error: return "Tap the microphone to try again"
        }
    }
    
    // =========================================================================
    // MARK: - Pipeline Actions
    // =========================================================================
    
    private func handleMainButtonTap() {
        switch pipelineState {
        case .idle, .error:
            startListening()
        case .listening:
            confirmAndProcess()
        case .speaking:
            audioService.stopPlayback()
            pipelineState = .idle
        default:
            break
        }
    }
    
    private func startListening() {
        currentTranscript = ""
        currentResponse = ""
        isSpeechDetected = false
        silenceStartTime = nil
        
        Task {
            do {
                pipelineState = .listening
                try await audioService.startRecording()
                
                // Start VAD monitoring if enabled
                if vadEnabled {
                    startVADMonitoring()
                }
            } catch {
                pipelineState = .error(message: error.localizedDescription)
            }
        }
    }
    
    // =========================================================================
    // MARK: - Voice Activity Detection (VAD)
    // =========================================================================
    
    /// Starts monitoring audio levels for automatic speech detection.
    private func startVADMonitoring() {
        // Check audio level every 100ms
        vadTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard pipelineState == .listening else {
                stopVADMonitoring()
                return
            }
            
            let level = audioService.inputLevel
            let recordingDuration = audioService.recordingDuration
            
            // Detect speech start
            if !isSpeechDetected && level > speechThreshold {
                isSpeechDetected = true
                silenceStartTime = nil
                print("🎤 VAD: Speech detected (level: \(String(format: "%.3f", level)))")
            }
            
            // Only check for silence after minimum recording and speech was detected
            if isSpeechDetected && recordingDuration > minRecordingDuration {
                if level < silenceThreshold {
                    // Speech ended, start silence timer
                    if silenceStartTime == nil {
                        silenceStartTime = Date()
                        print("🎤 VAD: Silence started")
                    } else if let startTime = silenceStartTime {
                        let silenceDurationSoFar = Date().timeIntervalSince(startTime)
                        
                        // Auto-stop after silence duration
                        if silenceDurationSoFar >= silenceDuration {
                            print("🎤 VAD: Auto-stopping after \(String(format: "%.1f", silenceDurationSoFar))s silence")
                            stopVADMonitoring()
                            
                            // Trigger processing on main thread
                            DispatchQueue.main.async {
                                confirmAndProcess()
                            }
                        }
                    }
                } else {
                    // Speech resumed, reset silence timer
                    if silenceStartTime != nil {
                        print("🎤 VAD: Speech resumed")
                    }
                    silenceStartTime = nil
                }
            }
        }
    }
    
    /// Stops VAD monitoring.
    private func stopVADMonitoring() {
        vadTimer?.invalidate()
        vadTimer = nil
    }
    
    /// Runs the full voice pipeline: STT → LLM → TTS
    private func confirmAndProcess() {
        Task {
            do {
                // Step 1: Stop recording & get audio
                pipelineState = .transcribing
                let audioData = try await audioService.stopRecording()
                
                guard audioData.count > 3200 else {
                    throw PipelineError.audioTooShort
                }
                
                // Step 2: Transcribe with Whisper
                let transcript = try await RunAnywhere.transcribe(audioData)
                let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard !cleanTranscript.isEmpty else {
                    throw PipelineError.noSpeechDetected
                }
                
                currentTranscript = cleanTranscript
                print("📝 Transcript: \"\(cleanTranscript)\"")
                
                // Step 3: Generate response with LLM
                pipelineState = .thinking
                
                let prompt = buildVoicePrompt(userMessage: cleanTranscript)
                let options = LLMGenerationOptions(maxTokens: 100, temperature: 0.7)
                
                let streamResult = try await RunAnywhere.generateStream(prompt, options: options)
                
                var fullResponse = ""
                for try await token in streamResult.stream {
                    fullResponse += token
                    currentResponse = fullResponse
                }
                
                let cleanResponse = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                currentResponse = cleanResponse
                print("🤖 Response: \"\(cleanResponse)\"")
                
                guard !cleanResponse.isEmpty else {
                    throw PipelineError.emptyResponse
                }
                
                // Step 4: Synthesize speech
                pipelineState = .synthesizing
                
                let ttsOptions = TTSOptions(rate: 1.0, pitch: 1.0, volume: 1.0)
                let speechOutput = try await RunAnywhere.synthesize(cleanResponse, options: ttsOptions)
                
                print("🔊 Synthesized \(speechOutput.audioData.count) bytes")
                
                // Store conversation turn
                let turn = ConversationTurn(
                    userText: cleanTranscript,
                    assistantText: cleanResponse,
                    timestamp: Date(),
                    audioData: speechOutput.audioData
                )
                conversation.append(turn)
                
                // Step 5: Play response
                pipelineState = .speaking
                try audioService.playAudio(speechOutput.audioData)
                
                try await Task.sleep(for: .seconds(speechOutput.duration + 0.5))
                
                pipelineState = .idle
                currentTranscript = ""
                currentResponse = ""
                
                print("✅ Pipeline complete")
                
            } catch {
                print("❌ Pipeline error: \(error)")
                pipelineState = .error(message: error.localizedDescription)
                
                try? await Task.sleep(for: .seconds(3))
                pipelineState = .idle
            }
        }
    }
    
    private func buildVoicePrompt(userMessage: String) -> String {
        var prompt = """
        You are a helpful voice assistant. Give SHORT, conversational responses suitable for spoken dialogue. \
        Keep responses under 2-3 sentences. Be friendly and natural.
        
        """
        
        for turn in conversation.suffix(4) {
            prompt += "User: \(turn.userText)\n"
            prompt += "Assistant: \(turn.assistantText)\n"
        }
        
        prompt += "User: \(userMessage)\nAssistant:"
        return prompt
    }
    
    private func stopPipeline() {
        stopVADMonitoring()
        audioService.cancelRecording()
        audioService.stopPlayback()
        pipelineState = .idle
        currentTranscript = ""
        currentResponse = ""
        isSpeechDetected = false
        silenceStartTime = nil
    }
}

// =============================================================================
// MARK: - Pipeline Errors
// =============================================================================
enum PipelineError: LocalizedError {
    case audioTooShort
    case noSpeechDetected
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .audioTooShort: return "Recording too short. Please speak for at least 1 second."
        case .noSpeechDetected: return "No speech detected. Please try again."
        case .emptyResponse: return "Could not generate a response. Please try again."
        }
    }
}

// =============================================================================
// MARK: - Supporting Views
// =============================================================================

struct PipelineModelRow: View {
    let name: String
    let isLoaded: Bool
    let isLoading: Bool
    let progress: Double
    
    var body: some View {
        HStack(spacing: AISpacing.sm) {
            Circle()
                .fill(isLoaded ? Color.aiSuccess : (isLoading ? Color.aiWarning : Color.secondary))
                .frame(width: 10, height: 10)
            
            Text(name)
                .font(.aiBodySmall)
            
            Spacer()
            
            if isLoading {
                if progress > 0 {
                    Text("\(Int(progress * 100))%").font(.aiMono)
                } else {
                    ProgressView().scaleEffect(0.6)
                }
            } else {
                Text(isLoaded ? "Ready" : "Not loaded")
                    .font(.aiCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PipelineStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: AISpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.purple)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.aiLabel)
                Text(description).font(.aiCaption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ConversationTurnView: View {
    let turn: ConversationTurn
    let onReplay: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: AISpacing.md) {
            // User message
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: AISpacing.xs) {
                    Text("You").font(.aiCaption).foregroundStyle(.secondary)
                    Text(turn.userText)
                        .font(.aiBody)
                        .padding(AISpacing.md)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.aiPrimary))
                        .foregroundStyle(.white)
                }
            }
            
            // Assistant response
            HStack {
                VStack(alignment: .leading, spacing: AISpacing.xs) {
                    HStack {
                        Text("Assistant").font(.aiCaption).foregroundStyle(.secondary)
                        Spacer()
                        if turn.audioData != nil {
                            Button(action: onReplay) {
                                Image(systemName: "play.circle.fill").foregroundStyle(.purple)
                            }
                        }
                    }
                    Text(turn.assistantText)
                        .font(.aiBody)
                        .padding(AISpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
                        )
                }
                Spacer()
            }
        }
    }
}

struct VoicePipelineButton: View {
    let state: PipelineState
    let audioLevel: Float
    let onTap: () -> Void
    
    @State private var pulseScale: CGFloat = 1
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if state == .listening {
                    Circle()
                        .stroke(state.color.opacity(0.3), lineWidth: 3)
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseScale)
                }
                
                Circle()
                    .stroke(state.color.opacity(0.5), lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .fill(state.color)
                    .frame(
                        width: 64 * (1 + CGFloat(audioLevel) * 0.2),
                        height: 64 * (1 + CGFloat(audioLevel) * 0.2)
                    )
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
                
                Group {
                    switch state {
                    case .idle, .error:
                        Image(systemName: "mic.fill")
                    case .listening:
                        Image(systemName: "waveform")
                    case .transcribing, .thinking, .synthesizing:
                        ProgressView().tint(.white)
                    case .speaking:
                        Image(systemName: "stop.fill")
                    }
                }
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
            }
        }
        .disabled(state == .transcribing || state == .thinking || state == .synthesizing)
        .onChange(of: state) { _, newState in
            if newState == .listening {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulseScale = 1.2
                }
            } else {
                pulseScale = 1
            }
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================
#Preview {
    VoicePipelineView()
        .environmentObject(ModelService())
}
