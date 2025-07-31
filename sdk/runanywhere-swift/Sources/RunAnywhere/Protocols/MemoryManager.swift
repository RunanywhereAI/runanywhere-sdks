import Foundation

/// Protocol for memory management
public protocol MemoryManager {
    /// Register a loaded model
    /// - Parameters:
    ///   - model: The loaded model
    ///   - size: Memory size in bytes
    ///   - service: The LLM service managing the model
    func registerLoadedModel(_ model: LoadedModel, size: Int64, service: LLMService)
    
    /// Unregister a model
    /// - Parameter modelId: The model identifier
    func unregisterModel(_ modelId: String)
    
    /// Get current memory usage
    /// - Returns: Current memory usage in bytes
    func getCurrentMemoryUsage() -> Int64
    
    /// Get available memory
    /// - Returns: Available memory in bytes
    func getAvailableMemory() -> Int64
    
    /// Check if enough memory is available
    /// - Parameter size: Required memory size
    /// - Returns: Whether enough memory is available
    func hasAvailableMemory(for size: Int64) -> Bool
    
    /// Handle memory pressure
    func handleMemoryPressure() async
    
    /// Set memory threshold
    /// - Parameter threshold: Memory threshold in bytes
    func setMemoryThreshold(_ threshold: Int64)
    
    /// Get loaded models
    /// - Returns: Array of loaded model information
    func getLoadedModels() -> [LoadedModel]
    
    /// Request memory for a model
    /// - Parameters:
    ///   - size: Required memory size
    ///   - priority: Priority of the request
    /// - Returns: Whether memory was allocated
    func requestMemory(size: Int64, priority: MemoryPriority) async -> Bool
}

/// Loaded model information
public struct LoadedModel {
    public let id: String
    public let name: String
    public let size: Int64
    public let framework: LLMFramework
    public let loadedAt: Date
    public var lastUsed: Date
    public let priority: MemoryPriority
    
    public init(
        id: String,
        name: String,
        size: Int64,
        framework: LLMFramework,
        loadedAt: Date = Date(),
        lastUsed: Date = Date(),
        priority: MemoryPriority = .normal
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.framework = framework
        self.loadedAt = loadedAt
        self.lastUsed = lastUsed
        self.priority = priority
    }
}

/// Memory priority levels
public enum MemoryPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    public static func < (lhs: MemoryPriority, rhs: MemoryPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Protocol for progress tracking
public protocol ProgressTracker {
    /// Start a new stage
    /// - Parameter stage: The lifecycle stage
    func startStage(_ stage: LifecycleStage)
    
    /// Update stage progress
    /// - Parameters:
    ///   - stage: The lifecycle stage
    ///   - progress: Progress value (0.0 to 1.0)
    ///   - message: Optional status message
    func updateStageProgress(_ stage: LifecycleStage, progress: Double, message: String?)
    
    /// Complete a stage
    /// - Parameter stage: The lifecycle stage
    func completeStage(_ stage: LifecycleStage)
    
    /// Fail a stage
    /// - Parameters:
    ///   - stage: The lifecycle stage
    ///   - error: The error that occurred
    func failStage(_ stage: LifecycleStage, error: Error)
    
    /// Get current overall progress
    /// - Returns: Overall progress information
    func getCurrentProgress() -> OverallProgress
    
    /// Add a progress observer
    /// - Parameter observer: The observer to add
    func addObserver(_ observer: ProgressObserver)
    
    /// Remove a progress observer
    /// - Parameter observer: The observer to remove
    func removeObserver(_ observer: ProgressObserver)
}

/// Lifecycle stages for progress tracking
public enum LifecycleStage: String, CaseIterable {
    case discovery = "Discovery"
    case download = "Download"
    case extraction = "Extraction"
    case validation = "Validation"
    case initialization = "Initialization"
    case loading = "Loading"
    case ready = "Ready"
    
    /// Default message for each stage
    public var defaultMessage: String {
        switch self {
        case .discovery:
            return "Discovering model..."
        case .download:
            return "Downloading model..."
        case .extraction:
            return "Extracting files..."
        case .validation:
            return "Validating model..."
        case .initialization:
            return "Initializing model..."
        case .loading:
            return "Loading model..."
        case .ready:
            return "Model ready"
        }
    }
}

/// Overall progress information
public struct OverallProgress {
    public let percentage: Double
    public let currentStage: LifecycleStage?
    public let stageProgress: Double
    public let message: String
    public let estimatedTimeRemaining: TimeInterval?
    
    public init(
        percentage: Double,
        currentStage: LifecycleStage? = nil,
        stageProgress: Double = 0,
        message: String = "",
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.percentage = percentage
        self.currentStage = currentStage
        self.stageProgress = stageProgress
        self.message = message
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}

/// Progress observer protocol
public protocol ProgressObserver: AnyObject {
    /// Called when progress is updated
    /// - Parameter progress: The current progress
    func progressDidUpdate(_ progress: OverallProgress)
    
    /// Called when a stage completes
    /// - Parameter stage: The completed stage
    func stageDidComplete(_ stage: LifecycleStage)
    
    /// Called when a stage fails
    /// - Parameters:
    ///   - stage: The failed stage
    ///   - error: The error that occurred
    func stageDidFail(_ stage: LifecycleStage, error: Error)
}