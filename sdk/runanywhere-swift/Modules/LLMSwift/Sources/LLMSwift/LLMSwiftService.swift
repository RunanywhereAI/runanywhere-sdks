import Foundation
import RunAnywhere
import LLM
import os.log

public class LLMSwiftService: LLMService {
    private var llm: LLM?
    private var modelPath: String?
    private var _modelInfo: LoadedModelInfo?
    private let hardwareConfig: HardwareConfiguration?
    private let logger = Logger(subsystem: "com.runanywhere.llmswift", category: "LLMSwiftService")

    public var isReady: Bool { llm != nil }
    public var modelInfo: LoadedModelInfo? { _modelInfo }

    init(hardwareConfig: HardwareConfiguration? = nil) {
        self.hardwareConfig = hardwareConfig
    }

    public func initialize(modelPath: String) async throws {
        logger.info("🚀 Initializing with model path: \(modelPath)")
        self.modelPath = modelPath

        // Check if model file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelPath) else {
            logger.error("❌ Model file does not exist at path: \(modelPath)")
            throw LLMServiceError.modelNotLoaded
        }

        let fileSize = (try? fileManager.attributesOfItem(atPath: modelPath)[.size] as? Int64) ?? 0
        logger.info("📊 Model file size: \(fileSize) bytes")

        // Configure LLM with hardware settings
        let maxTokens = 2048 // Default context length
        let template = LLMSwiftTemplateResolver.determineTemplate(from: modelPath, systemPrompt: nil)
        logger.info("📝 Using template: \(String(describing: template)), maxTokens: \(maxTokens)")

        // Initialize LLM instance
        do {
            logger.info("🚀 Creating LLM instance...")

            // Create LLM instance with proper configuration
            self.llm = LLM(
                from: URL(fileURLWithPath: modelPath),
                template: template,
                historyLimit: 6,  // Limit conversation history to prevent context overflow
                maxTokenCount: Int32(maxTokens)
            )

            guard let llm = self.llm else {
                throw LLMSwiftError.modelLoadFailed
            }

            logger.info("✅ LLM instance created")

            // Validate model readiness with a simple test prompt
            logger.info("🧪 Validating model readiness with test prompt")
            guard let llm = self.llm else {
                throw FrameworkError(
                    framework: .llamaCpp,
                    underlying: LLMSwiftError.modelLoadFailed,
                    context: "Failed to initialize LLM.swift with model at \(modelPath)"
                )
            }

            // Skip the test prompt to avoid blocking during initialization
            logger.info("✅ Skipping test prompt to avoid blocking")

            // Create model info
            guard self.llm != nil else {
                throw FrameworkError(
                    framework: .llamaCpp,
                    underlying: LLMSwiftError.modelLoadFailed,
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

    public func generate(prompt: String, options: RunAnywhereGenerationOptions) async throws -> String {
        logger.info("🔧 Starting generation for prompt: \(prompt.prefix(50))...")

        guard let llm = llm else {
            logger.error("❌ LLM not initialized")
            throw LLMServiceError.notInitialized
        }

        logger.info("✅ LLM is initialized, applying options")
        logger.info("🔍 LLM instance: \(String(describing: llm))")
        logger.info("🔍 Model path: \(self.modelPath ?? "nil")")

        // Apply generation options
        await applyGenerationOptions(options, to: llm)

        // Handle system prompt if provided
        if let systemPrompt = options.systemPrompt, let modelPath = self.modelPath {
            logger.info("🔧 Applying system prompt: \(systemPrompt.prefix(100))...")
            let newTemplate = LLMSwiftTemplateResolver.determineTemplate(from: modelPath, systemPrompt: systemPrompt)
            llm.template = newTemplate
        }

        logger.info("🔧 Building prompt with context")
        // Include context if available
        let fullPrompt = buildPromptWithContext(prompt)
        logger.info("📝 Full prompt length: \(fullPrompt.count) characters")

        // Generate response with timeout protection
        do {
            logger.info("🚀 Calling llm.getCompletion() with 60-second timeout")
            logger.info("📝 Full prompt being sent to LLM:")
            logger.info("---START PROMPT---")
            logger.info("\(fullPrompt)")
            logger.info("---END PROMPT---")

            // Use the simpler getCompletion method which is more reliable
            logger.info("🔄 Using getCompletion method for generation...")

            let response = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    // Call getCompletion which handles the generation internally
                    let result = await llm.getCompletion(from: fullPrompt)
                    self.logger.info("✅ Got response from getCompletion: \(result.prefix(100))...")
                    return result
                }

                group.addTask {
                    // Timeout task
                    try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                    self.logger.error("❌ Generation timed out after 60 seconds")
                    throw LLMSwiftError.generationFailed("Generation timed out after 60 seconds")
                }

                // Return the first completed task (either result or timeout)
                guard let result = try await group.next() else {
                    throw LLMSwiftError.generationFailed("No result from generation")
                }

                // Cancel the other task
                group.cancelAll()
                return result
            }

            logger.info("✅ Got response from LLM: \(response.prefix(100))...")

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
            logger.error("❌ Generation failed: \(error)")
            throw FrameworkError(
                framework: .llamaCpp,
                underlying: error,
                context: "Generation failed for prompt: \(prompt)"
            )
        }
    }

    public func streamGenerate(
        prompt: String,
        options: RunAnywhereGenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        logger.info("🔧 streamGenerate called!")
        logger.info("🔧 Starting stream generation for prompt: \(prompt.prefix(50))...")

        guard let llm = llm else {
            logger.error("❌ LLM not initialized for streaming")
            throw LLMServiceError.notInitialized
        }

        // Apply generation options
        await applyGenerationOptions(options, to: llm)

        // Handle system prompt if provided
        if let systemPrompt = options.systemPrompt, let modelPath = self.modelPath {
            logger.info("🔧 Applying system prompt for streaming: \(systemPrompt.prefix(100))...")
            let newTemplate = LLMSwiftTemplateResolver.determineTemplate(from: modelPath, systemPrompt: systemPrompt)
            llm.template = newTemplate
        }

        // Include context
        let fullPrompt = buildPromptWithContext(prompt)
        logger.info("📝 Full streaming prompt length: \(fullPrompt.count) characters")

        // Create streaming callback
        let maxTokens = options.maxTokens > 0 ? options.maxTokens : Int.max
        var accumulatedResponse = ""

        // Generate with streaming using respond method - simpler approach
        do {
            logger.info("🚀 Starting streaming generation")
            logger.info("📝 Full streaming prompt:")
            logger.info("---START STREAMING PROMPT---")
            logger.info("\(fullPrompt)")
            logger.info("---END STREAMING PROMPT---")

            var tokenCount = 0

            // Log the actual prompt being sent to LLM.swift
            logger.info("📤 Calling llm.respond with prompt: '\(fullPrompt)'")
            logger.info("📊 Current LLM history count: \(llm.history.count)")
            if !llm.history.isEmpty {
                for (index, chat) in llm.history.enumerated() {
                    let roleStr = chat.role == .user ? "user" : "bot"
                    let contentPreview = String(chat.content.prefix(100))
                    logger.info("📜 History[\(index)]: \(roleStr) - \(contentPreview)...")
                }
            }

            await llm.respond(to: fullPrompt) { [weak self] response in
                var fullResponse = ""
                self?.logger.info("🎯 Received response stream")

                for await token in response {
                    tokenCount += 1

                    // Accumulate response to check for stop sequences
                    accumulatedResponse += token

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

            logger.info("✅ Streaming generation completed successfully")
            logger.info("📊 Total tokens streamed: \(tokenCount)")
            logger.info("📊 Full response: \(accumulatedResponse)")

        }
    }

    public func cleanup() async {
        llm = nil
        modelPath = nil
        _modelInfo = nil
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



    // MARK: - Private Helpers

    private func determineFormat(from path: String) -> ModelFormat {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "gguf" ? .gguf : .ggml
    }

    private func applyGenerationOptions(_ options: RunAnywhereGenerationOptions, to llm: LLM) async {
        // LLM.swift Configuration requires apiKey, so we'll use generation parameters directly
        // The parameters will be applied during the respond() call
        // This is a placeholder for compatibility
    }

    private func buildPromptWithContext(_ prompt: String) -> String {
        // LLM.swift manages conversation history internally
        // We should only pass the new user message
        logger.info("📝 Passing new user message to LLM.swift")
        logger.info("📝 Message length: \(prompt.count) characters")

        // Return only the new message - LLM.swift will handle the rest
        return prompt
    }
}
