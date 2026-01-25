//
//  SpeechToTextView.swift
//  LocalAIPlayground
//
//  =============================================================================
//  SPEECH TO TEXT VIEW - ON-DEVICE TRANSCRIPTION
//  =============================================================================
//
//  This view demonstrates how to use the RunAnywhere SDK's Speech-to-Text
//  capabilities powered by Whisper, running entirely on-device.
//
//  KEY CONCEPTS DEMONSTRATED:
//
//  1. STT MODEL LOADING
//     - Models must be registered, downloaded, and loaded via ModelService
//
//  2. AUDIO CAPTURE
//     - Microphone permission handling
//     - Real-time audio recording
//     - Audio format conversion (16kHz mono PCM)
//
//  3. TRANSCRIPTION
//     - Converting audio to text with RunAnywhere.transcribe()
//
//  AUDIO REQUIREMENTS:
//  ┌────────────────┬──────────────────────────────────────┐
//  │ Parameter      │ Value                                │
//  ├────────────────┼──────────────────────────────────────┤
//  │ Sample Rate    │ 16000 Hz (required by Whisper)       │
//  │ Channels       │ 1 (mono)                             │
//  │ Format         │ 16-bit signed integer PCM            │
//  └────────────────┴──────────────────────────────────────┘
//
//  =============================================================================

import SwiftUI
import RunAnywhere
import AVFoundation

// =============================================================================
// MARK: - Speech to Text View
// =============================================================================
/// A view for recording and transcribing speech using on-device Whisper.
// =============================================================================
struct SpeechToTextView: View {
    // -------------------------------------------------------------------------
    // MARK: - State Properties
    // -------------------------------------------------------------------------
    
    /// Service managing AI model loading
    @EnvironmentObject var modelService: ModelService
    
    /// Service managing audio capture
    @StateObject private var audioService = AudioService.shared
    
    /// List of transcription results
    @State private var transcriptions: [TranscriptionResult] = []
    
    /// Whether we're currently transcribing
    @State private var isTranscribing = false
    
    /// Error message to display
    @State private var errorMessage: String?
    
    /// Show permission alert
    @State private var showPermissionAlert = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !modelService.isSTTLoaded {
                    // Model not loaded - show loader
                    modelLoaderView
                } else if !audioService.hasPermission {
                    // No microphone permission
                    permissionView
                } else {
                    // Ready to record
                    recordingInterface
                }
            }
            .navigationTitle("Speech to Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !transcriptions.isEmpty {
                        Button(action: clearTranscriptions) {
                            Image(systemName: "trash")
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
                Text("Please enable microphone access in Settings to use speech recognition.")
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
        if modelService.isSTTLoaded {
            return .ready
        } else if modelService.isSTTLoading {
            return .loading
        } else if modelService.isSTTDownloading {
            return .downloading(progress: modelService.sttDownloadProgress)
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
                modelName: "Whisper Tiny (English)",
                modelDescription: "Fast on-device speech recognition using OpenAI's Whisper architecture, optimized for mobile via Sherpa-ONNX.",
                modelSize: "~75MB",
                state: modelLoaderState,
                onLoad: {
                    Task {
                        await modelService.downloadAndLoadSTT()
                    }
                },
                onRetry: {
                    Task {
                        await modelService.downloadAndLoadSTT()
                    }
                }
            )
            .padding(.horizontal)
            
            // Info about STT
            InfoCard(
                icon: "waveform",
                title: "How it works",
                description: "Whisper converts your speech to text entirely on-device. No audio data leaves your phone."
            )
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Permission View
    // -------------------------------------------------------------------------
    
    private var permissionView: some View {
        VStack(spacing: AISpacing.xl) {
            Spacer()
            
            // Icon
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            // Title
            Text("Microphone Access Needed")
                .font(.aiHeading)
            
            // Description
            Text("To transcribe your speech, we need permission to access your microphone. Audio is processed entirely on-device.")
                .font(.aiBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AISpacing.xl)
            
            // Request button
            Button(action: requestPermission) {
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
    // MARK: - Recording Interface
    // -------------------------------------------------------------------------
    
    private var recordingInterface: some View {
        VStack(spacing: 0) {
            // Transcription history
            ScrollView {
                LazyVStack(spacing: AISpacing.md) {
                    if transcriptions.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(transcriptions) { result in
                            TranscriptionCard(result: result)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Recording controls
            recordingControls
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Empty State
    // -------------------------------------------------------------------------
    
    private var emptyStateView: some View {
        VStack(spacing: AISpacing.lg) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("Ready to Transcribe")
                .font(.aiHeading)
            
            Text("Tap and hold the record button to capture speech. Release to transcribe.")
                .font(.aiBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Tips
            VStack(alignment: .leading, spacing: AISpacing.sm) {
                TipRow(icon: "speaker.wave.2", text: "Speak clearly for best results")
                TipRow(icon: "hand.raised", text: "Minimize background noise")
                TipRow(icon: "clock", text: "Recordings up to 30 seconds work best")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AIRadius.md)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .padding(.top, AISpacing.xxl)
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Recording Controls
    // -------------------------------------------------------------------------
    
    private var recordingControls: some View {
        VStack(spacing: AISpacing.md) {
            // Recording indicator
            if audioService.state == .recording {
                RecordingIndicator(
                    isRecording: true,
                    duration: audioService.recordingDuration
                )
                
                // Audio visualizer
                WaveformVisualizer(
                    level: audioService.inputLevel,
                    isActive: true,
                    color: .aiPrimary
                )
                .frame(height: 40)
                .padding(.horizontal)
            }
            
            // Record button
            HStack(spacing: AISpacing.xl) {
                // Cancel button (when recording)
                if audioService.state == .recording {
                    Button(action: cancelRecording) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.secondary))
                    }
                }
                
                // Main record button
                RecordButton(
                    isRecording: audioService.state == .recording,
                    isProcessing: isTranscribing,
                    onTap: toggleRecording
                )
                
                // Done button (when recording)
                if audioService.state == .recording {
                    Button(action: stopAndTranscribe) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.aiSuccess))
                    }
                }
            }
            
            // Instructions
            Text(instructionText)
                .font(.aiCaption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
    }
    
    private var instructionText: String {
        switch audioService.state {
        case .recording:
            return "Tap ✓ to transcribe or ✕ to cancel"
        case .idle:
            if isTranscribing {
                return "Transcribing..."
            }
            return "Tap to start recording"
        default:
            return ""
        }
    }
    
    // =========================================================================
    // MARK: - Actions
    // =========================================================================
    
    private func requestPermission() {
        Task {
            let granted = await audioService.requestPermission()
            if !granted {
                showPermissionAlert = true
            }
        }
    }
    
    private func toggleRecording() {
        if audioService.state == .recording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        Task {
            do {
                try await audioService.startRecording()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func cancelRecording() {
        audioService.cancelRecording()
    }
    
    /// Stops recording and transcribes the captured audio.
    ///
    /// ## RunAnywhere SDK Usage
    /// RunAnywhere.transcribe() converts audio data to text using Whisper.
    // -------------------------------------------------------------------------
    private func stopAndTranscribe() {
        Task {
            isTranscribing = true
            
            do {
                let audioData = try await audioService.stopRecording()
                
                print("🎤 Captured \(audioData.count) bytes of audio")
                
                guard audioData.count > 3200 else {
                    throw TranscriptionError.audioTooShort
                }
                
                let startTime = Date()
                
                // ---------------------------------------------------------
                // Transcribe with RunAnywhere SDK
                // ---------------------------------------------------------
                let transcribedText = try await RunAnywhere.transcribe(audioData)
                
                let duration = Date().timeIntervalSince(startTime)
                
                let cleanedText = transcribedText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !cleanedText.isEmpty {
                    let result = TranscriptionResult(
                        text: cleanedText,
                        duration: audioService.recordingDuration,
                        processingTime: duration
                    )
                    transcriptions.insert(result, at: 0)
                    
                    print("✅ Transcription: \"\(cleanedText)\" in \(String(format: "%.2f", duration))s")
                } else {
                    throw TranscriptionError.noSpeechDetected
                }
                
            } catch {
                print("❌ Transcription failed: \(error)")
                errorMessage = error.localizedDescription
            }
            
            isTranscribing = false
        }
    }
    
    private func clearTranscriptions() {
        transcriptions.removeAll()
    }
}

// =============================================================================
// MARK: - Supporting Types
// =============================================================================

struct TranscriptionResult: Identifiable {
    let id = UUID()
    let text: String
    let duration: TimeInterval
    let processingTime: TimeInterval
    let timestamp = Date()
}

enum TranscriptionError: LocalizedError {
    case audioTooShort
    case noSpeechDetected
    case modelNotLoaded
    
    var errorDescription: String? {
        switch self {
        case .audioTooShort:
            return "Recording too short. Please speak for at least 1 second."
        case .noSpeechDetected:
            return "No speech detected. Please try again."
        case .modelNotLoaded:
            return "STT model not loaded. Please wait for it to load."
        }
    }
}

struct TranscriptionCard: View {
    let result: TranscriptionResult
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: AISpacing.sm) {
            Text(result.text)
                .font(.aiBody)
                .textSelection(.enabled)
            
            HStack(spacing: AISpacing.md) {
                Label(String(format: "%.1fs audio", result.duration), systemImage: "waveform")
                Label(String(format: "%.2fs to transcribe", result.processingTime), systemImage: "cpu")
                
                Spacer()
                
                Text(formattedTime)
            }
            .font(.aiCaption)
            .foregroundStyle(.secondary)
        }
        .padding(AISpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AIRadius.lg)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .contextMenu {
            Button(action: { UIPasteboard.general.string = result.text }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: result.timestamp)
    }
}

struct RecordButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let onTap: () -> Void
    
    @State private var pulseScale: CGFloat = 1
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isRecording {
                    Circle()
                        .stroke(Color.aiPrimary.opacity(0.3), lineWidth: 3)
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseScale)
                }
                
                Circle()
                    .stroke(isRecording ? Color.aiPrimary : Color.secondary.opacity(0.3), lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .fill(isRecording ? Color.aiPrimary : Color.aiPrimary.opacity(0.9))
                    .frame(width: 64, height: 64)
                
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isProcessing)
        .onChange(of: isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulseScale = 1.2
                }
            } else {
                pulseScale = 1
            }
        }
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: AISpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.aiSecondary)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: AISpacing.xs) {
                Text(title)
                    .font(.aiLabel)
                
                Text(description)
                    .font(.aiBodySmall)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AISpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AIRadius.md)
                .fill(Color.aiSecondary.opacity(0.1))
        )
    }
}

struct TipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: AISpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.aiSecondary)
                .frame(width: 20)
            
            Text(text)
                .font(.aiBodySmall)
                .foregroundStyle(.secondary)
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================
#Preview {
    SpeechToTextView()
        .environmentObject(ModelService())
}
