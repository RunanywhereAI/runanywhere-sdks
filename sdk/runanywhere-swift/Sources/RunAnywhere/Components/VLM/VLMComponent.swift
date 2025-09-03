import Foundation
import CoreGraphics

// MARK: - VLM Service Protocol

/// Protocol for Vision Language Model services
public protocol VLMService: AnyObject {
    /// Initialize the VLM service
    func initialize(modelPath: String?) async throws

    /// Process image with text prompt
    func processImage(
        imageData: Data,
        prompt: String,
        options: VLMOptions
    ) async throws -> VLMResult

    /// Check if service is ready
    var isReady: Bool { get }

    /// Get current model identifier
    var currentModel: String? { get }

    /// Cleanup resources
    func cleanup() async
}

// MARK: - VLM Configuration

/// Configuration for VLM component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
public struct VLMConfiguration: ComponentConfiguration, ComponentInitParameters {
    /// Component type
    public var componentType: SDKComponent { .vlm }

    /// Model ID
    public let modelId: String?

    // VLM-specific parameters
    public let imageSize: Int // Square image size (e.g., 224, 384, 512)
    public let maxImageTokens: Int
    public let contextLength: Int
    public let useGPUIfAvailable: Bool
    public let imagePreprocessing: ImagePreprocessing

    public enum ImagePreprocessing: String, Sendable {
        case none = "none"
        case normalize = "normalize"
        case centerCrop = "center_crop"
        case resize = "resize"
    }

    public init(
        modelId: String? = nil,
        imageSize: Int = 384,
        maxImageTokens: Int = 576,
        contextLength: Int = 2048,
        useGPUIfAvailable: Bool = true,
        imagePreprocessing: ImagePreprocessing = .normalize
    ) {
        self.modelId = modelId
        self.imageSize = imageSize
        self.maxImageTokens = maxImageTokens
        self.contextLength = contextLength
        self.useGPUIfAvailable = useGPUIfAvailable
        self.imagePreprocessing = imagePreprocessing
    }

    public func validate() throws {
        let validImageSizes = [224, 256, 384, 512, 768, 1024]
        guard validImageSizes.contains(imageSize) else {
            throw SDKError.validationFailed("Image size must be one of: \(validImageSizes)")
        }
        guard maxImageTokens > 0 && maxImageTokens <= 2048 else {
            throw SDKError.validationFailed("Max image tokens must be between 1 and 2048")
        }
        guard contextLength > 0 && contextLength <= 32768 else {
            throw SDKError.validationFailed("Context length must be between 1 and 32768")
        }
    }
}

// MARK: - VLM Input/Output Models

/// Input for Vision Language Model (conforms to ComponentInput protocol)
public struct VLMInput: ComponentInput {
    /// Image data to process
    public let image: Data

    /// Text prompt or question about the image
    public let prompt: String

    /// Image format
    public let imageFormat: ImageFormat

    /// Optional processing options
    public let options: VLMOptions?

    public init(
        image: Data,
        prompt: String,
        imageFormat: ImageFormat = .jpeg,
        options: VLMOptions? = nil
    ) {
        self.image = image
        self.prompt = prompt
        self.imageFormat = imageFormat
        self.options = options
    }

    public func validate() throws {
        guard !image.isEmpty else {
            throw SDKError.validationFailed("Image data cannot be empty")
        }
        guard !prompt.isEmpty else {
            throw SDKError.validationFailed("Prompt cannot be empty")
        }
    }
}

/// Output from Vision Language Model (conforms to ComponentOutput protocol)
public struct VLMOutput: ComponentOutput {
    /// Generated text response
    public let text: String

    /// Detected objects in the image
    public let detectedObjects: [DetectedObject]?

    /// Regions of interest
    public let regions: [ImageRegion]?

    /// Overall confidence score
    public let confidence: Float

    /// Processing metadata
    public let metadata: VLMMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        text: String,
        detectedObjects: [DetectedObject]? = nil,
        regions: [ImageRegion]? = nil,
        confidence: Float,
        metadata: VLMMetadata,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.detectedObjects = detectedObjects
        self.regions = regions
        self.confidence = confidence
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

/// VLM processing metadata
public struct VLMMetadata: Sendable {
    public let modelId: String
    public let processingTime: TimeInterval
    public let imageSize: CGSize
    public let tokenCount: Int

    public init(
        modelId: String,
        processingTime: TimeInterval,
        imageSize: CGSize,
        tokenCount: Int
    ) {
        self.modelId = modelId
        self.processingTime = processingTime
        self.imageSize = imageSize
        self.tokenCount = tokenCount
    }
}

/// Detected object in image
public struct DetectedObject: Sendable {
    public let label: String
    public let confidence: Float
    public let boundingBox: BoundingBox

    public init(label: String, confidence: Float, boundingBox: BoundingBox) {
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Image region of interest
public struct ImageRegion: Sendable {
    public let id: String
    public let description: String
    public let boundingBox: BoundingBox
    public let importance: Float

    public init(id: String, description: String, boundingBox: BoundingBox, importance: Float) {
        self.id = id
        self.description = description
        self.boundingBox = boundingBox
        self.importance = importance
    }
}

/// Bounding box for object detection
public struct BoundingBox: Sendable {
    public let x: Float
    public let y: Float
    public let width: Float
    public let height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}


/// Options for VLM processing
public struct VLMOptions: Sendable {
    public let imageSize: Int
    public let maxTokens: Int
    public let temperature: Float
    public let topP: Float?

    public init(
        imageSize: Int = 384,
        maxTokens: Int = 100,
        temperature: Float = 0.7,
        topP: Float? = nil
    ) {
        self.imageSize = imageSize
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
    }
}

/// Result from VLM processing
public struct VLMResult: Sendable {
    public let text: String
    public let confidence: Float?
    public let detections: [VLMDetection]?
    public let regions: [VLMRegion]?

    public struct VLMDetection: Sendable {
        public let label: String
        public let confidence: Float
        public let bbox: VLMBoundingBox
    }

    public struct VLMRegion: Sendable {
        public let id: String
        public let description: String
        public let bbox: VLMBoundingBox
        public let importance: Float
    }

    public struct VLMBoundingBox: Sendable {
        public let x: Float
        public let y: Float
        public let width: Float
        public let height: Float
    }
}

// MARK: - VLM Framework Adapter Protocol

/// Protocol for VLM framework adapters
public protocol VLMFrameworkAdapter: ComponentAdapter where ServiceType: VLMService {
    /// Create a VLM service for the given configuration
    func createVLMService(configuration: VLMConfiguration) async throws -> ServiceType
}

// MARK: - Default VLM Adapter (Mock)

/// Default VLM adapter - this would be replaced with actual implementations
public final class DefaultVLMAdapter: ComponentAdapter {
    public typealias ServiceType = MockVLMService

    public init() {}

    public func createService(configuration: any ComponentConfiguration) async throws -> MockVLMService {
        guard let vlmConfig = configuration as? VLMConfiguration else {
            throw SDKError.validationFailed("Expected VLMConfiguration")
        }
        return try await createVLMService(configuration: vlmConfig)
    }

    public func createVLMService(configuration: VLMConfiguration) async throws -> MockVLMService {
        let service = MockVLMService(configuration: configuration)
        try await service.initialize(modelPath: configuration.modelId)
        return service
    }
}

/// Mock VLM Service for testing
public final class MockVLMService: VLMService {
    private let configuration: VLMConfiguration
    private var initialized = false

    public init(configuration: VLMConfiguration) {
        self.configuration = configuration
    }

    public func initialize(modelPath: String?) async throws {
        // Simulate model loading
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        initialized = true
    }

    public func processImage(
        imageData: Data,
        prompt: String,
        options: VLMOptions
    ) async throws -> VLMResult {
        guard initialized else {
            throw SDKError.componentNotInitialized("VLM service not initialized")
        }

        // Mock processing
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        return VLMResult(
            text: "This image shows \(prompt). [Mock response]",
            confidence: 0.92,
            detections: [
                VLMResult.VLMDetection(
                    label: "object",
                    confidence: 0.95,
                    bbox: VLMResult.VLMBoundingBox(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
                )
            ],
            regions: nil
        )
    }

    public var isReady: Bool { initialized }
    public var currentModel: String? { configuration.modelId }

    public func cleanup() async {
        initialized = false
    }
}

// MARK: - VLM Component

/// Placeholder VLM service that throws not available error
public final class UnavailableVLMService: VLMService {
    public func initialize(modelPath: String?) async throws {
        throw SDKError.componentNotInitialized("VLM service not available")
    }

    public func processImage(imageData: Data, prompt: String, options: VLMOptions) async throws -> VLMResult {
        throw SDKError.componentNotInitialized("VLM service not available")
    }

    public var isReady: Bool { false }
    public var currentModel: String? { nil }

    public func cleanup() async {}
}

public final class VLMComponent: BaseComponent<UnavailableVLMService>, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .vlm }

    private let vlmConfiguration: VLMConfiguration
    private var isModelLoaded = false
    private var modelPath: String?

    // MARK: - Initialization

    public init(configuration: VLMConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.vlmConfiguration = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> UnavailableVLMService {
        // Emit model checking event
        eventBus.publish(ComponentInitializationEvent.componentChecking(
            component: Self.componentType,
            modelId: vlmConfiguration.modelId
        ))

        // Check if model needs downloading
        if let modelId = vlmConfiguration.modelId {
            modelPath = modelId // In real implementation, check if model exists

            // Simulate download check
            let needsDownload = false // In real implementation, check model store

            if needsDownload {
                // Emit download required event
                eventBus.publish(ComponentInitializationEvent.componentDownloadRequired(
                    component: Self.componentType,
                    modelId: modelId,
                    sizeBytes: 2_000_000_000 // 2GB example for VLM models
                ))

                // Download model
                try await downloadModel(modelId: modelId)
            }
        }

        // VLM requires external implementation
        throw SDKError.componentNotInitialized(
            "VLM service requires an external implementation. Please add a vision model provider as a dependency."
        )
    }

    public override func initializeService() async throws {
        guard let service = service else { return }

        // Track model loading state
        // currentStage = "model_loading" // TODO: Fix access to currentStage
        eventBus.publish(ComponentInitializationEvent.componentInitializing(
            component: Self.componentType,
            modelId: vlmConfiguration.modelId
        ))

        try await service.initialize(modelPath: modelPath)
        isModelLoaded = true
    }

    // MARK: - Model Management

    private func downloadModel(modelId: String) async throws {
        // Emit download started event
        eventBus.publish(ComponentInitializationEvent.componentDownloadStarted(
            component: Self.componentType,
            modelId: modelId
        ))

        // Simulate download with progress (VLM models are typically large)
        for progress in stride(from: 0.0, through: 1.0, by: 0.05) {
            eventBus.publish(ComponentInitializationEvent.componentDownloadProgress(
                component: Self.componentType,
                modelId: modelId,
                progress: progress
            ))
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }

        // Emit download completed event
        eventBus.publish(ComponentInitializationEvent.componentDownloadCompleted(
            component: Self.componentType,
            modelId: modelId
        ))
    }

    // MARK: - Public API

    /// Analyze an image with a text prompt
    public func analyze(image: Data, prompt: String, format: ImageFormat = .jpeg) async throws -> VLMOutput {
        try ensureReady()

        let input = VLMInput(image: image, prompt: prompt, imageFormat: format)
        return try await process(input)
    }

    /// Describe an image
    public func describeImage(_ image: Data, format: ImageFormat = .jpeg) async throws -> VLMOutput {
        try ensureReady()

        let input = VLMInput(
            image: image,
            prompt: "Describe this image in detail",
            imageFormat: format
        )
        return try await process(input)
    }

    /// Answer a question about an image
    public func answerQuestion(about image: Data, question: String, format: ImageFormat = .jpeg) async throws -> VLMOutput {
        try ensureReady()

        let input = VLMInput(image: image, prompt: question, imageFormat: format)
        return try await process(input)
    }

    /// Detect objects in an image
    public func detectObjects(in image: Data, format: ImageFormat = .jpeg) async throws -> [DetectedObject] {
        try ensureReady()

        let input = VLMInput(
            image: image,
            prompt: "Detect and list all objects in this image",
            imageFormat: format
        )
        let output = try await process(input)
        return output.detectedObjects ?? []
    }

    /// Process VLM input
    public func process(_ input: VLMInput) async throws -> VLMOutput {
        try ensureReady()

        guard let vlmService = service else {
            throw SDKError.componentNotReady("VLM service not available")
        }

        // Validate input
        try input.validate()

        // Preprocess image if needed
        let processedImage = try preprocessImage(input.image, format: input.imageFormat)

        // Create options from input or use defaults
        let options = input.options ?? VLMOptions(
            imageSize: vlmConfiguration.imageSize,
            maxTokens: vlmConfiguration.maxImageTokens,
            temperature: 0.7
        )

        // Track processing time
        let startTime = Date()

        // Process image
        let result = try await vlmService.processImage(
            imageData: processedImage,
            prompt: input.prompt,
            options: options
        )

        let processingTime = Date().timeIntervalSince(startTime)

        // Convert detections
        let detectedObjects = result.detections?.map { detection in
            DetectedObject(
                label: detection.label,
                confidence: detection.confidence,
                boundingBox: BoundingBox(
                    x: detection.bbox.x,
                    y: detection.bbox.y,
                    width: detection.bbox.width,
                    height: detection.bbox.height
                )
            )
        }

        // Convert regions
        let regions = result.regions?.map { region in
            ImageRegion(
                id: region.id,
                description: region.description,
                boundingBox: BoundingBox(
                    x: region.bbox.x,
                    y: region.bbox.y,
                    width: region.bbox.width,
                    height: region.bbox.height
                ),
                importance: region.importance
            )
        }

        // Estimate image size (mock - real implementation would extract from image data)
        let imageSize = CGSize(width: Double(vlmConfiguration.imageSize), height: Double(vlmConfiguration.imageSize))

        let metadata = VLMMetadata(
            modelId: vlmConfiguration.modelId ?? "unknown",
            processingTime: processingTime,
            imageSize: imageSize,
            tokenCount: result.text.count / 4 // Rough estimate
        )

        return VLMOutput(
            text: result.text,
            detectedObjects: detectedObjects,
            regions: regions,
            confidence: result.confidence ?? 0.9,
            metadata: metadata
        )
    }

    /// Get service for compatibility
    public func getService() -> VLMService? {
        return service
    }

    // MARK: - Cleanup

    public override func performCleanup() async throws {
        await service?.cleanup()
        isModelLoaded = false
        modelPath = nil
    }

    // MARK: - Private Helpers

    private func preprocessImage(_ imageData: Data, format: ImageFormat) throws -> Data {
        // Apply preprocessing based on configuration
        switch vlmConfiguration.imagePreprocessing {
        case .none:
            return imageData
        case .normalize:
            // Normalize image pixels to [0, 1] or [-1, 1]
            // This would require image processing library
            return imageData
        case .centerCrop:
            // Center crop to target size
            // This would require image processing library
            return imageData
        case .resize:
            // Resize to target dimensions
            // This would require image processing library
            return imageData
        }
    }
}

// MARK: - Core Graphics Support

import CoreGraphics

// MARK: - Compatibility Typealias

/// Compatibility alias for migration
public typealias VLMInitParameters = VLMConfiguration
