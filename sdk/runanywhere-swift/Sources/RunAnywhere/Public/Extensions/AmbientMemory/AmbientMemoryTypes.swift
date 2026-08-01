//
//  AmbientMemoryTypes.swift
//  RunAnywhere SDK
//
//  Public value types for the ambient-memory solution: the configuration a
//  host supplies when starting a session, the typed lifecycle events the
//  session emits, and the structured records the pipeline produces.
//
//  The host owns microphone acquisition and every storage / UI policy
//  decision; the SDK owns VAD debounce, segment boundaries, transcription
//  scheduling, and the event contract described here.
//

import Foundation

// MARK: - Session State

/// Coarse lifecycle state of an ambient-memory session. Hosts render this
/// directly; every transition is published as `RAAmbientEvent.state`.
public enum RAAmbientState: String, Sendable, CaseIterable {
    /// No session has been started.
    case idle
    /// Models are being resolved / loaded.
    case preparing
    /// Audio is flowing and VAD is armed, but no speech segment is open.
    case listening
    /// A speech segment is currently open and accumulating audio.
    case speechSegment
    /// At least one finalized segment is queued for or undergoing transcription.
    case processing
    /// The host paused ingestion; the session keeps its buffers.
    case paused
    /// The session finished normally and released its resources.
    case stopped
    /// The session ended on an unrecoverable failure.
    case failed
}

// MARK: - Configuration

/// Tuning for one ambient-memory session.
///
/// Durations are milliseconds of audio, not wall clock, so they stay stable
/// when ingestion runs faster or slower than real time (offline replay,
/// tests, or a backlogged host).
public struct RAAmbientConfiguration: Sendable {
    /// VAD model id loaded into `.voiceActivityDetection` before listening.
    public var vadModelID: String
    /// STT model id loaded into `.speechRecognition` before listening.
    public var sttModelID: String
    /// Sample rate of the Int16 PCM the host feeds in.
    public var sampleRate: Int
    /// Audio retained ahead of a speech-start transition so segments do not
    /// clip the first phoneme.
    public var preRollMs: Int
    /// Audio retained past a speech-end transition before the segment closes.
    public var postRollMs: Int
    /// Continuous speech required before a segment opens. Suppresses segments
    /// from door slams, keyboard clicks, and other single-frame transients.
    public var speechDebounceMs: Int
    /// Continuous silence required before an open segment closes.
    public var silenceHangoverMs: Int
    /// Segments shorter than this are discarded instead of transcribed.
    public var minSegmentMs: Int
    /// An open segment is force-closed at this length so a long monologue
    /// still produces incremental transcripts.
    public var maxSegmentMs: Int
    /// Emit the segment's PCM on `segmentFinalized`. Hosts that persist raw
    /// audio for dogfooding set this; production defaults leave it off.
    public var retainSegmentAudio: Bool
    /// Finalized segments allowed to queue for transcription before the
    /// pipeline sheds load and reports a backpressure gate.
    public var maxQueuedSegments: Int
    /// Transcription options forwarded to `RunAnywhere.transcribe`.
    public var sttOptions: RASTTOptions
    /// Detector overrides forwarded to `RunAnywhere.detectVoiceActivity`.
    public var vadOptions: RAVADOptions?

    public init(
        vadModelID: String,
        sttModelID: String,
        sampleRate: Int = 16_000,
        preRollMs: Int = 320,
        postRollMs: Int = 240,
        speechDebounceMs: Int = 128,
        silenceHangoverMs: Int = 700,
        minSegmentMs: Int = 400,
        maxSegmentMs: Int = 25_000,
        retainSegmentAudio: Bool = false,
        maxQueuedSegments: Int = 4,
        sttOptions: RASTTOptions = .defaults(),
        vadOptions: RAVADOptions? = nil
    ) {
        self.vadModelID = vadModelID
        self.sttModelID = sttModelID
        self.sampleRate = sampleRate
        self.preRollMs = preRollMs
        self.postRollMs = postRollMs
        self.speechDebounceMs = speechDebounceMs
        self.silenceHangoverMs = silenceHangoverMs
        self.minSegmentMs = minSegmentMs
        self.maxSegmentMs = maxSegmentMs
        self.retainSegmentAudio = retainSegmentAudio
        self.maxQueuedSegments = maxQueuedSegments
        self.sttOptions = sttOptions
        self.vadOptions = vadOptions
    }

    /// Defaults tuned for continuous ambient capture with the catalogued
    /// Silero VAD. Callers must still choose an STT model.
    public static func defaults(sttModelID: String) -> RAAmbientConfiguration {
        RAAmbientConfiguration(
            vadModelID: RunAnywhere.defaultVADModelID,
            sttModelID: sttModelID
        )
    }

    /// Frame size the pipeline feeds the detector, in samples. Silero expects
    /// 32 ms frames at 16 kHz; the value scales with `sampleRate`.
    public var vadFrameSampleCount: Int {
        max(160, sampleRate * 32 / 1000)
    }
}

// MARK: - Segments and Transcripts

/// One finalized run of speech, bounded by VAD transitions plus roll padding.
public struct RAAmbientSegment: Sendable, Identifiable {
    /// Stable id derived from the session id and segment index, so a host
    /// retrying persistence writes the same record instead of a duplicate.
    public let id: String
    public let sessionID: String
    public let index: Int
    public let startedAt: Date
    public let endedAt: Date
    public let durationMs: Int
    public let sampleRate: Int
    /// Peak VAD confidence observed inside the segment.
    public let peakConfidence: Float
    /// Int16 PCM for the segment, present only when the configuration asked
    /// for retained audio.
    public let pcm16: Data?
    /// Offset into the ingested recording timeline (excludes pause gaps), in
    /// milliseconds. Aligns with continuous WAV / diarization clocks.
    public let startOffsetMs: Int
    /// Exclusive end offset into the ingested recording timeline, in ms.
    public let endOffsetMs: Int

    public init(
        id: String,
        sessionID: String,
        index: Int,
        startedAt: Date,
        endedAt: Date,
        durationMs: Int,
        sampleRate: Int,
        peakConfidence: Float,
        pcm16: Data?,
        startOffsetMs: Int = 0,
        endOffsetMs: Int = 0
    ) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.peakConfidence = peakConfidence
        self.pcm16 = pcm16
        self.startOffsetMs = startOffsetMs
        self.endOffsetMs = endOffsetMs > 0 ? endOffsetMs : (startOffsetMs + durationMs)
    }
}

/// A completed transcription for one segment.
public struct RAAmbientTranscript: Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let segmentID: String
    public let segmentIndex: Int
    public let text: String
    public let confidence: Float
    public let languageCode: String
    public let startedAt: Date
    public let endedAt: Date
    public let audioDurationMs: Int
    public let transcriptionMs: Int
    public let modelID: String

    /// Transcription time over audio duration. Below 1.0 means the pipeline
    /// keeps up with real-time capture.
    public var realTimeFactor: Double {
        guard audioDurationMs > 0 else { return 0 }
        return Double(transcriptionMs) / Double(audioDurationMs)
    }

    public init(
        id: String,
        sessionID: String,
        segmentID: String,
        segmentIndex: Int,
        text: String,
        confidence: Float,
        languageCode: String,
        startedAt: Date,
        endedAt: Date,
        audioDurationMs: Int,
        transcriptionMs: Int,
        modelID: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.segmentID = segmentID
        self.segmentIndex = segmentIndex
        self.text = text
        self.confidence = confidence
        self.languageCode = languageCode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioDurationMs = audioDurationMs
        self.transcriptionMs = transcriptionMs
        self.modelID = modelID
    }
}

// MARK: - Gates and Failures

/// A non-fatal condition that made the pipeline shed or defer work.
public struct RAAmbientResourceGate: Sendable {
    public enum Reason: String, Sendable {
        /// Transcription fell behind ingestion and queued segments were dropped.
        case backpressure
        /// The host reported a thermal state that suspends derived work.
        case thermal
        /// The host reported memory pressure.
        case memory
        /// The host reported insufficient storage for retained audio.
        case storage
    }

    public let reason: Reason
    /// `true` when the gate engaged, `false` when it cleared.
    public let isActive: Bool
    public let detail: String

    public init(reason: Reason, isActive: Bool, detail: String) {
        self.reason = reason
        self.isActive = isActive
        self.detail = detail
    }
}

/// A pipeline error, scoped to the stage that produced it.
public struct RAAmbientFailure: Sendable {
    public enum Stage: String, Sendable {
        case modelLoad
        case vad
        case transcription
        case ingestion
    }

    public let stage: Stage
    public let message: String
    /// Fatal failures end the session; non-fatal ones skip a single segment.
    public let isFatal: Bool
    public let segmentID: String?

    public init(stage: Stage, message: String, isFatal: Bool, segmentID: String? = nil) {
        self.stage = stage
        self.message = message
        self.isFatal = isFatal
        self.segmentID = segmentID
    }
}

// MARK: - Events

/// Everything an ambient session tells its host. The host owns UI and storage
/// policy and reacts to these; it never drives the pipeline's internal stages.
public enum RAAmbientEvent: Sendable {
    case state(RAAmbientState)
    case speechStarted(at: Date)
    case speechEnded(at: Date, durationMs: Int)
    case segmentOpened(id: String, index: Int, startedAt: Date)
    case segmentFinalized(RAAmbientSegment)
    case transcript(RAAmbientTranscript)
    case resourceGate(RAAmbientResourceGate)
    case failure(RAAmbientFailure)
}

// MARK: - Note Digest

/// Which pass of the map-reduce summarization a digest call is performing.
///
/// A whole note rarely fits in a small local model's context, so transcripts
/// are digested in chunks while capture runs (`chunk`) and those partial
/// summaries are folded into one final answer at the end (`merge`).
public enum RAAmbientDigestMode: String, Sendable, CaseIterable {
    case chunk
    case merge
}

/// One bullet inside a structured note section.
public struct RAAmbientDigestBullet: Sendable, Equatable {
    /// Short bold-ready lead-in (e.g. "Qualcomm"). Empty when unused.
    public let lead: String
    public let text: String
    /// Segment indices cited from the numbered transcript (`[S12]` → 12).
    public let sourceSegmentIndices: [Int]

    public init(lead: String = "", text: String, sourceSegmentIndices: [Int] = []) {
        self.lead = lead
        self.text = text
        self.sourceSegmentIndices = sourceSegmentIndices
    }
}

/// A topical heading with bullets — Notion-style summary block.
public struct RAAmbientDigestSection: Sendable, Equatable {
    public let heading: String
    public let bullets: [RAAmbientDigestBullet]

    public init(heading: String, bullets: [RAAmbientDigestBullet]) {
        self.heading = heading
        self.bullets = bullets
    }
}

/// One action item with optional transcript citations.
public struct RAAmbientDigestActionItem: Sendable, Equatable {
    public let text: String
    public let sourceSegmentIndices: [Int]

    public init(text: String, sourceSegmentIndices: [Int] = []) {
        self.text = text
        self.sourceSegmentIndices = sourceSegmentIndices
    }
}

/// Structured note digest: sections + action items (+ flat summary fallback).
///
/// A note gets many of these during capture and exactly one after the merge.
public struct RAAmbientNoteDigest: Sendable, Equatable {
    /// Flattened prose for hosts that only need a string (search, titles).
    public let summary: String
    /// Suggested note title when the model provides one.
    public let title: String
    public let sections: [RAAmbientDigestSection]
    public let actionItems: [String]
    public let citedActionItems: [RAAmbientDigestActionItem]
    public let extractionMs: Int
    public let modelID: String

    public init(
        summary: String,
        actionItems: [String],
        extractionMs: Int,
        modelID: String,
        title: String = "",
        sections: [RAAmbientDigestSection] = [],
        citedActionItems: [RAAmbientDigestActionItem] = []
    ) {
        self.summary = summary
        self.title = title
        self.sections = sections
        self.actionItems = actionItems
        self.citedActionItems = citedActionItems.isEmpty
            ? actionItems.map { RAAmbientDigestActionItem(text: $0) }
            : citedActionItems
        self.extractionMs = extractionMs
        self.modelID = modelID
    }
}
