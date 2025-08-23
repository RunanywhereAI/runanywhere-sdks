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
        options: RunAnywhereGenerationOptions? = nil
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
        let effectiveOptions = options ?? RunAnywhereGenerationOptions(
            maxTokens: effectiveSettings.maxTokens,
            temperature: Float(effectiveSettings.temperature),
            topP: Float(effectiveSettings.topP)
        )

        // Check if analytics is enabled
        let isAnalyticsEnabled = await getAnalyticsEnabled()

        logger.debug("🚀 Calling GenerationService.generate()")
        let result = try await serviceContainer.generationService.generate(
            prompt: prompt,
            options: effectiveOptions
        )

        // Track analytics if enabled
        if isAnalyticsEnabled {
            await trackGenerationAnalytics(result: result, prompt: prompt, options: effectiveOptions)
        }

        logger.info("✅ Generation completed successfully")
        return result
    }

    // MARK: - Analytics Helpers

    private func trackGenerationAnalytics(
        result: GenerationResult,
        prompt: String,
        options: RunAnywhereGenerationOptions
    ) async {
        do {
            let analyticsService = await serviceContainer.generationAnalytics

            var properties: [String: String] = [:]
            properties["model_id"] = result.modelUsed
            properties["input_tokens"] = "\(prompt.count / 4)" // Rough token estimate
            properties["output_tokens"] = "\(result.text.count / 4)" // Rough token estimate
            properties["total_time"] = "\(result.latencyMs)"
            properties["tokens_used"] = "\(result.tokensUsed)"
            properties["framework"] = result.framework?.rawValue ?? "unknown"
            properties["execution_target"] = result.executionTarget.rawValue
            properties["hardware_used"] = result.hardwareUsed.rawValue
            properties["memory_used"] = "\(result.memoryUsed)"
            properties["saved_amount"] = "\(result.savedAmount)"

            let event = GenerationEvent(
                type: .generationCompleted,
                properties: properties
            )

            await analyticsService.track(event: event)
            logger.debug("📊 Generation analytics tracked")
        } catch {
            logger.warning("Failed to track generation analytics: \(error)")
        }
    }

    private func trackStreamingStarted(
        prompt: String,
        options: RunAnywhereGenerationOptions
    ) async {
        do {
            let analyticsService = await serviceContainer.generationAnalytics

            var properties: [String: String] = [:]
            properties["model_id"] = "streaming" // Will be updated when model is determined
            properties["input_tokens"] = "\(prompt.count / 4)" // Rough token estimate
            properties["output_tokens"] = "0"
            properties["total_time"] = "0"
            properties["framework"] = "unknown"
            properties["execution_target"] = "unknown"

            let event = GenerationEvent(
                type: .generationStarted,
                properties: properties
            )

            await analyticsService.track(event: event)
            logger.debug("📊 Streaming start analytics tracked")
        } catch {
            logger.warning("Failed to track streaming analytics: \(error)")
        }
    }

    /// Generate text as a stream
    /// - Parameters:
    ///   - prompt: The prompt to generate from
    ///   - options: Generation options
    /// - Returns: An async stream of generated text chunks
    public func generateStream(
        prompt: String,
        options: RunAnywhereGenerationOptions? = nil
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
                let effectiveOptions = options ?? RunAnywhereGenerationOptions(
                    maxTokens: effectiveSettings.maxTokens,
                    temperature: Float(effectiveSettings.temperature),
                    topP: Float(effectiveSettings.topP)
                )

                // Check if analytics is enabled
                let isAnalyticsEnabled = await getAnalyticsEnabled()

                // Get the actual stream
                let stream = serviceContainer.streamingService.generateStream(
                    prompt: prompt,
                    options: effectiveOptions
                )

                // Track streaming analytics if enabled
                if isAnalyticsEnabled {
                    await trackStreamingStarted(prompt: prompt, options: effectiveOptions)
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
