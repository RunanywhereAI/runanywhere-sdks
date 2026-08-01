//
//  Options.swift
//  RunAnywhere SDK
//
//  One options struct per modality, matching the v3 public API spec. Every
//  field is optional; the defaults are the cross-SDK contract. Each struct
//  lowers itself onto the canonical generated proto options so commons stays
//  the only place that interprets them.
//

import Foundation

// MARK: - Shared enums

/// Whether the model is allowed to emit reasoning tokens.
public enum ReasoningMode: Sendable {
    case on
    case off
}

/// How the model may pick tools for a generation.
public enum ToolChoice: Sendable {
    case auto
    case none
    case required
    case forced(name: String)
}

/// How token vectors collapse into one sentence vector.
public enum PoolingMode: Sendable {
    case mean
    case cls
    case last
}

/// Whether an image request paints from scratch or repaints a masked region.
public enum ImageMode: Sendable {
    case generate
    case inpaint(input: ImageInput, mask: ImageInput)
}

// MARK: - ReasoningOptions

/// Control the model's thinking phase.
public struct ReasoningOptions: Sendable {
    /// Suppress thinking entirely with `.off`.
    public var mode: ReasoningMode = .on

    /// Stream thought tokens to the caller alongside the answer.
    public var includeInOutput: Bool = false

    /// Thinking tag name, without angle brackets — `"think"` yields
    /// `<think>` / `</think>`. Leave `nil` to use the model's own tags.
    public var pattern: String?

    /// Build reasoning options.
    public init(mode: ReasoningMode = .on, includeInOutput: Bool = false, pattern: String? = nil) {
        self.mode = mode
        self.includeInOutput = includeInOutput
        self.pattern = pattern
    }

    func toProto() -> RAReasoningOptions {
        var proto = RAReasoningOptions()
        proto.mode = mode == .on ? .on : .off
        proto.includeInOutput = includeInOutput
        if let pattern, !pattern.isEmpty {
            var tags = RAThinkingTagPattern()
            tags.openTag = "<\(pattern)>"
            tags.closeTag = "</\(pattern)>"
            proto.pattern = tags
        }
        return proto
    }
}

// MARK: - StructuredOutput

/// Force generation to satisfy a JSON schema.
public struct StructuredOutput: Sendable {
    /// Schema the output must validate against.
    public var schema: JsonSchema

    /// Reject output that does not validate instead of returning it raw.
    public var strict: Bool = true

    /// Build a structured-output constraint.
    public init(schema: JsonSchema, strict: Bool = true) {
        self.schema = schema
        self.strict = strict
    }

    func toProto() -> RAStructuredOutputOptions {
        RAStructuredOutputOptions.defaults(schema: schema, includeSchemaInPrompt: true, strict: strict)
    }
}

// MARK: - LlmOptions

/// Sampling, prompting, and tool knobs for one text or vision generation.
///
/// The numeric defaults are read from the generated IDL defaults rather than
/// hand-copied, so a change in `idl/llm_options.proto` moves every SDK at once.
public struct LlmOptions: Sendable {
    /// Model slug; an absent model auto-loads, downloading if needed.
    public var model: String?
    public var maxOutputTokens: Int = Int(RALLMGenerationOptions.defaults().maxOutputTokens)
    public var temperature: Float = RALLMGenerationOptions.defaults().temperature
    public var topP: Float = RALLMGenerationOptions.defaults().topP
    public var topK: Int?
    public var minP: Float?
    public var frequencyPenalty: Float?
    public var presencePenalty: Float?
    public var repetitionPenalty: Float?
    public var seed: Int?
    public var stopSequences: [String] = []
    public var systemPrompt: String?
    public var reasoning: ReasoningOptions?
    public var structuredOutput: StructuredOutput?

    /// Tools offered for this call; empty uses the `llm.tools` registry.
    public var tools: [ToolDefinition] = []
    public var toolChoice: ToolChoice = .auto
    public var maxToolCalls: Int = Int(RAToolCallingOptions.defaults().maxToolCalls)

    /// Build generation options; every field defaults to the IDL value.
    public init(
        model: String? = nil,
        maxOutputTokens: Int = Int(RALLMGenerationOptions.defaults().maxOutputTokens),
        temperature: Float = RALLMGenerationOptions.defaults().temperature,
        topP: Float = RALLMGenerationOptions.defaults().topP,
        topK: Int? = nil,
        minP: Float? = nil,
        frequencyPenalty: Float? = nil,
        presencePenalty: Float? = nil,
        repetitionPenalty: Float? = nil,
        seed: Int? = nil,
        stopSequences: [String] = [],
        systemPrompt: String? = nil,
        reasoning: ReasoningOptions? = nil,
        structuredOutput: StructuredOutput? = nil,
        tools: [ToolDefinition] = [],
        toolChoice: ToolChoice = .auto,
        maxToolCalls: Int = Int(RAToolCallingOptions.defaults().maxToolCalls)
    ) {
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.repetitionPenalty = repetitionPenalty
        self.seed = seed
        self.stopSequences = stopSequences
        self.systemPrompt = systemPrompt
        self.reasoning = reasoning
        self.structuredOutput = structuredOutput
        self.tools = tools
        self.toolChoice = toolChoice
        self.maxToolCalls = maxToolCalls
    }

    func toProto() -> RALLMGenerationOptions {
        var proto = RALLMGenerationOptions.defaults()
        proto.maxOutputTokens = Int32(maxOutputTokens)
        proto.temperature = temperature
        proto.topP = topP
        if let topK { proto.topK = Int32(topK) }
        if let minP { proto.minP = minP }
        if let frequencyPenalty { proto.frequencyPenalty = frequencyPenalty }
        if let presencePenalty { proto.presencePenalty = presencePenalty }
        if let repetitionPenalty { proto.repetitionPenalty = repetitionPenalty }
        if let seed { proto.seed = Int64(seed) }
        proto.stopSequences = stopSequences
        if let systemPrompt { proto.systemPrompt = systemPrompt }
        if let reasoning { proto.reasoning = reasoning.toProto() }
        if let structuredOutput { proto.structuredOutput = structuredOutput.toProto() }
        proto.toolCalling = toolCallingProto()
        return proto
    }

    /// Tool configuration is only meaningful when tools are in play; the
    /// registry contents are merged in by the `llm` namespace.
    func toolCallingProto() -> RAToolCallingOptions {
        var options = RAToolCallingOptions.defaults()
        options.tools = tools
        options.maxToolCalls = Int32(maxToolCalls)
        switch toolChoice {
        case .auto:
            options.toolChoice = .auto
        case .none:
            options.toolChoice = RAToolChoiceMode.none
        case .required:
            options.toolChoice = .required
        case .forced(let name):
            options.toolChoice = .specific
            options.forcedToolName = name
        }
        return options
    }

    /// VLM shares this options shape; lower onto the VLM proto instead.
    func toVLMProto(prompt: String) -> RAVLMGenerationOptions {
        var proto = RAVLMGenerationOptions.defaults()
        proto.prompt = prompt
        proto.maxOutputTokens = Int32(maxOutputTokens)
        proto.temperature = temperature
        proto.topP = topP
        if let topK { proto.topK = Int32(topK) }
        if let minP { proto.minP = minP }
        if let repetitionPenalty { proto.repetitionPenalty = repetitionPenalty }
        if let seed { proto.seed = Int64(seed) }
        proto.stopSequences = stopSequences
        if let systemPrompt { proto.systemPrompt = systemPrompt }
        if let reasoning { proto.reasoning = reasoning.toProto() }
        return proto
    }
}

// MARK: - SttOptions

/// Transcription knobs for one audio input or stream.
///
/// Defaults come from the generated IDL defaults, not hand-copied constants.
public struct SttOptions: Sendable {
    /// BCP-47 tag; `nil` auto-detects.
    public var language: String?
    public var punctuation: Bool = RASTTOptions.defaults().enablePunctuation
    public var wordTimestamps: Bool = RASTTOptions.defaults().enableWordTimestamps
    public var diarization: Bool = false
    public var maxSpeakers: Int?
    public var translateToEnglish: Bool = false

    /// Build transcription options.
    public init(
        language: String? = nil,
        punctuation: Bool = RASTTOptions.defaults().enablePunctuation,
        wordTimestamps: Bool = RASTTOptions.defaults().enableWordTimestamps,
        diarization: Bool = false,
        maxSpeakers: Int? = nil,
        translateToEnglish: Bool = false
    ) {
        self.language = language
        self.punctuation = punctuation
        self.wordTimestamps = wordTimestamps
        self.diarization = diarization
        self.maxSpeakers = maxSpeakers
        self.translateToEnglish = translateToEnglish
    }

    func toProto() -> RASTTOptions {
        var proto = RASTTOptions.defaults()
        if let language { proto.language = language }
        proto.enablePunctuation = punctuation
        proto.enableWordTimestamps = wordTimestamps
        proto.enableDiarization = diarization
        if let maxSpeakers { proto.maxSpeakers = Int32(maxSpeakers) }
        proto.translateToEnglish = translateToEnglish
        return proto
    }
}

// MARK: - TtsOptions

/// Voice and audio-format knobs for one synthesis.
///
/// Defaults come from the generated IDL defaults, not hand-copied constants.
public struct TtsOptions: Sendable {
    public var voice: String?
    public var language: String = RATTSOptions.defaults().languageCode
    public var speed: Float = RATTSOptions.defaults().speed
    public var pitch: Float = RATTSOptions.defaults().pitch
    public var format: RAAudioFormat = RATTSOptions.defaults().audioFormat
    public var sampleRate: Int = Int(RATTSOptions.defaults().sampleRate)

    /// Build synthesis options.
    public init(
        voice: String? = nil,
        language: String = RATTSOptions.defaults().languageCode,
        speed: Float = RATTSOptions.defaults().speed,
        pitch: Float = RATTSOptions.defaults().pitch,
        format: RAAudioFormat = RATTSOptions.defaults().audioFormat,
        sampleRate: Int = Int(RATTSOptions.defaults().sampleRate)
    ) {
        self.voice = voice
        self.language = language
        self.speed = speed
        self.pitch = pitch
        self.format = format
        self.sampleRate = sampleRate
    }

    func toProto() -> RATTSOptions {
        var proto = RATTSOptions.defaults()
        if let voice { proto.voice = voice }
        proto.languageCode = language
        proto.speed = speed
        proto.pitch = pitch
        proto.audioFormat = format
        proto.sampleRate = Int32(sampleRate)
        return proto
    }
}

// MARK: - VadOptions

/// Speech-boundary sensitivity for one detection or stream.
///
/// Defaults come from the generated IDL defaults, not hand-copied constants.
public struct VadOptions: Sendable {
    /// `nil` uses the model's calibrated default.
    public var activationThreshold: Float?
    public var minSpeechMs: Int = Int(RAVADOptions.defaults().minSpeechDurationMs)
    public var minSilenceMs: Int = Int(RAVADOptions.defaults().minSilenceDurationMs)
    public var prefixPaddingMs: Int = Int(RAVADOptions.defaults().prefixPaddingMs)

    /// Build detection options.
    public init(
        activationThreshold: Float? = nil,
        minSpeechMs: Int = Int(RAVADOptions.defaults().minSpeechDurationMs),
        minSilenceMs: Int = Int(RAVADOptions.defaults().minSilenceDurationMs),
        prefixPaddingMs: Int = Int(RAVADOptions.defaults().prefixPaddingMs)
    ) {
        self.activationThreshold = activationThreshold
        self.minSpeechMs = minSpeechMs
        self.minSilenceMs = minSilenceMs
        self.prefixPaddingMs = prefixPaddingMs
    }

    func toProto() -> RAVADOptions {
        var proto = RAVADOptions.defaults()
        if let activationThreshold { proto.activationThreshold = activationThreshold }
        proto.minSpeechDurationMs = Int32(minSpeechMs)
        proto.minSilenceDurationMs = Int32(minSilenceMs)
        proto.prefixPaddingMs = Int32(prefixPaddingMs)
        return proto
    }
}

// MARK: - EmbedOptions

/// Normalization and pooling for one embedding batch.
public struct EmbedOptions: Sendable {
    /// Apply L2 normalization to each embedding vector.
    public var normalize: Bool = true
    public var pooling: PoolingMode = .mean

    /// Build embedding options.
    public init(normalize: Bool = true, pooling: PoolingMode = .mean) {
        self.normalize = normalize
        self.pooling = pooling
    }

    func toProto() -> RAEmbeddingsOptions {
        var proto = RAEmbeddingsOptions.defaults()
        proto.normalize = normalize
        switch pooling {
        case .mean: proto.pooling = .mean
        case .cls: proto.pooling = .cls
        case .last: proto.pooling = .last
        }
        return proto
    }
}

// MARK: - ImageOptions

/// Diffusion knobs for one image request.
public struct ImageOptions: Sendable {
    public var negativePrompt: String?
    public var width: Int?
    public var height: Int?
    public var steps: Int?
    public var guidanceScale: Float?
    public var seed: Int?
    public var mode: ImageMode = .generate

    /// Emit intermediate step images on the event stream.
    public var reportPartials: Bool = false

    /// Build image-generation options.
    public init(
        negativePrompt: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        steps: Int? = nil,
        guidanceScale: Float? = nil,
        seed: Int? = nil,
        mode: ImageMode = .generate,
        reportPartials: Bool = false
    ) {
        self.negativePrompt = negativePrompt
        self.width = width
        self.height = height
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.mode = mode
        self.reportPartials = reportPartials
    }

    func toProto(prompt: String) throws -> RADiffusionGenerationOptions {
        var proto = RADiffusionGenerationOptions.defaults()
        proto.prompt = prompt
        if let negativePrompt { proto.negativePrompt = negativePrompt }
        if let width { proto.width = Int32(width) }
        if let height { proto.height = Int32(height) }
        if let steps { proto.steps = Int32(steps) }
        if let guidanceScale { proto.guidanceScale = guidanceScale }
        if let seed { proto.seed = Int64(seed) }
        proto.reportIntermediateImages = reportPartials
        switch mode {
        case .generate:
            proto.mode = .textToImage
        case .inpaint(let input, let mask):
            proto.mode = .inpainting
            let inputPixels = try input.rawPixels()
            let maskPixels = try mask.rawPixels()
            proto.inputImage = inputPixels.data
            proto.inputImageWidth = Int32(inputPixels.width)
            proto.inputImageHeight = Int32(inputPixels.height)
            proto.maskImage = maskPixels.data
        }
        return proto
    }
}

// MARK: - DiarizationOptions

/// Speaker-clustering knobs for one diarization run.
public struct DiarizationOptions: Sendable {
    public var threshold: Float?
    public var minimumDurationMs: Int?
    public var mergeGapMs: Int?

    /// Build diarization options.
    public init(threshold: Float? = nil, minimumDurationMs: Int? = nil, mergeGapMs: Int? = nil) {
        self.threshold = threshold
        self.minimumDurationMs = minimumDurationMs
        self.mergeGapMs = mergeGapMs
    }

    func toProto(audio: AudioInput) -> RADiarizationOptions {
        toProto(
            sampleRate: audio.sampleRate,
            channels: audio.channels,
            encoding: audio.diarizationEncoding
        )
    }

    func toProto(
        sampleRate: Int,
        channels: Int,
        encoding: RAAudioEncoding
    ) -> RADiarizationOptions {
        var proto = RADiarizationOptions.defaults()
        if sampleRate > 0 { proto.sampleRate = Int32(sampleRate) }
        if channels > 0 { proto.channels = Int32(channels) }
        proto.encoding = encoding
        if let threshold { proto.threshold = threshold }
        if let minimumDurationMs { proto.minimumDurationMs = Int64(minimumDurationMs) }
        if let mergeGapMs { proto.mergeGapMs = Int64(mergeGapMs) }
        return proto
    }
}

// MARK: - SegmentationOptions

/// Segmentation output knobs for one image.
public struct SegmentationOptions: Sendable {
    /// Also return an RGBA overlay useful for debugging.
    public var includeDiagnosticImage: Bool = false

    /// Build segmentation options.
    public init(includeDiagnosticImage: Bool = false) {
        self.includeDiagnosticImage = includeDiagnosticImage
    }

    func toProto() -> RASegmentationOptions {
        var proto = RASegmentationOptions()
        proto.includeDiagnosticRgba = includeDiagnosticImage
        return proto
    }
}

// MARK: - TurnHandlingOptions

/// When the agent decides the user stopped talking.
public struct Endpointing: Sendable {
    public var minDelayMs: Int = 500
    public var maxDelayMs: Int = 3000

    /// Build endpointing timings.
    public init(minDelayMs: Int = 500, maxDelayMs: Int = 3000) {
        self.minDelayMs = minDelayMs
        self.maxDelayMs = maxDelayMs
    }
}

/// Whether the user can talk over the agent.
public struct Interruption: Sendable {
    public var enabled: Bool = true
    public var minDurationMs: Int = 500

    /// Build interruption behaviour.
    public init(enabled: Bool = true, minDurationMs: Int = 500) {
        self.enabled = enabled
        self.minDurationMs = minDurationMs
    }
}

/// Turn-taking behaviour for a voice session.
public struct TurnHandlingOptions: Sendable {
    public var endpointing: Endpointing = Endpointing()
    public var interruption: Interruption = Interruption()

    /// Build turn-handling options.
    public init(endpointing: Endpointing = Endpointing(), interruption: Interruption = Interruption()) {
        self.endpointing = endpointing
        self.interruption = interruption
    }
}

// MARK: - RagConfig

/// Chunking, retrieval, and persistence settings for one RAG session.
///
/// Defaults come from the generated IDL defaults, not hand-copied constants.
public struct RagConfig: Sendable {
    public var topK: Int = Int(RARAGConfiguration.defaults().topK)
    public var chunkSize: Int = Int(RARAGConfiguration.defaults().chunkSize)
    public var chunkOverlap: Int = Int(RARAGConfiguration.defaults().chunkOverlap)
    public var similarityThreshold: Float?
    public var persistPath: String?

    /// Build RAG session configuration.
    public init(
        topK: Int = Int(RARAGConfiguration.defaults().topK),
        chunkSize: Int = Int(RARAGConfiguration.defaults().chunkSize),
        chunkOverlap: Int = Int(RARAGConfiguration.defaults().chunkOverlap),
        similarityThreshold: Float? = nil,
        persistPath: String? = nil
    ) {
        self.topK = topK
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.similarityThreshold = similarityThreshold
        self.persistPath = persistPath
    }

    func toProto() -> RARAGConfiguration {
        var proto = RARAGConfiguration.defaults()
        proto.topK = Int32(topK)
        proto.chunkSize = Int32(chunkSize)
        proto.chunkOverlap = Int32(chunkOverlap)
        if let similarityThreshold { proto.similarityThreshold = similarityThreshold }
        if let persistPath {
            proto.indexPath = persistPath
            proto.persistIndex = true
        }
        return proto
    }
}

// MARK: - LoadOptions

/// Placement knobs applied when a model is loaded, not per request.
public struct LoadOptions: Sendable {
    /// Engine pin honoured at load time only.
    public var framework: InferenceFramework?
    public var contextLength: Int?
    public var threads: Int?
    public var useGpu: Bool?

    /// Build load options.
    public init(
        framework: InferenceFramework? = nil,
        contextLength: Int? = nil,
        threads: Int? = nil,
        useGpu: Bool? = nil
    ) {
        self.framework = framework
        self.contextLength = contextLength
        self.threads = threads
        self.useGpu = useGpu
    }
}
