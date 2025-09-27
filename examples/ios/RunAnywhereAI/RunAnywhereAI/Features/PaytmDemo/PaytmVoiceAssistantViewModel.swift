//
//  PaytmVoiceAssistantViewModel.swift
//  RunAnywhereAI
//
//  Custom ViewModel for Paytm Voice Payment with amount extraction
//

import Foundation
import RunAnywhereSDK
import AVFoundation
import Combine
import os

@MainActor
class PaytmVoiceAssistantViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "PaytmVoiceViewModel")
    private let sdk = RunAnywhereSDK.shared
    private let audioCapture = AudioCapture()

    // MARK: - Published Properties`
    @Published var currentTranscript: String = ""
    @Published var assistantResponse: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var isInitialized = false
    @Published var currentBalance: Double = 24567.0  // Starting balance
    @Published var transactionHistory: [Transaction] = []

    // Session state
    enum SessionState: Equatable {
        case disconnected
        case connecting
        case connected
        case listening
        case processing
        case speaking
        case error(String)

        static func == (lhs: SessionState, rhs: SessionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.listening, .listening),
                 (.processing, .processing),
                 (.speaking, .speaking):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    @Published var sessionState: SessionState = .disconnected
    @Published var isSpeechDetected: Bool = false
    @Published var isListening: Bool = false

    // Transaction model
    struct Transaction: Identifiable {
        let id = UUID()
        let amount: Double
        let recipient: String
        let timestamp: Date
        let type: TransactionType

        enum TransactionType {
            case sent
            case received
        }
    }

    // MARK: - Pipeline State
    private var voicePipeline: VoicePipelineManager?
    private var pipelineTask: Task<Void, Never>?
    private let whisperModelName: String = "whisper-base"

    // MARK: - System Prompt for Payment Processing
    private let systemPrompt = """
    You are a Paytm voice payment assistant. Your primary function is to help users send money through voice commands.

    IMPORTANT INSTRUCTIONS:
    1. When a user says they want to send money (in any language including Hindi), extract:
       - The amount (numbers like "500", "five hundred", "पांच सौ" should be converted to numeric values)
       - The recipient name if mentioned

    2. For payment commands, ALWAYS respond in this JSON format:
    {
        "action": "payment",
        "amount": <numeric_amount>,
        "recipient": "<recipient_name>",
        "message": "<confirmation_message>"
    }

    3. For non-payment queries, respond in this format:
    {
        "action": "query",
        "message": "<your_response>"
    }

    4. Keep responses conversational and brief. Examples:
       - For successful payment: "Done! ₹500 sent to Vijay successfully."
       - For balance check: "Your current balance is ₹24,567"

    5. Support multiple languages but always extract amounts correctly:
       - "Send 500 to Raj" → amount: 500
       - "पांच सौ रुपये राज को भेजो" → amount: 500
       - "Transfer thousand rupees to mom" → amount: 1000

    Remember: Be friendly, concise, and always confirm the transaction details.
    """

    // MARK: - Initialization
    func initialize() async {
        logger.info("Initializing Paytm Voice Assistant...")

        // Request microphone permission
        let hasPermission = await AudioCapture.requestMicrophonePermission()
        guard hasPermission else {
            errorMessage = "Please enable microphone access in Settings"
            return
        }

        isInitialized = true
    }

    // MARK: - Voice Pipeline Control
    func startConversation() async {
        logger.info("Starting voice conversation...")
        sessionState = .connecting

        // Clear previous messages
        currentTranscript = ""
        assistantResponse = ""
        errorMessage = nil

        // Get current loaded model for offline operation
        var llmModelId = "default"
        if let currentModel = ModelManager.shared.getCurrentModel() {
            llmModelId = currentModel.id
            logger.info("Using loaded model: \(llmModelId)")
        }

        // Create pipeline configuration with custom system prompt
        // Using local models only - no cloud dependency
        let config = ModularPipelineConfig(
            components: [.vad, .stt, .llm, .tts],
            vad: VADConfig(),
            stt: VoiceSTTConfig(modelId: whisperModelName),
            llm: VoiceLLMConfig(modelId: llmModelId, systemPrompt: systemPrompt),
            tts: VoiceTTSConfig(voice: "system")  // System voice works offline
        )

        // Create the pipeline
        voicePipeline = sdk.createVoicePipeline(config: config)

        guard let pipeline = voicePipeline else {
            sessionState = .error("Failed to create voice pipeline")
            return
        }

        // Initialize components first
        do {
            for try await event in pipeline.initializeComponents() {
                await handleInitializationEvent(event)
            }
        } catch {
            sessionState = .error("Initialization failed: \(error.localizedDescription)")
            errorMessage = "Component initialization failed: \(error.localizedDescription)"
            logger.error("Component initialization failed: \(error)")
            return
        }

        // Start audio capture after initialization is complete
        let audioStream = audioCapture.startContinuousCapture()

        sessionState = .listening
        isListening = true
        errorMessage = nil

        // Process audio through pipeline
        pipelineTask = Task {
            do {
                for try await event in pipeline.process(audioStream: audioStream) {
                    await handlePipelineEvent(event)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Pipeline error: \(error.localizedDescription)"
                    self.sessionState = .error(error.localizedDescription)
                    self.isListening = false
                }
            }
        }
    }

    func stopConversation() async {
        logger.info("Stopping voice conversation...")

        isListening = false
        isProcessing = false
        isSpeechDetected = false

        // Cancel pipeline task
        pipelineTask?.cancel()
        pipelineTask = nil

        // Stop audio capture
        audioCapture.stopContinuousCapture()

        // Clean up pipeline
        voicePipeline = nil

        sessionState = .disconnected
    }

    // MARK: - Event Handlers
    private func handleInitializationEvent(_ event: ModularPipelineEvent) async {
        switch event {
        case .componentInitialized(let componentName):
            logger.info("Component initialized: \(componentName)")
        case .allComponentsInitialized:
            logger.info("All components initialized successfully")
        case .componentInitializationFailed(let componentName, let error):
            errorMessage = "Failed to initialize \(componentName): \(error.localizedDescription)"
            sessionState = .error(error.localizedDescription)
        default:
            break
        }
    }

    private func handlePipelineEvent(_ event: ModularPipelineEvent) async {
        switch event {
        case .vadSpeechStart:
            sessionState = .listening
            isSpeechDetected = true

        case .vadSpeechEnd:
            isSpeechDetected = false

        case .sttFinalTranscript(let text):
            logger.info("Transcription: \(text)")
            currentTranscript = text
            sessionState = .processing
            isListening = false

        case .llmFinalResponse(let response):
            logger.info("LLM Response: \(response)")
            await processLLMResponse(response)

        case .ttsStarted:
            sessionState = .speaking

        case .ttsCompleted:
            logger.info("TTS complete, restarting listening...")
            sessionState = .listening
            isListening = true
            // Clear transcript for next interaction
            currentTranscript = ""

        case .pipelineError(let error):
            logger.error("Pipeline error: \(error)")
            errorMessage = error.localizedDescription
            sessionState = .error(error.localizedDescription)

        default:
            break
        }
    }

    // MARK: - Payment Processing
    private func processLLMResponse(_ response: String) async {
        // Try to parse JSON response
        if let data = response.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let action = json["action"] as? String {
                        switch action {
                        case "payment":
                            await handlePayment(json: json)
                        case "query":
                            if let message = json["message"] as? String {
                                assistantResponse = message
                            }
                        default:
                            assistantResponse = response
                        }
                        return
                    }
                }
            } catch {
                // If JSON parsing fails, try to extract amount from plain text
                logger.info("JSON parsing failed, attempting plain text extraction")
            }
        }

        // Fallback: try to extract amount from plain response
        assistantResponse = response
        await extractAndProcessPayment(from: response)
    }

    private func handlePayment(json: [String: Any]) async {
        guard let amount = json["amount"] as? Double,
              let recipient = json["recipient"] as? String,
              let message = json["message"] as? String else {
            assistantResponse = "I couldn't process that payment. Please try again."
            return
        }

        // Check if sufficient balance
        if amount > self.currentBalance {
            assistantResponse = "Insufficient balance. You have ₹\(Int(self.currentBalance)) available."
            return
        }

        // Process the payment
        self.currentBalance -= amount

        // Add to transaction history
        let transaction = Transaction(
            amount: amount,
            recipient: recipient,
            timestamp: Date(),
            type: .sent
        )
        self.transactionHistory.insert(transaction, at: 0)

        // Set the response
        assistantResponse = message.isEmpty ?
            "Done! ₹\(Int(amount)) sent to \(recipient) successfully." : message

        logger.info("Payment processed: ₹\(amount) to \(recipient). New balance: ₹\(self.currentBalance)")
    }

    private func extractAndProcessPayment(from text: String) async {
        // Simple amount extraction for fallback
        let patterns = [
            #"(\d+(?:\.\d+)?)"#,  // Numbers
            #"(one|two|three|four|five|six|seven|eight|nine|ten|hundred|thousand)"#  // Words
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                if let match = matches.first {
                    let matchString = (text as NSString).substring(with: match.range)
                    if let amount = parseAmount(from: matchString) {
                        // Extract recipient (simple heuristic: word after "to")
                        let recipient = extractRecipient(from: text) ?? "User"

                        if amount > currentBalance {
                            assistantResponse = "Insufficient balance. You have ₹\(Int(currentBalance)) available."
                        } else {
                            currentBalance -= amount
                            let transaction = Transaction(
                                amount: amount,
                                recipient: recipient,
                                timestamp: Date(),
                                type: .sent
                            )
                            transactionHistory.insert(transaction, at: 0)
                            assistantResponse = "Done! ₹\(Int(amount)) sent to \(recipient) successfully."
                        }
                        return
                    }
                }
            }
        }
    }

    private func parseAmount(from string: String) -> Double? {
        // Try to parse as number
        if let amount = Double(string) {
            return amount
        }

        // Parse word numbers
        let wordToNumber: [String: Double] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "hundred": 100, "thousand": 1000
        ]

        if let amount = wordToNumber[string.lowercased()] {
            return amount
        }

        return nil
    }

    private func extractRecipient(from text: String) -> String? {
        // Simple extraction: find word after "to"
        let words = text.split(separator: " ")
        if let toIndex = words.firstIndex(of: "to"),
           toIndex < words.count - 1 {
            return String(words[toIndex + 1])
        }
        return nil
    }
}
