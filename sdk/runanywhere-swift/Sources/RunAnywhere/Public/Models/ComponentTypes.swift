import Foundation

// MARK: - Component Types

/// Represents all initializable components in the SDK
public enum SDKComponent: String, CaseIterable, Sendable {
    case llm = "LLM"
    case stt = "STT"
    case tts = "TTS"
    case vad = "VAD"
    case vlm = "VLM"
    case embedding = "Embedding"
    case speakerDiarization = "SpeakerDiarization"
    case voiceAgent = "VoiceAgent"
    case wakeWord = "wakeWord"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .llm: return "Language Model"
        case .stt: return "Speech-to-Text"
        case .tts: return "Text-to-Speech"
        case .vad: return "Voice Activity Detection"
        case .vlm: return "Vision Language Model"
        case .embedding: return "Embeddings"
        case .speakerDiarization: return "Speaker Diarization"
        case .voiceAgent: return "Voice Agent"
        case .wakeWord: return "Wake Word Detection"
        }
    }

    /// Whether this component requires model download
    public var requiresModel: Bool {
        switch self {
        case .llm, .stt, .vlm, .embedding: return true
        case .tts, .vad, .speakerDiarization, .voiceAgent, .wakeWord: return false
        }
    }
}

// MARK: - Component State

/// Lifecycle state of a component
public enum ComponentState: String, Sendable {
    case notInitialized = "Not Initialized"
    case checking = "Checking"
    case downloadRequired = "Download Required"
    case downloading = "Downloading"
    case downloaded = "Downloaded"
    case initializing = "Initializing"
    case ready = "Ready"
    case failed = "Failed"

    /// Whether the component is in a usable state
    public var isReady: Bool {
        self == .ready
    }

    /// Whether the component is in a transitional state
    public var isTransitioning: Bool {
        switch self {
        case .checking, .downloading, .initializing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Component Status

/// Complete status information for a component
public struct ComponentStatus: Sendable {
    public let component: SDKComponent
    public let state: ComponentState
    public let modelId: String?
    public let progress: Double? // 0.0 to 1.0 for download/initialization progress
    public let error: Error?
    public let lastUpdated: Date

    public init(
        component: SDKComponent,
        state: ComponentState,
        modelId: String? = nil,
        progress: Double? = nil,
        error: Error? = nil,
        lastUpdated: Date = Date()
    ) {
        self.component = component
        self.state = state
        self.modelId = modelId
        self.progress = progress
        self.error = error
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Initialization Configuration

/// Configuration for component initialization
public struct ComponentInitConfig: Sendable {
    public let component: SDKComponent
    public let modelId: String?
    public let priority: InitializationPriority
    public let downloadPolicy: DownloadPolicy

    public init(
        component: SDKComponent,
        modelId: String? = nil,
        priority: InitializationPriority = .normal,
        downloadPolicy: DownloadPolicy = .automatic
    ) {
        self.component = component
        self.modelId = modelId
        self.priority = priority
        self.downloadPolicy = downloadPolicy
    }
}

/// Priority for initialization
public enum InitializationPriority: Int, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: InitializationPriority, rhs: InitializationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Initialization Request

/// Request to initialize components
public struct InitializationRequest: Sendable {
    public let components: [ComponentInitConfig]
    public let parallel: Bool // Whether to initialize in parallel
    public let continueOnError: Bool // Whether to continue if one component fails

    public init(
        components: [ComponentInitConfig],
        parallel: Bool = true,
        continueOnError: Bool = true
    ) {
        self.components = components
        self.parallel = parallel
        self.continueOnError = continueOnError
    }

    /// Convenience initializer for simple cases
    public init(
        _ components: [SDKComponent],
        parallel: Bool = true,
        continueOnError: Bool = true
    ) {
        self.components = components.map { ComponentInitConfig(component: $0) }
        self.parallel = parallel
        self.continueOnError = continueOnError
    }
}

// MARK: - Initialization Result

/// Result of component initialization
public struct InitializationResult: Sendable {
    public let successful: [SDKComponent]
    public let failed: [(component: SDKComponent, error: Error)]
    public let duration: TimeInterval
    public let timestamp: Date

    /// Whether all components initialized successfully
    public var isComplete: Bool {
        failed.isEmpty
    }

    /// Whether at least one component initialized successfully
    public var isPartialSuccess: Bool {
        !successful.isEmpty
    }
}
