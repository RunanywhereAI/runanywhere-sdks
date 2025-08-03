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
        let maxTokens = 2048 // Default context length
        let template = determineTemplate(from: modelPath)

        // Initialize LLM instance
        do {
            self.llm = LLM(
                from: URL(fileURLWithPath: modelPath),
                template: template,
                maxTokenCount: Int32(maxTokens)
            )

            // Note: Will configure generation parameters during inference
            // LLM.swift Configuration API requires apiKey parameter

            // Create model info
            guard let llm = self.llm else {
                throw FrameworkError(
                    framework: .llamaCpp,
                    underlying: LLMError.modelLoadFailed,
                    context: "Failed to initialize LLM.swift with model at \(modelPath)"
                )
            }

            _modelInfo = LoadedModelInfo(
                id: UUID().uuidString,
                name: URL(fileURLWithPath: modelPath).lastPathComponent,
                framework: .llamaCpp,
                format: determineFormat(from: modelPath),
                memoryUsage: try await getModelMemoryUsage(),
                contextLength: Int(maxTokens),
                configuration: hardwareConfig ?? HardwareConfiguration(
                    primaryAccelerator: .cpu,
                    memoryMode: .balanced
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
            let response = await llm.getCompletion(from: fullPrompt)

            // Apply stop sequences if specified
            var finalResponse = response
            if !options.stopSequences.isEmpty {
                for sequence in options.stopSequences {
                    if let range = finalResponse.range(of: sequence) {
                        finalResponse = String(finalResponse[..<range.lowerBound])
                        break
                    }
                }
            }

            // Limit to max tokens if specified
            if options.maxTokens > 0 {
                let tokens = finalResponse.split(separator: " ")
                if tokens.count > options.maxTokens {
                    finalResponse = tokens.prefix(options.maxTokens).joined(separator: " ")
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
        let maxTokens = options.maxTokens > 0 ? options.maxTokens : Int.max

        // Generate with streaming using respond method
        do {
            await llm.respond(to: fullPrompt) { response in
                var fullResponse = ""
                for await token in response {
                    // Check token limit
                    tokenCount += 1
                    if tokenCount >= maxTokens {
                        break
                    }

                    // Check stop sequences
                    if !options.stopSequences.isEmpty {
                        var shouldStop = false
                        for sequence in options.stopSequences {
                            if token.contains(sequence) {
                                shouldStop = true
                                break
                            }
                        }
                        if shouldStop { break }
                    }

                    // Yield token
                    onToken(token)
                    fullResponse += token
                }
                return fullResponse
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
        if let llm = llm {
            if !context.messages.isEmpty {
                // Convert context messages to LLM Chat format
                var history: [Chat] = []
                for message in context.messages {
                    let role: Role = message.role == .user ? .user : .bot
                    history.append((role: role, content: message.content))
                }
                llm.history = history
            }
        }
    }

    public func clearContext() async {
        self.context = nil
        if let llm = llm {
            llm.history = []
        }
    }

    // MARK: - Private Helpers

    private func determineTemplate(from path: String) -> Template {
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()

        if filename.contains("chatml") || filename.contains("openai") {
            return .chatML()
        } else if filename.contains("alpaca") {
            return .alpaca()
        } else if filename.contains("llama") {
            return .llama()
        } else if filename.contains("mistral") {
            return .mistral
        } else if filename.contains("gemma") {
            return .gemma
        }

        // Default to ChatML
        return .chatML()
    }

    private func determineFormat(from path: String) -> ModelFormat {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "gguf" ? .gguf : .ggml
    }

    private func applyGenerationOptions(_ options: GenerationOptions, to llm: LLM) async {
        // LLM.swift Configuration requires apiKey, so we'll use generation parameters directly
        // The parameters will be applied during the respond() call
        // This is a placeholder for compatibility
    }

    private func buildPromptWithContext(_ prompt: String) -> String {
        guard let context = context else { return prompt }

        // Build conversation history
        var fullPrompt = ""

        // Add system prompt if available
        if let systemPrompt = context.systemPrompt {
            fullPrompt += "System: \(systemPrompt)\n\n"
        }

        // Add message history if available
        if !context.messages.isEmpty {
            for message in context.messages.suffix(10) { // Last 10 messages
                let role = message.role == .user ? "User" : "Assistant"
                fullPrompt += "\(role): \(message.content)\n"
            }
        }

        // Add current prompt
        fullPrompt += "User: \(prompt)\nAssistant: "

        return fullPrompt
    }
}
