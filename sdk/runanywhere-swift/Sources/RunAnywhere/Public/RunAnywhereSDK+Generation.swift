import Foundation

// MARK: - Generation APIs

extension RunAnywhereSDK {

    /// Generate text using the loaded model
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options
    /// - Returns: The generation result
    public func generate(
        prompt: String,
        options: GenerationOptions? = nil
    ) async throws -> GenerationResult {
        logger.info("🚀 Starting generation for prompt: \(prompt.prefix(50))...")

        guard _isInitialized else {
            logger.error("❌ SDK not initialized")
            throw SDKError.notInitialized
        }

        logger.debug("✅ SDK is initialized")

        guard let model = currentModel else {
            logger.error("❌ No model loaded")
            throw SDKError.modelNotFound("No model loaded")
        }

        logger.debug("✅ Current model: \(model.name)")

        // Get effective settings from configuration
        logger.debug("🚀 Getting effective settings")
        let effectiveSettings = await getGenerationSettings()

        // Create options with configuration defaults if not provided
        let effectiveOptions = options ?? GenerationOptions(
            maxTokens: effectiveSettings.maxTokens,
            temperature: Float(effectiveSettings.temperature),
            topP: Float(effectiveSettings.topP)
        )

        // Check if analytics is enabled
        let isAnalyticsEnabled = await getAnalyticsEnabled()

        let result: GenerationResult
        if isAnalyticsEnabled {
            result = try await serviceContainer.generationService.generateWithAnalytics(
                prompt: prompt,
                options: effectiveOptions
            )
        } else {
            logger.debug("🚀 Calling GenerationService.generate()")
            result = try await serviceContainer.generationService.generate(
                prompt: prompt,
                options: effectiveOptions
            )
        }

        logger.info("✅ Generation completed successfully")
        return result
    }

    /// Generate text as a stream
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options
    /// - Returns: An async stream of generated text chunks
    public func generateStream(
        prompt: String,
        options: GenerationOptions? = nil
    ) -> AsyncThrowingStream<String, Error> {
        guard _isInitialized else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SDKError.notInitialized)
            }
        }

        guard currentModel != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SDKError.modelNotFound("No model loaded"))
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                // Get effective settings from configuration
                let effectiveSettings = await getGenerationSettings()

                // Create options with configuration defaults if not provided
                let effectiveOptions = options ?? GenerationOptions(
                    maxTokens: effectiveSettings.maxTokens,
                    temperature: Float(effectiveSettings.temperature),
                    topP: Float(effectiveSettings.topP)
                )

                // Check if analytics is enabled
                let isAnalyticsEnabled = await getAnalyticsEnabled()

                // Get the actual stream
                let stream: AsyncThrowingStream<String, Error>
                if isAnalyticsEnabled {
                    stream = serviceContainer.streamingService.generateStreamWithAnalytics(
                        prompt: prompt,
                        options: effectiveOptions
                    )
                } else {
                    stream = serviceContainer.streamingService.generateStream(
                        prompt: prompt,
                        options: effectiveOptions
                    )
                }

                // Forward all values from the inner stream
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
