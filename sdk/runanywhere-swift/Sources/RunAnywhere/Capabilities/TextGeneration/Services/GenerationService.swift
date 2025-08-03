import Foundation

/// Main service for text generation
public class GenerationService {
    private let routingService: RoutingService
    private let contextManager: ContextManager
    private let performanceMonitor: PerformanceMonitor
    private let modelLoadingService: ModelLoadingService

    // Current loaded model
    private var currentLoadedModel: LoadedModel?

    public init(
        routingService: RoutingService,
        contextManager: ContextManager,
        performanceMonitor: PerformanceMonitor,
        modelLoadingService: ModelLoadingService? = nil
    ) {
        self.routingService = routingService
        self.contextManager = contextManager
        self.performanceMonitor = performanceMonitor
        self.modelLoadingService = modelLoadingService ?? ServiceContainer.shared.modelLoadingService
    }

    /// Set the current loaded model for generation
    public func setCurrentModel(_ model: LoadedModel?) {
        self.currentLoadedModel = model
    }

    /// Generate text using the loaded model
    public func generate(
        prompt: String,
        options: GenerationOptions
    ) async throws -> GenerationResult {
        // Start performance tracking
        let startTime = Date()

        // Prepare context
        let context = try await contextManager.prepareContext(
            prompt: prompt,
            options: options
        )

        // Get routing decision
        let routingDecision = try await routingService.determineRouting(
            prompt: prompt,
            context: context,
            options: options
        )

        // Generate based on routing decision
        let result: GenerationResult

        switch routingDecision {
        case .onDevice(let framework, let reason):
            result = try await generateOnDevice(
                prompt: prompt,
                context: context,
                options: options,
                framework: framework
            )

        case .cloud(let provider, let reason):
            result = try await generateInCloud(
                prompt: prompt,
                context: context,
                options: options,
                provider: provider
            )

        case .hybrid(let devicePortion, let framework, let reason):
            result = try await generateHybrid(
                prompt: prompt,
                context: context,
                options: options,
                devicePortion: devicePortion,
                framework: framework
            )
        }

        // Performance tracking is handled by the monitoring service

        return result
    }

    private func generateOnDevice(
        prompt: String,
        context: Context,
        options: GenerationOptions,
        framework: LLMFramework?
    ) async throws -> GenerationResult {
        let startTime = Date()

        // Use the current loaded model
        guard let loadedModel = currentLoadedModel else {
            throw SDKError.modelNotFound("No model is currently loaded")
        }

        // Set context if needed
        await loadedModel.service.setContext(context)

        // Generate text using the actual loaded model's service
        let generatedText = try await loadedModel.service.generate(
            prompt: prompt,
            options: options
        )

        // Calculate metrics
        let latency = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
        let estimatedTokens = generatedText.split(separator: " ").count
        let tokensPerSecond = Double(estimatedTokens) / (latency / 1000.0)

        // Get memory usage from the service
        let memoryUsage = try await loadedModel.service.getModelMemoryUsage()

        return GenerationResult(
            text: generatedText,
            tokensUsed: estimatedTokens,
            modelUsed: loadedModel.model.id,
            latencyMs: latency,
            executionTarget: .onDevice,
            savedAmount: 0.001, // Calculate based on cloud pricing
            performanceMetrics: PerformanceMetrics(
                inferenceTimeMs: latency,
                tokensPerSecond: tokensPerSecond,
                peakMemoryUsage: memoryUsage
            )
        )
    }

    private func generateInCloud(
        prompt: String,
        context: Context,
        options: GenerationOptions,
        provider: String?
    ) async throws -> GenerationResult {
        // Placeholder implementation
        return GenerationResult(
            text: "Generated text in cloud",
            tokensUsed: 10,
            modelUsed: "cloud-model",
            latencyMs: 50.0,
            executionTarget: .cloud,
            savedAmount: 0.001,
            performanceMetrics: PerformanceMetrics(
                inferenceTimeMs: 50.0,
                tokensPerSecond: 20.0
            )
        )
    }

    private func generateHybrid(
        prompt: String,
        context: Context,
        options: GenerationOptions,
        devicePortion: Double,
        framework: LLMFramework?
    ) async throws -> GenerationResult {
        // For hybrid approach, use on-device generation with partial processing
        // In a real implementation, this would split processing between device and cloud
        let startTime = Date()

        // Use the current loaded model
        guard let loadedModel = currentLoadedModel else {
            throw SDKError.modelNotFound("No model is currently loaded")
        }

        // Set context if needed
        await loadedModel.service.setContext(context)

        // For now, use on-device generation entirely
        // In a real implementation, this would coordinate between device and cloud
        let generatedText = try await loadedModel.service.generate(
            prompt: prompt,
            options: options
        )

        // Calculate metrics
        let latency = Date().timeIntervalSince(startTime) * 1000
        let estimatedTokens = generatedText.split(separator: " ").count
        let tokensPerSecond = Double(estimatedTokens) / (latency / 1000.0)

        // Get memory usage from the service
        let memoryUsage = try await loadedModel.service.getModelMemoryUsage()

        return GenerationResult(
            text: generatedText,
            tokensUsed: estimatedTokens,
            modelUsed: loadedModel.model.id,
            latencyMs: latency,
            executionTarget: .hybrid,
            savedAmount: 0.0005, // Hybrid saves less than full on-device
            performanceMetrics: PerformanceMetrics(
                inferenceTimeMs: latency,
                tokensPerSecond: tokensPerSecond,
                peakMemoryUsage: memoryUsage
            )
        )
    }
}
