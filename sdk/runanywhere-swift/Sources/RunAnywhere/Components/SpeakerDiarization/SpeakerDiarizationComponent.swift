// swiftlint:disable file_length
import Foundation

// MARK: - Speaker Diarization Service Protocol

/// Protocol for speaker diarization services
public protocol SpeakerDiarizationService: AnyObject { // swiftlint:disable:this avoid_any_object
    /// Initialize the service
    func initialize() async throws

    /// Process audio and identify speakers
    func processAudio(_ samples: [Float]) -> SpeakerInfo

    /// Get all identified speakers
    func getAllSpeakers() -> [SpeakerInfo]

    /// Reset the diarization state
    func reset()

    /// Check if service is ready
    var isReady: Bool { get }

    /// Cleanup resources
    func cleanup() async
}

/// Information about a detected speaker
public struct SpeakerInfo: Sendable {
    public let id: String
    public var name: String?
    public let confidence: Float?
    public let embedding: [Float]?

    public init(id: String, name: String? = nil, confidence: Float? = nil, embedding: [Float]? = nil) {
        self.id = id
        self.name = name
        self.confidence = confidence
        self.embedding = embedding
    }
}

// MARK: - Speaker Diarization Configuration

/// Configuration for Speaker Diarization component
public struct SpeakerDiarizationConfiguration: ComponentConfiguration, ComponentInitParameters {
    /// Component type
    public var componentType: SDKComponent { .speakerDiarization }

    /// Model ID (if using ML-based diarization)
    public let modelId: String?

    // Diarization parameters
    public let maxSpeakers: Int
    public let minSpeechDuration: TimeInterval
    public let speakerChangeThreshold: Float
    public let enableVoiceIdentification: Bool
    public let windowSize: TimeInterval
    public let stepSize: TimeInterval

    public init(
        modelId: String? = nil,
        maxSpeakers: Int = 10,
        minSpeechDuration: TimeInterval = 0.5,
        speakerChangeThreshold: Float = 0.7,
        enableVoiceIdentification: Bool = false,
        windowSize: TimeInterval = 2.0,
        stepSize: TimeInterval = 0.5
    ) {
        self.modelId = modelId
        self.maxSpeakers = maxSpeakers
        self.minSpeechDuration = minSpeechDuration
        self.speakerChangeThreshold = speakerChangeThreshold
        self.enableVoiceIdentification = enableVoiceIdentification
        self.windowSize = windowSize
        self.stepSize = stepSize
    }

    public func validate() throws {
        guard maxSpeakers > 0 && maxSpeakers <= 100 else {
            throw RunAnywhereError.validationFailed("Max speakers must be between 1 and 100")
        }
        guard minSpeechDuration > 0 && minSpeechDuration <= 10 else {
            throw RunAnywhereError.validationFailed("Min speech duration must be between 0 and 10 seconds")
        }
        guard speakerChangeThreshold >= 0 && speakerChangeThreshold <= 1.0 else {
            throw RunAnywhereError.validationFailed("Speaker change threshold must be between 0 and 1")
        }
    }
}

// MARK: - Speaker Diarization Input/Output Models

/// Input for Speaker Diarization (conforms to ComponentInput protocol)
public struct SpeakerDiarizationInput: ComponentInput {
    /// Audio data to diarize
    public let audioData: Data

    /// Audio format
    public let format: AudioFormat

    /// Optional transcription for labeled output
    public let transcription: STTOutput?

    /// Expected number of speakers (if known)
    public let expectedSpeakers: Int?

    /// Custom options
    public let options: SpeakerDiarizationOptions?

    public init(
        audioData: Data,
        format: AudioFormat = .wav,
        transcription: STTOutput? = nil,
        expectedSpeakers: Int? = nil,
        options: SpeakerDiarizationOptions? = nil
    ) {
        self.audioData = audioData
        self.format = format
        self.transcription = transcription
        self.expectedSpeakers = expectedSpeakers
        self.options = options
    }

    public func validate() throws {
        guard !audioData.isEmpty else {
            throw RunAnywhereError.validationFailed("Audio data cannot be empty")
        }
    }
}

/// Output from Speaker Diarization (conforms to ComponentOutput protocol)
public struct SpeakerDiarizationOutput: ComponentOutput {
    /// Speaker segments
    public let segments: [SpeakerSegment]

    /// Speaker profiles
    public let speakers: [SpeakerProfile]

    /// Labeled transcription (if STT output was provided)
    public let labeledTranscription: LabeledTranscription?

    /// Processing metadata
    public let metadata: DiarizationMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        segments: [SpeakerSegment],
        speakers: [SpeakerProfile],
        labeledTranscription: LabeledTranscription? = nil,
        metadata: DiarizationMetadata,
        timestamp: Date = Date()
    ) {
        self.segments = segments
        self.speakers = speakers
        self.labeledTranscription = labeledTranscription
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

/// Speaker segment
public struct SpeakerSegment: Sendable {
    public let speakerId: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float

    public var duration: TimeInterval {
        endTime - startTime
    }

    public init(speakerId: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
        self.speakerId = speakerId
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

/// Speaker profile
public struct SpeakerProfile: Sendable {
    public let id: String
    public let embedding: [Float]?
    public let totalSpeakingTime: TimeInterval
    public let segmentCount: Int
    public let name: String?

    public init(
        id: String,
        embedding: [Float]? = nil,
        totalSpeakingTime: TimeInterval,
        segmentCount: Int,
        name: String? = nil
    ) {
        self.id = id
        self.embedding = embedding
        self.totalSpeakingTime = totalSpeakingTime
        self.segmentCount = segmentCount
        self.name = name
    }
}

/// Labeled transcription with speaker information
public struct LabeledTranscription: Sendable {
    public let segments: [LabeledSegment]

    public struct LabeledSegment: Sendable {
        public let speakerId: String
        public let text: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval

        public init(speakerId: String, text: String, startTime: TimeInterval, endTime: TimeInterval) {
            self.speakerId = speakerId
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    public init(segments: [LabeledSegment]) {
        self.segments = segments
    }

    /// Get full transcript as formatted text
    public var formattedTranscript: String {
        segments.map { "[\($0.speakerId)]: \($0.text)" }.joined(separator: "\n")
    }
}

/// Diarization metadata
public struct DiarizationMetadata: Sendable {
    public let processingTime: TimeInterval
    public let audioLength: TimeInterval
    public let speakerCount: Int
    public let method: String // "energy", "ml", "hybrid"

    public init(
        processingTime: TimeInterval,
        audioLength: TimeInterval,
        speakerCount: Int,
        method: String
    ) {
        self.processingTime = processingTime
        self.audioLength = audioLength
        self.speakerCount = speakerCount
        self.method = method
    }
}

/// Options for speaker diarization
public struct SpeakerDiarizationOptions: Sendable {
    public let maxSpeakers: Int
    public let minSpeechDuration: TimeInterval
    public let speakerChangeThreshold: Float

    public init(
        maxSpeakers: Int = 10,
        minSpeechDuration: TimeInterval = 0.5,
        speakerChangeThreshold: Float = 0.7
    ) {
        self.maxSpeakers = maxSpeakers
        self.minSpeechDuration = minSpeechDuration
        self.speakerChangeThreshold = speakerChangeThreshold
    }
}

// MARK: - Default Speaker Diarization Adapter

/// Default adapter using simple energy-based diarization
public final class DefaultSpeakerDiarizationAdapter: ComponentAdapter {
    public typealias ServiceType = DefaultSpeakerDiarization

    public init() {}

    public func createService(configuration: any ComponentConfiguration) async throws -> DefaultSpeakerDiarization {
        guard let diarizationConfig = configuration as? SpeakerDiarizationConfiguration else {
            throw RunAnywhereError.validationFailed("Expected SpeakerDiarizationConfiguration")
        }
        return try await createDiarizationService(configuration: diarizationConfig)
    }

    public func createDiarizationService(configuration: SpeakerDiarizationConfiguration) async throws -> DefaultSpeakerDiarization {
        let service = DefaultSpeakerDiarization()
        // Initialize if needed
        return service
    }
}

// MARK: - Speaker Diarization Component

/// Speaker Diarization component following the clean architecture
@MainActor
public final class SpeakerDiarizationComponent: BaseComponent<DefaultSpeakerDiarization>, @unchecked Sendable {

    // MARK: - Properties

    public override static var componentType: SDKComponent { .speakerDiarization }

    private let diarizationConfiguration: SpeakerDiarizationConfiguration
    private var speakerProfiles: [String: SpeakerProfile] = [:]

    // MARK: - Initialization

    public init(configuration: SpeakerDiarizationConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.diarizationConfiguration = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> DefaultSpeakerDiarization {
        // Emit checking event
        eventBus.publish(ComponentInitializationEvent.componentChecking(
            component: Self.componentType,
            modelId: diarizationConfiguration.modelId
        ))

        // For now, we don't have an adapter registry

        // Fallback to default adapter
        let defaultAdapter = DefaultSpeakerDiarizationAdapter()
        return try await defaultAdapter.createDiarizationService(configuration: diarizationConfiguration)
    }

    public override func initializeService() async throws {
        // Track initialization
        eventBus.publish(ComponentInitializationEvent.componentInitializing(
            component: Self.componentType,
            modelId: diarizationConfiguration.modelId
        ))

        // Service is ready to use
    }

    // MARK: - Public API

    /// Diarize audio to identify speakers
    public func diarize(_ audioData: Data, format: AudioFormat = .wav) async throws -> SpeakerDiarizationOutput {
        try ensureReady()

        let input = SpeakerDiarizationInput(audioData: audioData, format: format)
        return try await process(input)
    }

    /// Diarize with transcription for labeled output
    public func diarizeWithTranscription(
        _ audioData: Data,
        transcription: STTOutput,
        format: AudioFormat = .wav
    ) async throws -> SpeakerDiarizationOutput {
        try ensureReady()

        let input = SpeakerDiarizationInput(
            audioData: audioData,
            format: format,
            transcription: transcription
        )
        return try await process(input)
    }

    /// Process diarization input
    public func process(_ input: SpeakerDiarizationInput) async throws -> SpeakerDiarizationOutput {
        try ensureReady()

        guard let diarizationService = service else {
            throw RunAnywhereError.componentNotReady("Speaker diarization service not available")
        }

        // Validate input
        try input.validate()

        // Track processing time
        let startTime = Date()

        // Convert audio data to float array for processing
        let audioSamples = convertDataToFloatArray(input.audioData)

        // Process audio to detect speakers
        let speakerInfo = diarizationService.processAudio(audioSamples)

        // Build segments from speaker info
        var segments: [SpeakerSegment] = []
        var currentSpeaker = speakerInfo.id
        var segmentStart: TimeInterval = 0
        let segmentDuration: TimeInterval = diarizationConfiguration.windowSize

        // Simple segmentation (real implementation would be more sophisticated)
        let totalDuration = Double(audioSamples.count) / 16000.0
        var currentTime: TimeInterval = 0

        while currentTime < totalDuration {
            let endTime = min(currentTime + segmentDuration, totalDuration)
            segments.append(SpeakerSegment(
                speakerId: currentSpeaker,
                startTime: currentTime,
                endTime: endTime,
                confidence: speakerInfo.confidence ?? 0.8
            ))
            currentTime = endTime
        }

        // Build speaker profiles
        let allSpeakers = diarizationService.getAllSpeakers()
        let profiles = allSpeakers.map { speaker in
            let speakerSegments = segments.filter { $0.speakerId == speaker.id }
            let totalTime = speakerSegments.reduce(0) { $0 + $1.duration }
            return SpeakerProfile(
                id: speaker.id,
                embedding: speaker.embedding,
                totalSpeakingTime: totalTime,
                segmentCount: speakerSegments.count,
                name: speaker.name
            )
        }

        // Store profiles
        profiles.forEach { speakerProfiles[$0.id] = $0 }

        // Create labeled transcription if provided
        var labeledTranscription: LabeledTranscription?
        if let transcription = input.transcription,
           let wordTimestamps = transcription.wordTimestamps {
            labeledTranscription = createLabeledTranscription(
                wordTimestamps: wordTimestamps,
                segments: segments
            )
        }

        let processingTime = Date().timeIntervalSince(startTime)

        let metadata = DiarizationMetadata(
            processingTime: processingTime,
            audioLength: totalDuration,
            speakerCount: profiles.count,
            method: diarizationConfiguration.modelId != nil ? "ml" : "energy"
        )

        return SpeakerDiarizationOutput(
            segments: segments,
            speakers: profiles,
            labeledTranscription: labeledTranscription,
            metadata: metadata
        )
    }

    /// Get stored speaker profile
    public func getSpeakerProfile(id: String) -> SpeakerProfile? {
        return speakerProfiles[id]
    }

    /// Reset speaker profiles
    public func resetProfiles() {
        speakerProfiles.removeAll()
        service?.reset()
    }

    /// Get service for compatibility
    public func getService() -> SpeakerDiarizationService? {
        return service
    }

    // MARK: - Cleanup

    public override func performCleanup() async throws {
        speakerProfiles.removeAll()
        service?.reset()
    }

    // MARK: - Private Helpers

    private func convertDataToFloatArray(_ data: Data) -> [Float] {
        // Simple conversion - real implementation would handle different audio formats
        let floatCount = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { bytes in
            Array(UnsafeBufferPointer<Float>(
                start: bytes.bindMemory(to: Float.self).baseAddress,
                count: floatCount
            ))
        }
    }

    private func createLabeledTranscription(
        wordTimestamps: [WordTimestamp],
        segments: [SpeakerSegment]
    ) -> LabeledTranscription {
        var labeledSegments: [LabeledTranscription.LabeledSegment] = []
        var currentText = ""
        var currentSpeaker = ""
        var segmentStart: TimeInterval = 0

        for word in wordTimestamps {
            // Find which speaker this word belongs to
            let speaker = segments.first { segment in
                word.startTime >= segment.startTime && word.endTime <= segment.endTime
            }?.speakerId ?? "unknown"

            if speaker != currentSpeaker && !currentText.isEmpty {
                // Save previous segment
                labeledSegments.append(LabeledTranscription.LabeledSegment(
                    speakerId: currentSpeaker,
                    text: currentText.trimmingCharacters(in: .whitespaces),
                    startTime: segmentStart,
                    endTime: word.startTime
                ))
                currentText = ""
                segmentStart = word.startTime
            }

            currentSpeaker = speaker
            if currentText.isEmpty {
                segmentStart = word.startTime
            }
            currentText += " " + word.word
        }

        // Add final segment
        if !currentText.isEmpty {
            labeledSegments.append(LabeledTranscription.LabeledSegment(
                speakerId: currentSpeaker,
                text: currentText.trimmingCharacters(in: .whitespaces),
                startTime: segmentStart,
                endTime: wordTimestamps.last?.endTime ?? 0
            ))
        }

        return LabeledTranscription(segments: labeledSegments)
    }
}

// MARK: - Compatibility Typealias
