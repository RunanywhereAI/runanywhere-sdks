import Foundation
import RunAnywhereSDK
import AVFoundation
import Combine
import os
#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
class TranscriptionViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "TranscriptionViewModel")
    private let sdk = RunAnywhereSDK.shared
    private let audioCapture = AudioCapture()

    // MARK: - Published Properties
    @Published var transcriptionText: String = ""
    @Published var isTranscribing: Bool = false
    @Published var errorMessage: String?
    @Published var isInitialized = false
    @Published var currentStatus = "Initializing..."
    @Published var whisperModel: String = "Whisper Base"
    @Published var partialTranscript: String = ""
    @Published var finalTranscripts: [TranscriptSegment] = []

    // MARK: - Transcription State
    private var voicePipeline: ModularVoicePipeline?
    private let whisperModelName: String = "whisper-base"
    private var audioStreamContinuation: AsyncStream<VoiceAudioChunk>.Continuation?
    private var pipelineTask: Task<Void, Never>?

    // MARK: - Transcript Segment Model
    struct TranscriptSegment: Identifiable {
        let id = UUID()
        let text: String
        let timestamp: Date
        let isFinal: Bool
    }

    // MARK: - Initialization

    func initialize() async {
        logger.info("Initializing TranscriptionViewModel...")

        // Request microphone permission
        logger.info("Requesting microphone permission...")
        let hasPermission = await AudioCapture.requestMicrophonePermission()
        logger.info("Microphone permission: \(hasPermission)")

        guard hasPermission else {
            currentStatus = "Microphone permission denied"
            errorMessage = "Please enable microphone access in Settings"
            logger.error("Microphone permission denied")
            return
        }

        // Set the Whisper model display name
        updateWhisperModelName()

        logger.info("Transcription service initialized")
        currentStatus = "Ready to transcribe"
        isInitialized = true
    }

    private func updateWhisperModelName() {
        switch whisperModelName {
        case "whisper-base":
            whisperModel = "Whisper Base"
        case "whisper-small":
            whisperModel = "Whisper Small"
        case "whisper-medium":
            whisperModel = "Whisper Medium"
        case "whisper-large":
            whisperModel = "Whisper Large"
        case "whisper-large-v3":
            whisperModel = "Whisper Large v3"
        default:
            whisperModel = whisperModelName.replacingOccurrences(of: "-", with: " ").capitalized
        }
        logger.info("Using Whisper model: \(self.whisperModel)")
    }

    // MARK: - Transcription Control

    /// Start real-time transcription
    func startTranscription() async {
        guard !isTranscribing else {
            logger.warning("Transcription already in progress")
            return
        }

        logger.info("Starting transcription with modular pipeline...")

        // Create a simple transcription-only pipeline config
        let config = ModularPipelineConfig.transcriptionWithVAD(
            sttModel: whisperModelName,
            vadThreshold: 0.02
        )

        // Create the pipeline
        voicePipeline = sdk.createVoicePipeline(config: config)
        voicePipeline?.delegate = self

        // Initialize components first (VAD and STT only for transcription)
        guard let pipeline = voicePipeline else {
            errorMessage = "Failed to create pipeline"
            currentStatus = "Error"
            logger.error("Failed to create transcription pipeline")
            return
        }

        // Initialize all components
        currentStatus = "Initializing components..."
        do {
            for try await event in pipeline.initializeComponents() {
                if case .componentInitialized(let name) = event {
                    logger.info("Initialized: \(name)")
                } else if case .componentInitializationFailed(let name, let error) = event {
                    logger.error("Failed to initialize \(name): \(error)")
                    throw error
                }
            }
        } catch {
            errorMessage = "Component initialization failed: \(error.localizedDescription)"
            currentStatus = "Error"
            logger.error("Component initialization failed: \(error)")
            return
        }

        // Start audio capture and process through pipeline
        let audioStream = audioCapture.startContinuousCapture()

        isTranscribing = true
        currentStatus = "Listening..."
        errorMessage = nil
        partialTranscript = ""

        // Process audio through pipeline
        pipelineTask = Task {
            do {
                for try await event in pipeline.process(audioStream: audioStream) {
                    await handlePipelineEvent(event)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Pipeline error: \(error.localizedDescription)"
                    self.currentStatus = "Error"
                    self.isTranscribing = false
                }
            }
        }

        logger.info("Transcription pipeline started successfully")
    }

    /// Stop transcription
    func stopTranscription() async {
        guard isTranscribing else {
            logger.warning("No transcription in progress")
            return
        }

        logger.info("Stopping transcription...")

        // Cancel pipeline task
        pipelineTask?.cancel()
        pipelineTask = nil

        // Stop audio capture
        audioCapture.stopContinuousCapture()

        voicePipeline = nil

        isTranscribing = false
        currentStatus = "Ready to transcribe"

        // Add final partial transcript if exists
        if !partialTranscript.isEmpty {
            finalTranscripts.append(TranscriptSegment(
                text: partialTranscript,
                timestamp: Date(),
                isFinal: true
            ))
            partialTranscript = ""
        }

        logger.info("Transcription stopped")
    }

    /// Clear all transcripts
    func clearTranscripts() {
        finalTranscripts.removeAll()
        partialTranscript = ""
        transcriptionText = ""
        logger.info("Transcripts cleared")
    }

    /// Export transcripts as text
    func exportTranscripts() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium

        var exportText = "Transcription Export\n"
        exportText += "Date: \(dateFormatter.string(from: Date()))\n"
        exportText += "Model: \(whisperModel)\n"
        exportText += "---\n\n"

        for segment in finalTranscripts {
            exportText += "[\(dateFormatter.string(from: segment.timestamp))]\n"
            exportText += "\(segment.text)\n\n"
        }

        if !partialTranscript.isEmpty {
            exportText += "[Current]\n"
            exportText += "\(partialTranscript)\n"
        }

        return exportText
    }

    /// Copy all transcripts to clipboard
    func copyToClipboard() {
        let fullText = finalTranscripts.map { $0.text }.joined(separator: " ")
        let textToCopy = fullText.isEmpty ? partialTranscript : fullText

        #if os(iOS) || targetEnvironment(macCatalyst)
        UIPasteboard.general.string = textToCopy
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToCopy, forType: .string)
        #endif

        logger.info("Copied \(textToCopy.count) characters to clipboard")
    }

    // MARK: - Pipeline Event Handling

    private func handlePipelineEvent(_ event: ModularPipelineEvent) async {
        await MainActor.run {
            switch event {
            case .vadSpeechStart:
                logger.info("Speech detected")
                currentStatus = "Listening..."

            case .vadSpeechEnd:
                logger.info("Speech ended")

            case .sttPartialTranscript(let text):
                partialTranscript = text
                logger.info("Partial transcript: '\(text)'")

            case .sttFinalTranscript(let text):
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finalTranscripts.append(TranscriptSegment(
                        text: text,
                        timestamp: Date(),
                        isFinal: true
                    ))
                    partialTranscript = ""
                    transcriptionText = finalTranscripts.map { $0.text }.joined(separator: " ")
                }
                logger.info("Final transcript: '\(text)'")

            case .pipelineError(let error):
                errorMessage = error.localizedDescription
                currentStatus = "Error"
                logger.error("Pipeline error: \(error)")

            default:
                // Ignore other events not relevant to transcription
                break
            }
        }
    }
}

// MARK: - ModularVoicePipelineDelegate

extension TranscriptionViewModel: @preconcurrency ModularVoicePipelineDelegate {
    nonisolated func pipeline(_ pipeline: ModularVoicePipeline, didReceiveEvent event: ModularPipelineEvent) {
        Task { @MainActor in
            await handlePipelineEvent(event)
        }
    }

    nonisolated func pipeline(_ pipeline: ModularVoicePipeline, didEncounterError error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            isTranscribing = false
            currentStatus = "Error"
        }
        logger.error("Pipeline error: \(error)")
    }
}
