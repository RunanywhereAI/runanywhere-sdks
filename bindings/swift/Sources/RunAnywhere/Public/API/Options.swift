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
    /// Schema the output must validate against, as raw JSON Schema text.
    public var schema: JsonSchema

    /// Reject output that does not validate instead of returning it raw.
    ///
    /// `RAStructuredOutputOptions.strictMode` was deleted outright
    /// (idl/structured_output.proto shrunk the message to
    /// `includeSchemaInPrompt` + a `schema`/`grammar`/`regex` oneof); this
    /// knob has no wire home anymore. Kept on the public struct for API
    /// stability but currently has no effect on the built proto — every
    /// generation is validated the same way regardless of this flag.
    public var strict: Bool = true

    /// Build a structured-output constraint.
    public init(schema: JsonSchema, strict: Bool = true) {
        self.schema = schema
        self.strict = strict
    }

    func toProto() -> RAStructuredOutputOptions {
        RAStructuredOutputOptions.defaults(schema: schema, includeSchemaInPrompt: true)
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
    public var maxOutputTokens = Int(RALLMGenerationOptions.defaults().maxOutputTokens)
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
    public var maxToolCalls: Int = 5

    /// Run matched tools automatically inside the generate call (the same flag
    /// as the tool-calling API's `autoExecute`). Defaults true so `generate`
    /// with registered tools executes them instead of leaking a raw tool call.
    public var autoExecute: Bool = true

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
        maxToolCalls: Int = 5
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
        // idl/llm_options.proto renamed repetition_penalty -> repeat_penalty
        // (industry name: llama.cpp / Ollama both spell it repeat_penalty).
        if let repetitionPenalty { proto.repeatPenalty = repetitionPenalty }
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
        var options = RAToolCallingOptions()
        options.tools = tools
        options.maxToolCalls = Int32(maxToolCalls)
        options.autoExecute = autoExecute
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

    /// Build the VLM request envelope. `RAVLMGenerationOptions` was deleted
    /// outright (idl/vlm_options.proto): its 11 sampling fields were
    /// name-for-name copies of `LLMGenerationOptions` with drifted
    /// defaults, so VLM now shares the exact same `toProto()` options this
    /// struct already builds for `llm`. `vision`/`images` carry the four
    /// genuinely vision-specific knobs and the image payload; neither has a
    /// public `LlmOptions` knob yet, so `vision` stays default.
    func toVLMRequest(prompt: String, images: [RAVLMImage]) -> RAVLMGenerationRequest {
        var request = RAVLMGenerationRequest()
        request.prompt = prompt
        request.images = images
        request.options = toProto()
        return request
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

    /// `translateToEnglish` was reserved off the wire outright
    /// (idl/stt_options.proto: "None were ever read by any backend") with
    /// no replacement. Kept on the public struct for API stability but
    /// currently has no effect on the built proto.
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
        // enableDiarization -> diarize (idl/stt_options.proto rename).
        proto.diarize = diarization
        // maxSpeakers -> speakersExpected (idl/stt_options.proto rename,
        // now presence-tracked optional int32).
        if let maxSpeakers { proto.speakersExpected = Int32(maxSpeakers) }
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
    public var sampleRate = Int(RATTSOptions.defaults().sampleRate)

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
    public var minSpeechMs = Int(RAVADOptions.defaults().minSpeechDurationMs)
    public var minSilenceMs = Int(RAVADOptions.defaults().minSilenceDurationMs)
    public var prefixPaddingMs = Int(RAVADOptions.defaults().prefixPaddingMs)

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

    /// `RADiffusionGenerationOptions.reportIntermediateImages` was deleted
    /// outright (idl/diffusion_options.proto) with no replacement. Kept on
    /// the public struct for API stability but currently has no effect on
    /// the built proto — `DiffusionProgress.intermediateImageData` is
    /// populated purely at the backend's discretion now.
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
        // mode/inputImage/inputImageWidth/inputImageHeight/
        // reportIntermediateImages were all deleted outright
        // (idl/diffusion_options.proto): mode is now INFERRED from field
        // presence alone (no image = text-to-image, image = image-to-image,
        // image + maskImage = inpainting), and there is no toggle left for
        // intermediate-image reporting.
        switch mode {
        case .generate:
            break
        case .inpaint(let input, let mask):
            let inputEncoded = try input.encodedImageBytes()
            let maskEncoded = try mask.encodedImageBytes()
            proto.image = inputEncoded.data
            proto.imageMediaType = inputEncoded.mediaType
            proto.maskImage = maskEncoded.data
            proto.maskImageMediaType = maskEncoded.mediaType
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
    public var endpointing = Endpointing()
    public var interruption = Interruption()

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
    /// Retrieval depth (not LLM sampling topK).
    public var retrievalTopK = Int(RARAGConfiguration.defaults().topK)
    public var chunkSize = Int(RARAGConfiguration.defaults().chunkSize)
    public var chunkOverlap = Int(RARAGConfiguration.defaults().chunkOverlap)
    public var similarityThreshold: Float?

    /// `RAGConfiguration.index_path`/`persist_index` were deleted outright
    /// (idl/rag.proto) with no replacement — vector-index persistence has no
    /// wire home anymore. Kept on the public struct for API stability but
    /// currently has no effect on the built proto.
    public var persistPath: String?

    /// Deprecated alias for `retrievalTopK`.
    @available(*, deprecated, renamed: "retrievalTopK")
    public var topK: Int {
        get { retrievalTopK }
        set { retrievalTopK = newValue }
    }

    /// Build RAG session configuration.
    public init(
        retrievalTopK: Int = Int(RARAGConfiguration.defaults().topK),
        chunkSize: Int = Int(RARAGConfiguration.defaults().chunkSize),
        chunkOverlap: Int = Int(RARAGConfiguration.defaults().chunkOverlap),
        similarityThreshold: Float? = nil,
        persistPath: String? = nil,
        topK: Int? = nil
    ) {
        self.retrievalTopK = topK ?? retrievalTopK
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.similarityThreshold = similarityThreshold
        self.persistPath = persistPath
    }

    func toProto() -> RARAGConfiguration {
        var proto = RARAGConfiguration.defaults()
        proto.topK = Int32(retrievalTopK)
        proto.chunkSize = Int32(chunkSize)
        proto.chunkOverlap = Int32(chunkOverlap)
        // similarityThreshold -> scoreThreshold (idl/rag.proto rename).
        if let similarityThreshold { proto.scoreThreshold = similarityThreshold }
        return proto
    }
}

// MARK: - LoadOptions

/// Placement knobs applied when a model is loaded, not per request.
public struct LoadOptions: Sendable {
    /// Ordered backend preferences (LiteRT/ExecuTorch-aligned).
    public var backendPreferences: [BackendPreference]
    /// Accelerator class preference.
    public var accelerator: AcceleratorPolicy?
    public var contextLength: Int?
    public var threads: Int?
    public var forceReload: Bool

    /// Deprecated adapter: maps into `backendPreferences`.
    @available(*, deprecated, message: "Use backendPreferences instead")
    public var framework: InferenceFramework? {
        didSet {
            if let framework, backendPreferences.isEmpty {
                backendPreferences = [BackendPreference(backend: framework)]
            }
        }
    }

    /// Deprecated adapter: maps into `accelerator`.
    @available(*, deprecated, message: "Use accelerator instead")
    public var useGpu: Bool? {
        didSet {
            if let useGpu, accelerator == nil {
                accelerator = useGpu ? .gpu : .cpu
            }
        }
    }

    /// Build load options.
    public init(
        backendPreferences: [BackendPreference] = [],
        accelerator: AcceleratorPolicy? = nil,
        contextLength: Int? = nil,
        threads: Int? = nil,
        forceReload: Bool = false,
        framework: InferenceFramework? = nil,
        useGpu: Bool? = nil
    ) {
        self.backendPreferences = backendPreferences
        self.accelerator = accelerator
        self.contextLength = contextLength
        self.threads = threads
        self.forceReload = forceReload
        self.framework = framework
        self.useGpu = useGpu
        if let framework, self.backendPreferences.isEmpty {
            self.backendPreferences = [BackendPreference(backend: framework)]
        }
        if let useGpu, self.accelerator == nil {
            self.accelerator = useGpu ? .gpu : .cpu
        }
    }
}
