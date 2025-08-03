import Foundation
import RunAnywhereSDK
import LLM

public class LLMSwiftService: LLMService {
    private var llm: LLM?
    private var modelPath: String?
    private var _modelInfo: LoadedModelInfo?
    private var context: Context?
    private let hardwareConfig: HardwareConfiguration?

    public var isReady: Bool { llm != nil }
    public var modelInfo: LoadedModelInfo? { _modelInfo }

    init(hardwareConfig: HardwareConfiguration? = nil) {
        self.hardwareConfig = hardwareConfig
    }

    public func initialize(modelPath: String) async throws {
        self.modelPath = modelPath

        // Configure LLM with hardware settings
        let maxTokens = hardwareConfig?.maxMemoryUsage ?? 2048
        let template = determineTemplate(from: modelPath)

        // Initialize LLM instance
        do {
            self.llm = try await LLM(
                from: URL(fileURLWithPath: modelPath),
                template: template,
                maxTokens: Int(maxTokens)
            )

            // Configure generation parameters based on hardware
            if let llm = self.llm {
                await llm.updateConfiguration(Configuration(
                    topP: 0.95,
                    temperature: 0.7,
                    topK: 40,
                    repeatPenalty: 1.1
                ))
            }

            // Create model info
            _modelInfo = LoadedModelInfo(
                id: UUID().uuidString,
                name: URL(fileURLWithPath: modelPath).lastPathComponent,
                framework: .llamaCpp,
                format: determineFormat(from: modelPath),
                memoryUsage: try await getModelMemoryUsage(),
                contextLength: Int(maxTokens),
                configuration: hardwareConfig ?? HardwareConfiguration(
                    preferredAccelerator: .cpu,
                    maxMemoryUsage: 0,
                    powerEfficiencyMode: .balanced
                )
            )
        } catch {
            throw FrameworkError(
                framework: .llamaCpp,
                underlying: error,
                context: "Failed to initialize LLM.swift with model at \(modelPath)"
            )
        }
    }

    public func generate(prompt: String, options: GenerationOptions) async throws -> String {
        guard let llm = llm else {
            throw LLMServiceError.notInitialized
        }

        // Apply generation options
        await applyGenerationOptions(options, to: llm)

        // Include context if available
        let fullPrompt = buildPromptWithContext(prompt)

        // Generate response
        do {
            let response = try await llm.respond(to: fullPrompt)

            // Apply stop sequences if specified
            var finalResponse = response
            if let stopSequences = options.stopSequences {
                for sequence in stopSequences {
                    if let range = finalResponse.range(of: sequence) {
                        finalResponse = String(finalResponse[..<range.lowerBound])
                        break
                    }
                }
            }

            // Limit to max tokens if specified
            if let maxTokens = options.maxTokens {
                let tokens = finalResponse.split(separator: " ")
                if tokens.count > maxTokens {
                    finalResponse = tokens.prefix(maxTokens).joined(separator: " ")
                }
            }

            return finalResponse
        } catch {
            throw FrameworkError(
                framework: .llamaCpp,
                underlying: error,
                context: "Generation failed for prompt: \(prompt)"
            )
        }
    }

    public func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let llm = llm else {
            throw LLMServiceError.notInitialized
        }

        // Apply generation options
        await applyGenerationOptions(options, to: llm)

        // Include context
        let fullPrompt = buildPromptWithContext(prompt)

        // Create streaming callback
        var tokenCount = 0
        let maxTokens = options.maxTokens ?? Int.max

        // Generate with streaming
        do {
            for try await token in llm.stream(fullPrompt) {
                // Check token limit
                tokenCount += 1
                if tokenCount >= maxTokens {
                    break
                }

                // Check stop sequences
                if let stopSequences = options.stopSequences {
                    var shouldStop = false
                    for sequence in stopSequences {
                        if token.contains(sequence) {
                            shouldStop = true
                            break
                        }
                    }
                    if shouldStop { break }
                }

                // Yield token
                onToken(token)
            }
        } catch {
            throw FrameworkError(
                framework: .llamaCpp,
                underlying: error,
                context: "Streaming generation failed"
            )
        }
    }

    public func cleanup() async {
        llm = nil
        modelPath = nil
        _modelInfo = nil
        context = nil
    }

    public func getModelMemoryUsage() async throws -> Int64 {
        // Estimate based on model file size and context
        guard let modelPath = modelPath else {
            throw LLMServiceError.notInitialized
        }

        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: modelPath)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Add context memory (approximately 10MB per 1000 context tokens)
        let contextMemory = Int64(2048 * 10 * 1024) // 20MB for 2048 context

        return fileSize + contextMemory
    }

    public func setContext(_ context: Context) async {
        self.context = context

        // Update LLM conversation history if needed
        if let llm = llm, let messages = context.messages {
            // Convert context messages to LLM format
            var history: [Message] = []
            for message in messages {
                let role: Role = message.role == .user ? .user : .assistant
                history.append(Message(role: role, content: message.content))
            }
            await llm.updateHistory(history)
        }
    }

    public func clearContext() async {
        self.context = nil
        if let llm = llm {
            await llm.updateHistory([])
        }
    }

    // MARK: - Private Helpers

    private func determineTemplate(from path: String) -> Template {
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()

        if filename.contains("chatml") || filename.contains("openai") {
            return .chatML
        } else if filename.contains("alpaca") {
            return .alpaca
        } else if filename.contains("llama") {
            return .llama3
        } else if filename.contains("mistral") {
            return .mistral
        } else if filename.contains("gemma") {
            return .gemma
        }

        // Default to ChatML
        return .chatML
    }

    private func determineFormat(from path: String) -> ModelFormat {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "gguf" ? .gguf : .ggml
    }

    private func applyGenerationOptions(_ options: GenerationOptions, to llm: LLM) async {
        var config = Configuration()

        if let temperature = options.temperature {
            config.temperature = Float(temperature)
        }
        if let topP = options.topP {
            config.topP = Float(topP)
        }
        if let topK = options.topK {
            config.topK = Int32(topK)
        }
        if let repeatPenalty = options.repetitionPenalty {
            config.repeatPenalty = Float(repeatPenalty)
        }
        if let seed = options.seed {
            config.seed = UInt32(seed)
        }

        await llm.updateConfiguration(config)
    }

    private func buildPromptWithContext(_ prompt: String) -> String {
        guard let context = context else { return prompt }

        // Build conversation history
        var fullPrompt = ""

        // Add system prompt if available
        if let systemPrompt = context.systemPrompt {
            fullPrompt += "System: \(systemPrompt)\n\n"
        }

        // Add message history
        if let messages = context.messages {
            for message in messages.suffix(10) { // Last 10 messages
                let role = message.role == .user ? "User" : "Assistant"
                fullPrompt += "\(role): \(message.content)\n"
            }
        }

        // Add current prompt
        fullPrompt += "User: \(prompt)\nAssistant: "

        return fullPrompt
    }
}
