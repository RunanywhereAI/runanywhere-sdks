import Foundation
import RunAnywhereSDK
import LLM

// Define LLMError for handling LLM.swift specific errors
enum LLMError: LocalizedError {
    case modelLoadFailed
    case initializationFailed
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load the LLM model"
        case .initializationFailed:
            return "Failed to initialize LLM service"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        }
    }
}

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
        print("🚀 [LLMSwiftService] Initializing with model path: \(modelPath)")
        self.modelPath = modelPath

        // Check if model file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelPath) else {
            print("❌ [LLMSwiftService] Model file does not exist at path: \(modelPath)")
            throw LLMServiceError.modelNotLoaded
        }

        let fileSize = (try? fileManager.attributesOfItem(atPath: modelPath)[.size] as? Int64) ?? 0
        print("📊 [LLMSwiftService] Model file size: \(fileSize) bytes")

        // Configure LLM with hardware settings
        let maxTokens = 2048 // Default context length
        let template = determineTemplate(from: modelPath)
        print("📝 [LLMSwiftService] Using template: \(template), maxTokens: \(maxTokens)")

        // Initialize LLM instance
        do {
            print("🚀 [LLMSwiftService] Creating LLM instance...")

            // Create LLM instance directly without timeout for debugging
            self.llm = LLM(
                from: URL(fileURLWithPath: modelPath),
                template: template,
                maxTokenCount: Int32(maxTokens)
            )

            guard let llm = self.llm else {
                throw LLMError.modelLoadFailed
            }

            print("✅ [LLMSwiftService] LLM instance created")

            // Validate model readiness with a simple test prompt
            print("🧪 [LLMSwiftService] Validating model readiness with test prompt")
            guard let llm = self.llm else {
                throw FrameworkError(
                    framework: .llamaCpp,
                    underlying: LLMError.modelLoadFailed,
                    context: "Failed to initialize LLM.swift with model at \(modelPath)"
                )
            }

            // Skip the test prompt to avoid blocking during initialization
            print("✅ [LLMSwiftService] Skipping test prompt to avoid blocking")

            // Note: Will configure generation parameters during inference
            // LLM.swift Configuration API requires apiKey parameter

            // Create model info
            guard self.llm != nil else {
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
        print("🔧 [LLMSwiftService] Starting generation for prompt: \(prompt.prefix(50))...")

        guard let llm = llm else {
            print("❌ [LLMSwiftService] LLM not initialized")
            throw LLMServiceError.notInitialized
        }

        print("✅ [LLMSwiftService] LLM is initialized, applying options")
        print("🔍 [LLMSwiftService] LLM instance: \(String(describing: llm))")
        print("🔍 [LLMSwiftService] Model path: \(modelPath ?? "nil")")
        // Apply generation options
        await applyGenerationOptions(options, to: llm)

        print("🔧 [LLMSwiftService] Building prompt with context")
        // Include context if available
        let fullPrompt = buildPromptWithContext(prompt)
        print("📝 [LLMSwiftService] Full prompt length: \(fullPrompt.count) characters")

        // Generate response with timeout protection
        do {
            print("🚀 [LLMSwiftService] Calling llm.getCompletion() with 60-second timeout")
            print("📝 [LLMSwiftService] Full prompt being sent to LLM:")
            print("---START PROMPT---")
            print(fullPrompt)
            print("---END PROMPT---")

            // Use the simpler getCompletion method which is more reliable
            print("🔄 [LLMSwiftService] Using getCompletion method for generation...")

            let response = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    // Call getCompletion which handles the generation internally
                    let result = await llm.getCompletion(from: fullPrompt)
                    print("✅ [LLMSwiftService] Got response from getCompletion: \(result.prefix(100))...")
                    return result
                }

                group.addTask {
                    // Timeout task
                    try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                    print("❌ [LLMSwiftService] Generation timed out after 60 seconds")
                    throw LLMError.generationFailed("Generation timed out after 60 seconds")
                }

                // Return the first completed task (either result or timeout)
                guard let result = try await group.next() else {
                    throw LLMError.generationFailed("No result from generation")
                }

                // Cancel the other task
                group.cancelAll()
                return result
            }

            print("✅ [LLMSwiftService] Got response from LLM: \(response.prefix(100))...")

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

            // Note: We return the raw response including any thinking tags
            // The SDK's GenerationService will handle parsing thinking content
            // based on the model's configuration

            // Limit to max tokens if specified (but preserve thinking tags)
            if options.maxTokens > 0 {
                // For responses with thinking content, we count tokens excluding tags
                let tokens = finalResponse.split(separator: " ")
                if tokens.count > options.maxTokens {
                    // This is a simple approximation - in practice, token counting
                    // should be done by the tokenizer
                    finalResponse = tokens.prefix(options.maxTokens).joined(separator: " ")
                }
            }

            return finalResponse
        } catch {
            print("❌ [LLMSwiftService] Generation failed: \(error)")
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
        print("🔧 [LLMSwiftService] streamGenerate called!")
        print("🔧 [LLMSwiftService] Starting stream generation for prompt: \(prompt.prefix(50))...")

        guard let llm = llm else {
            print("❌ [LLMSwiftService] LLM not initialized for streaming")
            throw LLMServiceError.notInitialized
        }

        // Apply generation options
        await applyGenerationOptions(options, to: llm)

        // Include context
        let fullPrompt = buildPromptWithContext(prompt)
        print("📝 [LLMSwiftService] Full streaming prompt length: \(fullPrompt.count) characters")

        // Create streaming callback
        var tokenCount = 0
        let maxTokens = options.maxTokens > 0 ? options.maxTokens : Int.max
        var accumulatedResponse = ""

        // Generate with streaming using respond method - simpler approach
        do {
            print("🚀 [LLMSwiftService] Starting streaming generation")

            await llm.respond(to: fullPrompt) { response in
                var fullResponse = ""
                for await token in response {
                    // Accumulate response to check for stop sequences
                    accumulatedResponse += token

                    // Note: We stream all tokens including thinking tags
                    // The SDK's StreamingService will handle parsing and filtering
                    // thinking content based on the model's configuration

                    // Check stop sequences in accumulated response
                    if !options.stopSequences.isEmpty {
                        var shouldStop = false
                        for sequence in options.stopSequences {
                            if accumulatedResponse.contains(sequence) {
                                // If we hit a stop sequence, emit only up to that point
                                if let range = accumulatedResponse.range(of: sequence) {
                                    let remainingText = String(accumulatedResponse[..<range.lowerBound])
                                    if remainingText.count > fullResponse.count {
                                        let newText = String(remainingText.suffix(remainingText.count - fullResponse.count))
                                        if !newText.isEmpty {
                                            onToken(newText)
                                        }
                                    }
                                }
                                shouldStop = true
                                break
                            }
                        }
                        if shouldStop { break }
                    }

                    // Check token limit (approximate - actual tokenization may differ)
                    tokenCount += 1
                    if tokenCount >= maxTokens {
                        break
                    }

                    // Yield token
                    onToken(token)
                    fullResponse += token
                }
                return fullResponse
            }

            print("✅ [LLMSwiftService] Streaming generation completed successfully")

        } catch {
            print("❌ [LLMSwiftService] Streaming generation failed: \(error)")
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

        print("🔍 [LLMSwiftService] Determining template for filename: \(filename)")

        if filename.contains("qwen") {
            // Qwen models typically use ChatML format
            print("✅ [LLMSwiftService] Using ChatML template for Qwen model")
            return .chatML()
        } else if filename.contains("chatml") || filename.contains("openai") {
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
        print("⚠️ [LLMSwiftService] Using default ChatML template")
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
        // LLM.swift handles context and template formatting internally through its history property
        // We've already set the context via setContext() which updates llm.history
        // So we just return the raw prompt to avoid double-processing
        print("📝 [LLMSwiftService] Returning raw prompt (LLM.swift handles formatting)")
        return prompt
    }
}
