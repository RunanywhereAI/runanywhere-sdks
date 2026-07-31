//
//  AmbientRecords.swift
//  RunAnywhereAI
//
//  Codable records persisted by the notes feature. Every id is derived from the
//  SDK's session/segment ids so a retried write updates the same record instead
//  of creating a duplicate.
//
//  Type names stay `AmbientSessionRecord` and friends to match the SDK's
//  ambient solution; everything a user reads says "note".
//

import Foundation
import RunAnywhere

// MARK: - Retention

/// Whether a note keeps its recording. Audio is a dogfood affordance for
/// judging capture quality, not something a shipping product would default to.
enum AmbientRetentionPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Keep the note text; discard audio as soon as it is transcribed.
    case transcriptsOnly
    /// Keep the recording alongside the transcript so the tester can hear what
    /// the model heard.
    case retainAudio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .transcriptsOnly: return "Text only"
        case .retainAudio: return "Text and recording"
        }
    }

    /// The voice memo is the point of dogfooding right now, so a fresh install
    /// keeps audio until the tester says otherwise.
    static let `default`: AmbientRetentionPolicy = .retainAudio

    var retainsAudio: Bool { self == .retainAudio }
}

/// Age after which a note's *recording* is deleted to reclaim space. Note text
/// is never reaped: transcripts, summaries, and action items live until the
/// tester deletes the note by hand.
enum AmbientRetentionWindow: Int, Codable, CaseIterable, Sendable, Identifiable {
    case oneDay = 1
    case sevenDays = 7
    case thirtyDays = 30
    case keepUntilDeleted = 0

    /// Recordings are the dogfood evidence, so nothing expires unless the
    /// tester opts in.
    static let `default`: AmbientRetentionWindow = .keepUntilDeleted

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneDay: return "After 1 day"
        case .sevenDays: return "After 7 days"
        case .thirtyDays: return "After 30 days"
        case .keepUntilDeleted: return "Never"
        }
    }

    /// Cutoff date for expiry, or `nil` when no recording expires on its own.
    func expiryCutoff(from now: Date) -> Date? {
        guard rawValue > 0 else { return nil }
        return now.addingTimeInterval(-Double(rawValue) * 24 * 60 * 60)
    }
}

// MARK: - Capture Context

/// Free-form labels the tester attaches so multi-hour dogfood runs stay
/// comparable across environments.
struct AmbientCaptureContext: Codable, Sendable, Equatable {
    var environment: String
    var placement: String
    var note: String

    static let empty = AmbientCaptureContext(environment: "", placement: "", note: "")

    var isEmpty: Bool {
        environment.isEmpty && placement.isEmpty && note.isEmpty
    }

    var summary: String {
        [environment, placement].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Segment

/// One finalized speech segment plus its transcription outcome.
struct AmbientSegmentRecord: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let sessionID: String
    let index: Int
    let startedAt: Date
    let endedAt: Date
    let durationMs: Int
    let sampleRate: Int
    let peakConfidence: Float

    var transcript: String?
    var transcriptConfidence: Float?
    var languageCode: String?
    var sttModelID: String?
    var transcriptionMs: Int?
    var speakerLabel: String?

    var realTimeFactor: Double? {
        guard let transcriptionMs, durationMs > 0 else { return nil }
        return Double(transcriptionMs) / Double(durationMs)
    }

    init(from segment: RAAmbientSegment) {
        self.id = segment.id
        self.sessionID = segment.sessionID
        self.index = segment.index
        self.startedAt = segment.startedAt
        self.endedAt = segment.endedAt
        self.durationMs = segment.durationMs
        self.sampleRate = segment.sampleRate
        // JSONEncoder rejects NaN/Inf; Sherpa confidence often arrives as NaN.
        self.peakConfidence = Self.jsonSafe(segment.peakConfidence)
    }

    init(
        id: String,
        sessionID: String,
        index: Int,
        startedAt: Date,
        endedAt: Date,
        durationMs: Int,
        sampleRate: Int,
        peakConfidence: Float
    ) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.peakConfidence = Self.jsonSafe(peakConfidence)
    }

    mutating func apply(_ transcript: RAAmbientTranscript) {
        self.transcript = transcript.text
        self.transcriptConfidence = Self.jsonSafeOptional(transcript.confidence)
        self.languageCode = transcript.languageCode.isEmpty ? nil : transcript.languageCode
        self.sttModelID = transcript.modelID
        self.transcriptionMs = transcript.transcriptionMs
    }

    /// JSON has no NaN/Inf; map them to 0 so a note can still be written.
    private static func jsonSafe(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }

    private static func jsonSafeOptional(_ value: Float) -> Float? {
        value.isFinite ? value : nil
    }
}

// MARK: - Action Item

/// One thing the note says somebody still has to do.
struct AmbientActionItem: Codable, Sendable, Identifiable, Equatable {
    let id: String
    var text: String
    var isDone: Bool
    /// Set for items the tester typed. A later digest rewrites the machine
    /// list, and manual items are carried across untouched so a re-run never
    /// erases something a person added by hand.
    var isManual: Bool

    init(id: String = UUID().uuidString, text: String, isDone: Bool = false, isManual: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.isManual = isManual
    }

    /// Case- and whitespace-insensitive identity, used to keep the same item
    /// from arriving twice across chunk digests and the final merge.
    var dedupeKey: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Note

/// One note: everything captured by a single recording.
struct AmbientSessionRecord: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let startedAt: Date
    var endedAt: Date?
    var profileID: String
    var vadModelID: String
    var sttModelID: String
    var digestModelID: String?
    var retentionPolicy: AmbientRetentionPolicy
    var context: AmbientCaptureContext
    var deviceModel: String
    var osVersion: String
    var segments: [AmbientSegmentRecord]

    /// The note-level summary, written by the merge pass at stop.
    var summary: String
    var actionItems: [AmbientActionItem]
    /// Output of each chunk digest, persisted as it lands so a crash or a
    /// deferred merge still leaves something readable behind.
    var partialSummaries: [String]
    /// The one continuous recording for this note, relative to the ambient
    /// root. Cleared when audio expires; the note itself survives.
    var audioRelativePath: String?
    /// Set when the tester renames the note.
    var customTitle: String?
    /// True when the merge pass was skipped because the app was backgrounded
    /// with a GPU-only digest model. The next foreground finishes it.
    var summaryPending: Bool
    /// Terminal reason recorded when the session stopped for anything other
    /// than a plain user stop, so failures leave a visible audit record.
    var stopReason: String?

    init(
        id: String,
        startedAt: Date,
        endedAt: Date? = nil,
        profileID: String,
        vadModelID: String,
        sttModelID: String,
        digestModelID: String? = nil,
        retentionPolicy: AmbientRetentionPolicy,
        context: AmbientCaptureContext,
        deviceModel: String,
        osVersion: String,
        segments: [AmbientSegmentRecord] = [],
        summary: String = "",
        actionItems: [AmbientActionItem] = [],
        partialSummaries: [String] = [],
        audioRelativePath: String? = nil,
        customTitle: String? = nil,
        summaryPending: Bool = false,
        stopReason: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.profileID = profileID
        self.vadModelID = vadModelID
        self.sttModelID = sttModelID
        self.digestModelID = digestModelID
        self.retentionPolicy = retentionPolicy
        self.context = context
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.segments = segments
        self.summary = summary
        self.actionItems = actionItems
        self.partialSummaries = partialSummaries
        self.audioRelativePath = audioRelativePath
        self.customTitle = customTitle
        self.summaryPending = summaryPending
        self.stopReason = stopReason
    }

    /// Notes written before summaries existed carry none of the new keys, and
    /// losing a tester's recording history to a schema change is worse than
    /// showing an old note without a summary. Everything added since decodes
    /// with a default instead of failing the file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        profileID = try container.decode(String.self, forKey: .profileID)
        vadModelID = try container.decode(String.self, forKey: .vadModelID)
        sttModelID = try container.decode(String.self, forKey: .sttModelID)
        digestModelID = try container.decodeIfPresent(String.self, forKey: .digestModelID)
        retentionPolicy = try container.decode(AmbientRetentionPolicy.self, forKey: .retentionPolicy)
        context = try container.decode(AmbientCaptureContext.self, forKey: .context)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        segments = try container.decodeIfPresent([AmbientSegmentRecord].self, forKey: .segments) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        actionItems = try container.decodeIfPresent([AmbientActionItem].self, forKey: .actionItems) ?? []
        partialSummaries = try container.decodeIfPresent([String].self, forKey: .partialSummaries) ?? []
        audioRelativePath = try container.decodeIfPresent(String.self, forKey: .audioRelativePath)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        summaryPending = try container.decodeIfPresent(Bool.self, forKey: .summaryPending) ?? false
        stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)
    }

    /// Wall-clock length of a finished note. Incomplete orphans (never got a
    /// mic) report zero so the list does not show a duration that grows forever.
    var duration: TimeInterval {
        guard let endedAt else { return 0 }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    /// True when the note was never filled in — typically a failed start that
    /// wrote the JSON before the microphone opened.
    var isEmptyOrphan: Bool {
        endedAt == nil
            && segments.isEmpty
            && summary.isEmpty
            && actionItems.isEmpty
            && audioRelativePath == nil
            && !summaryPending
    }

    var transcribedSegments: [AmbientSegmentRecord] {
        segments.filter { !($0.transcript ?? "").isEmpty }
    }

    /// The whole note as one string, so the detail view and search both read a
    /// single body instead of walking segments.
    var fullTranscript: String {
        transcribedSegments
            .compactMap { $0.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var hasAudio: Bool { audioRelativePath != nil }

    var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if let clause = Self.firstClause(of: summary) { return clause }
        return Self.titleFormatter.string(from: startedAt)
    }

    /// The first sentence of the summary, capped so a model that ignores the
    /// sentence break still yields a list row rather than a paragraph.
    private static func firstClause(of summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sentence = trimmed.prefix { $0 != "." && $0 != "\n" && $0 != "!" && $0 != "?" }
        let clause = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clause.isEmpty else { return nil }
        return clause.count > 80 ? String(clause.prefix(80)) + "…" : clause
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Upsert by id so a replayed event never appends a second copy.
    mutating func upsert(_ segment: AmbientSegmentRecord) {
        if let index = segments.firstIndex(where: { $0.id == segment.id }) {
            segments[index] = segment
        } else {
            segments.append(segment)
        }
    }

    /// Fold freshly digested items into the list, keeping every manual item and
    /// every tick the tester already made.
    mutating func mergeActionItems(_ incoming: [String]) {
        var seen = Set(actionItems.map(\.dedupeKey))
        for text in incoming {
            let candidate = AmbientActionItem(text: text)
            guard !candidate.dedupeKey.isEmpty, seen.insert(candidate.dedupeKey).inserted else { continue }
            actionItems.append(candidate)
        }
    }

    /// Replace the machine-written items with the merge pass's list while
    /// preserving manual items and completion state.
    mutating func replaceMachineActionItems(with incoming: [String]) {
        let manual = actionItems.filter(\.isManual)
        let previousState = Dictionary(
            actionItems.map { ($0.dedupeKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set(manual.map(\.dedupeKey))
        var rebuilt: [AmbientActionItem] = []
        for text in incoming {
            let candidate = AmbientActionItem(text: text)
            guard !candidate.dedupeKey.isEmpty, seen.insert(candidate.dedupeKey).inserted else { continue }
            if let previous = previousState[candidate.dedupeKey] {
                rebuilt.append(AmbientActionItem(id: previous.id, text: text, isDone: previous.isDone))
            } else {
                rebuilt.append(candidate)
            }
        }
        actionItems = manual + rebuilt
    }
}

// MARK: - Benchmark Sample

/// One instrumented ambient run, exported alongside the standard benchmark
/// suite but kept separate so the synthetic STT benchmark keeps its meaning.
struct AmbientBenchmarkSample: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let recordedAt: Date
    let sessionID: String
    let profileID: String
    let deviceModel: String
    let chipName: String
    let osVersion: String
    let audioRoute: String
    let environment: String
    let placement: String

    let sessionSeconds: Double
    let speechSeconds: Double
    let segmentCount: Int
    let transcribedSegmentCount: Int
    let droppedSegmentCount: Int
    let actionItemCount: Int
    let completedActionItemCount: Int

    let medianTranscriptionMs: Double
    let medianRealTimeFactor: Double
    let medianExtractionMs: Double
    let firstTranscriptLatencyMs: Double

    let peakMemoryBytes: Int64
    let batteryDeltaPerHour: Double
    let thermalState: String
    let interruptionCount: Int
    let retainedAudioBytes: Int64

    /// Fraction of the session that carried detected speech.
    var speechRatio: Double {
        guard sessionSeconds > 0 else { return 0 }
        return speechSeconds / sessionSeconds
    }

    /// Fraction of the note's action items the tester ticked off, which stands
    /// in for how many of them were worth extracting at all.
    var completedActionItemRate: Double {
        guard actionItemCount > 0 else { return 0 }
        return Double(completedActionItemCount) / Double(actionItemCount)
    }
}
