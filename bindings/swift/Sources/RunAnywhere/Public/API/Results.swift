//
//  Results.swift
//  RunAnywhere SDK
//
//  Uniform result types for the v3 public API. Every generation result carries
//  the same metrics block so no caller computes throughput itself, and no
//  result carries a success flag or an error message — failures throw.
//

import CoreGraphics
import Foundation

// MARK: - FinishReason

/// Why generation stopped.
public enum FinishReason: Sendable {
    case stop
    case length
    case toolCalls
    case cancelled
    case error
    /// Producer gave no signal (`FINISH_REASON_UNSPECIFIED`) or an unrecognized value.
    case unknown

    /// Decode the backend's finish-reason label (VLM/voice-agent paths,
    /// which still carry finishReason as a free-form String).
    static func parse(_ raw: String) -> FinishReason {
        switch raw.lowercased() {
        case "length", "max_tokens", "max_output_tokens": return .length
        case "tool_calls", "toolcalls", "tool_call": return .toolCalls
        case "cancelled", "canceled": return .cancelled
        case "error": return .error
        case "", "unspecified", "unknown": return .unknown
        default: return .stop
        }
    }

    /// Decode the canonical `RAFinishReason` enum (LLM generate/stream/tool path).
    /// Never invents `.toolCalls` / `.stop` from local tool-call counts.
    init(proto: RAFinishReason) {
        switch proto {
        case .stop, .stopSequence: self = .stop
        case .length, .contextOverflow: self = .length
        case .toolCalls: self = .toolCalls
        case .cancelled: self = .cancelled
        case .error: self = .error
        case .unspecified: self = .unknown
        case .UNRECOGNIZED: self = .unknown
        }
    }
}

// MARK: - GenerationResult

/// The finished output of one text or vision generation.
public struct GenerationResult: Sendable {
    public let text: String
    public let thinkingText: String?
    public let toolCalls: [ToolCall]
    public let finishReason: FinishReason
    public let inputTokens: Int
    public let outputTokens: Int
    public let timeToFirstTokenMs: Int64
    public let tokensPerSecond: Float
    public let requestId: String
    public let model: String

    init(
        text: String,
        thinkingText: String?,
        toolCalls: [ToolCall],
        finishReason: FinishReason,
        inputTokens: Int,
        outputTokens: Int,
        timeToFirstTokenMs: Int64,
        tokensPerSecond: Float,
        requestId: String,
        model: String
    ) {
        self.text = text
        self.thinkingText = thinkingText
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.tokensPerSecond = tokensPerSecond
        self.requestId = requestId
        self.model = model
    }

    init(proto: RALLMGenerationResult, requestId: String) {
        self.init(
            text: proto.text,
            thinkingText: proto.hasThinkingContent && !proto.thinkingContent.isEmpty ? proto.thinkingContent : nil,
            toolCalls: proto.toolCalls,
            finishReason: FinishReason(proto: proto.finishReason),
            inputTokens: Int(proto.usage.inputTokens),
            outputTokens: Int(proto.usage.outputTokens),
            timeToFirstTokenMs: proto.usage.ttftMs,
            tokensPerSecond: Float(proto.usage.decodeTokensPerSecond),
            requestId: requestId,
            model: proto.modelUsed
        )
    }

    // LLMStreamFinalResult was deleted outright (idl/llm_service.proto): the
    // stream now terminates with the same RALLMGenerationResult the unary
    // call returns (RALLMStreamEvent.result). This overload takes the
    // caller's known `model` instead of `proto.modelUsed`, which the
    // streaming terminal event does not reliably populate.
    init(proto: RALLMGenerationResult, requestId: String, model: String) {
        self.init(
            text: proto.text,
            thinkingText: proto.hasThinkingContent && !proto.thinkingContent.isEmpty ? proto.thinkingContent : nil,
            toolCalls: proto.toolCalls,
            finishReason: FinishReason(proto: proto.finishReason),
            inputTokens: Int(proto.usage.inputTokens),
            outputTokens: Int(proto.usage.outputTokens),
            timeToFirstTokenMs: proto.usage.ttftMs,
            tokensPerSecond: Float(proto.usage.decodeTokensPerSecond),
            requestId: requestId,
            model: model
        )
    }

    init(proto: RAVLMResult, requestId: String, model: String) {
        self.init(
            text: proto.text,
            thinkingText: nil,
            toolCalls: [],
            finishReason: FinishReason.parse(proto.finishReason),
            inputTokens: Int(proto.usage.inputTokens),
            outputTokens: Int(proto.usage.outputTokens),
            timeToFirstTokenMs: proto.usage.ttftMs,
            tokensPerSecond: Float(proto.usage.decodeTokensPerSecond),
            requestId: requestId,
            model: model
        )
    }

    init(proto: RAToolCallingResult, requestId: String, model: String) {
        self.init(
            text: proto.text,
            thinkingText: proto.hasThinkingContent && !proto.thinkingContent.isEmpty ? proto.thinkingContent : nil,
            toolCalls: proto.toolCalls,
            finishReason: FinishReason(proto: proto.finishReason),
            inputTokens: Int(proto.usage.inputTokens),
            outputTokens: Int(proto.usage.outputTokens),
            timeToFirstTokenMs: proto.usage.ttftMs,
            tokensPerSecond: Float(proto.usage.decodeTokensPerSecond),
            requestId: requestId,
            model: model
        )
    }
}

// MARK: - StructuredResult

/// A generation whose output was parsed against a JSON schema.
public struct StructuredResult: Sendable {
    /// Parsed JSON payload as UTF-8 bytes.
    public let value: Data
    public let raw: String
    public let valid: Bool
    public let mode: StructuredEnforcementMode

    public let inputTokens: Int
    public let outputTokens: Int
    public let timeToFirstTokenMs: Int64
    public let tokensPerSecond: Float
    public let requestId: String
    public let model: String

    init(
        proto: RAStructuredOutputResult,
        generation: GenerationResult,
        mode: StructuredEnforcementMode = .validationOnly
    ) {
        // RAStructuredOutputResult.json (String) replaced the deleted
        // parsedJson (Data) field (idl/structured_output.proto).
        self.value = Data(proto.json.utf8)
        self.raw = proto.hasRawText ? proto.rawText : generation.text
        self.valid = proto.hasValidation ? proto.validation.isValid : false
        self.mode = mode
        self.inputTokens = generation.inputTokens
        self.outputTokens = generation.outputTokens
        self.timeToFirstTokenMs = generation.timeToFirstTokenMs
        self.tokensPerSecond = generation.tokensPerSecond
        self.requestId = generation.requestId
        self.model = generation.model
    }

    /// Decode `value` into a `Decodable` type.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: value)
    }
}

// MARK: - Transcription

/// One word in a transcript, with its span and speaker.
public struct Word: Sendable {
    public let text: String
    public let startMs: Int64
    public let endMs: Int64
    public let confidence: Float
    public let speakerId: String?

    init(proto: RAWordTimestamp) {
        self.text = proto.word
        self.startMs = Int64(proto.startMs)
        self.endMs = Int64(proto.endMs)
        self.confidence = proto.confidence
        self.speakerId = proto.hasSpeakerID && !proto.speakerID.isEmpty ? proto.speakerID : nil
    }
}

/// The finished transcript of one audio input.
public struct Transcription: Sendable {
    public let text: String
    public let language: String?
    public let confidence: Float
    public let words: [Word]
    public let durationMs: Int64

    init(proto: RASTTOutput) {
        self.text = proto.text
        self.language = proto.hasLanguage && !proto.language.isEmpty ? proto.language : nil
        self.confidence = proto.confidence
        self.words = proto.words.map(Word.init(proto:))
        self.durationMs = Int64(proto.durationMs)
    }
}

// MARK: - Audio

/// Synthesized audio ready to play or persist.
public struct Audio: Sendable {
    public let data: Data
    public let sampleRate: Int
    public let format: RAAudioFormat
    public let durationMs: Int64

    init(proto: RATTSOutput) {
        self.data = proto.audioData
        self.sampleRate = Int(proto.sampleRate)
        self.format = proto.audioFormat
        self.durationMs = Int64(proto.durationMs)
    }
}

/// One slice of a streaming synthesis.
public struct AudioChunk: Sendable {
    public let data: Data
    public let index: Int
    public let isFinal: Bool

    init(proto: RATTSOutput) {
        self.data = proto.audioData
        self.index = Int(proto.chunkIndex)
        self.isFinal = proto.isFinal
    }
}

// MARK: - VadResult

/// A detected span of speech.
public struct Segment: Sendable {
    public let startMs: Int64
    public let endMs: Int64
}

/// Whether the supplied audio contains speech.
public struct VadResult: Sendable {
    public let isSpeech: Bool
    public let probability: Float
    public let segments: [Segment]

    // RAVADResult.confidence/startTimeMs/endTimeMs were deleted outright
    // (idl/vad_options.proto): confidence is renamed probability, and the
    // start/end pair has no replacement — the result now only carries
    // timestampMs (frame start) + durationMs (frame length). Derive the one
    // segment this frame represents from that pair instead of a span.
    init(proto: RAVADResult) {
        self.isSpeech = proto.isSpeech
        self.probability = proto.probability
        if proto.isSpeech, proto.durationMs > 0 {
            self.segments = [Segment(
                startMs: proto.timestampMs,
                endMs: proto.timestampMs + Int64(proto.durationMs)
            )]
        } else {
            self.segments = []
        }
    }
}

// MARK: - Embedding / RankedResult

/// One embedding vector, tagged with its position in the input batch.
public struct Embedding: Sendable {
    public let index: Int
    public let vector: [Float]

    init(proto: RAEmbeddingVector, fallbackIndex: Int) {
        self.index = proto.inputIndex > 0 ? Int(proto.inputIndex) : fallbackIndex
        self.vector = proto.values
    }
}

/// A rerank score pointing back at a document by index.
public struct RankedResult: Sendable {
    public let index: Int
    public let relevanceScore: Float

    init(proto: RARerankScoredItem) {
        self.index = Int(proto.index)
        self.relevanceScore = proto.relevanceScore
    }
}

// MARK: - ImageResult

/// One generated image.
public struct ImageData: Sendable {
    public let data: Data
    public let width: Int
    public let height: Int
}

/// The finished output of one image request.
public struct ImageResult: Sendable {
    public let images: [ImageData]
    public let seed: Int64
    public let steps: Int

    // idl/diffusion_options.proto reshaped DiffusionResult from a flat
    // width/height/imageData/batchImages/seedUsed quintuple into
    // `repeated DiffusionImage images` (each carrying its own
    // data/width/height/seedUsed/mediaType) + totalTimeMs. `seed` surfaces
    // the first image's seed for backward-compatible single-image callers.
    init(proto: RADiffusionResult, requestedSteps: Int) {
        self.images = proto.images.map {
            ImageData(data: $0.data, width: Int($0.width), height: Int($0.height))
        }
        self.seed = proto.images.first?.seedUsed ?? 0
        self.steps = requestedSteps
    }
}

// MARK: - DiarizationResult

/// One speaker turn inside diarized audio.
public struct SpeakerSegment: Sendable {
    public let speakerId: String
    public let startMs: Int64
    public let endMs: Int64

    init(proto: RADiarizationSegment) {
        self.speakerId = proto.speakerID.isEmpty ? "speaker_\(proto.speakerIndex)" : proto.speakerID
        self.startMs = proto.startMs
        self.endMs = proto.endMs
    }
}

/// Who spoke when.
public struct DiarizationResult: Sendable {
    public let segments: [SpeakerSegment]
    public let speakerCount: Int

    init(proto: RADiarizationResult) {
        self.segments = proto.segments.map(SpeakerSegment.init(proto:))
        self.speakerCount = Int(proto.speakerCount)
    }
}

// MARK: - SegmentationResult

/// One class present in a segmentation mask.
public struct ClassInfo: Sendable {
    public let classId: Int
    public let label: String
    public let pixelCount: Int
    public let fraction: Float

    // Commons owns SegmentationClassSummary.fraction (idl tag 5).
    init(proto: RASegmentationClassSummary) {
        self.classId = Int(proto.classID)
        self.label = proto.label
        self.pixelCount = Int(proto.pixelCount)
        self.fraction = proto.fraction
    }
}

/// A per-pixel class mask plus the classes it contains.
public struct SegmentationResult: Sendable {
    /// Little-endian UInt16 class ids, one per pixel, row-major.
    public let classMask: Data
    public let width: Int
    public let height: Int
    public let classes: [ClassInfo]

    init(proto: RASegmentationResult) {
        self.classMask = proto.classMaskU16Le
        self.width = Int(proto.width)
        self.height = Int(proto.height)
        self.classes = proto.classSummaries.map { ClassInfo(proto: $0) }
    }
}

// MARK: - OCRPageResult

/// One text region read off a page.
public struct OCRRegion: Sendable {
    public let text: String
    /// Mean per-character confidence in 0...1, or nil when the engine reports
    /// none. Deliberately optional rather than 0 — a model that does not score
    /// its output is not a model that scored it zero.
    public let confidence: Float?
    /// Four corner points in SOURCE-image pixels, clockwise from top-left.
    /// Detectors in this family emit rotated boxes, so this is a quad and not
    /// a `CGRect`; `boundingBox` computes the axis-aligned hull when that is
    /// all a caller needs.
    public let quad: [CGPoint]

    init(proto: RAOCRRegion) {
        self.text = proto.text
        self.confidence = proto.hasConfidence ? proto.confidence : nil
        self.quad = [
            CGPoint(x: CGFloat(proto.quad.x0), y: CGFloat(proto.quad.y0)),
            CGPoint(x: CGFloat(proto.quad.x1), y: CGFloat(proto.quad.y1)),
            CGPoint(x: CGFloat(proto.quad.x2), y: CGFloat(proto.quad.y2)),
            CGPoint(x: CGFloat(proto.quad.x3), y: CGFloat(proto.quad.y3))
        ]
    }

    /// The axis-aligned hull of `quad`, for callers that only need a rect.
    public var boundingBox: CGRect {
        guard let first = quad.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in quad.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Everything read off one page.
public struct OCRPageResult: Sendable {
    public let regions: [OCRRegion]
    public let processingTimeMs: Int
    public let modelId: String
    /// Whether the loaded model can also serve `recognizeLine`. False for the
    /// detector-coupled families, whose recognizer consumes the detector's
    /// feature map rather than pixels.
    public let supportsLineRecognition: Bool

    init(proto: RAOCRResult) {
        self.regions = proto.regions.map { OCRRegion(proto: $0) }
        self.processingTimeMs = Int(proto.processingTimeMs)
        self.modelId = proto.modelID
        self.supportsLineRecognition = proto.supportsLineRecognition
    }

    /// Region texts joined in the order the detector returned them.
    public var text: String { regions.map(\.text).joined(separator: "\n") }
}

// MARK: - RAG results

/// One retrieved chunk backing a RAG answer.
public struct Match: Sendable {
    public let text: String
    public let score: Float
    public let metadata: [String: String]

    init(proto: RARAGSearchResult) {
        self.text = proto.text
        self.score = proto.score
        self.metadata = proto.metadata
    }
}

/// A grounded answer plus the chunks it came from.
public struct RagResult: Sendable {
    public let answer: String
    public let sources: [Match]

    public let inputTokens: Int
    public let outputTokens: Int
    public let timeToFirstTokenMs: Int64
    public let tokensPerSecond: Float
    public let requestId: String
    public let model: String

    init(proto: RARAGResult, model: String) {
        self.answer = proto.answer
        self.sources = proto.retrievedChunks.map(Match.init(proto:))
        self.inputTokens = Int(proto.usage.inputTokens)
        self.outputTokens = Int(proto.usage.outputTokens)
        self.timeToFirstTokenMs = proto.usage.ttftMs
        self.tokensPerSecond = Float(proto.usage.decodeTokensPerSecond)
        self.requestId = proto.requestID
        self.model = model
    }
}

/// How much a RAG session currently holds.
public struct RagStats: Sendable {
    public let documentCount: Int
    public let chunkCount: Int
    public let indexSizeBytes: Int64

    init(proto: RARAGStatistics) {
        self.documentCount = Int(proto.indexedDocuments)
        self.chunkCount = Int(proto.indexedChunks)
        self.indexSizeBytes = proto.vectorStoreSizeBytes
    }
}

// MARK: - Service states

/// Whether transcription is usable right now.
public struct SttState: Sendable {
    public let isReady: Bool
    public let modelId: String?
    public let supportsStreaming: Bool
    public let languages: [String]

    init(proto: RASTTServiceState) {
        self.isReady = proto.isReady
        self.modelId = proto.hasCurrentModel && !proto.currentModel.isEmpty ? proto.currentModel : nil
        self.supportsStreaming = proto.supportsStreaming
        self.languages = proto.supportedLanguageCodes
    }
}

/// What is loaded and how much room is left.
public struct ModelsState: Sendable {
    public let loaded: [ModelCategory: ModelInfo]
    public let storageUsedBytes: Int64
    public let storageFreeBytes: Int64
}

// MARK: - LoRA state

/// One LoRA adapter currently applied to the loaded model.
public struct AppliedAdapter: Sendable {
    public let id: String
    public let scale: Float

    init(proto: RALoraAdapterInfo) {
        self.id = proto.adapterID
        self.scale = proto.scale
    }
}

/// Which adapters are live.
public struct LoraState: Sendable {
    public let applied: [AppliedAdapter]

    init(proto: RALoraState) {
        self.applied = proto.loadedAdapters.filter(\.applied).map(AppliedAdapter.init(proto:))
    }
}
