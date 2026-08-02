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

// MARK: - Speaker Labeling

/// Opt-in post-pass speaker labeling for a saved note.
enum AmbientSpeakerLabelingState: String, Codable, Sendable, Equatable {
    /// No speaker model chosen for this note yet.
    case notConfigured
    /// A model is selected; user has not run labeling (or can re-label).
    case modelSelected
    case loadingModel
    case labeling
    case completed
    /// App was backgrounded / suspended mid-pass; transcript is still intact.
    case interrupted
    case failed
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
    /// Recording-relative start (excludes pause gaps). Nil on notes captured
    /// before offset stamping existed — alignment falls back to cumulative duration.
    var startOffsetMs: Int?
    var endOffsetMs: Int?

    var transcript: String?
    var transcriptConfidence: Float?
    var languageCode: String?
    var sttModelID: String?
    var transcriptionMs: Int?
    /// Display speaker label (machine or user-renamed).
    var speakerLabel: String?
    /// Last diarization assignment, kept so re-label can refresh non-manual labels.
    var machineSpeakerLabel: String?
    /// User renamed this speaker; re-label must not overwrite `speakerLabel`.
    var isSpeakerManual: Bool

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
        self.startOffsetMs = segment.startOffsetMs
        self.endOffsetMs = segment.endOffsetMs
        self.isSpeakerManual = false
    }

    init(
        id: String,
        sessionID: String,
        index: Int,
        startedAt: Date,
        endedAt: Date,
        durationMs: Int,
        sampleRate: Int,
        peakConfidence: Float,
        startOffsetMs: Int? = nil,
        endOffsetMs: Int? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.peakConfidence = Self.jsonSafe(peakConfidence)
        self.startOffsetMs = startOffsetMs
        self.endOffsetMs = endOffsetMs
        self.isSpeakerManual = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        index = try container.decode(Int.self, forKey: .index)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        peakConfidence = try container.decode(Float.self, forKey: .peakConfidence)
        startOffsetMs = try container.decodeIfPresent(Int.self, forKey: .startOffsetMs)
        endOffsetMs = try container.decodeIfPresent(Int.self, forKey: .endOffsetMs)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        transcriptConfidence = try container.decodeIfPresent(Float.self, forKey: .transcriptConfidence)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        sttModelID = try container.decodeIfPresent(String.self, forKey: .sttModelID)
        transcriptionMs = try container.decodeIfPresent(Int.self, forKey: .transcriptionMs)
        speakerLabel = try container.decodeIfPresent(String.self, forKey: .speakerLabel)
        machineSpeakerLabel = try container.decodeIfPresent(String.self, forKey: .machineSpeakerLabel)
        isSpeakerManual = try container.decodeIfPresent(Bool.self, forKey: .isSpeakerManual) ?? false
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
    /// Segment ids cited from the structured digest (for jump-to-transcript).
    var sourceSegmentIDs: [String]

    init(
        id: String = UUID().uuidString,
        text: String,
        isDone: Bool = false,
        isManual: Bool = false,
        sourceSegmentIDs: [String] = []
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.isManual = isManual
        self.sourceSegmentIDs = sourceSegmentIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? false
        sourceSegmentIDs = try container.decodeIfPresent([String].self, forKey: .sourceSegmentIDs) ?? []
    }

    /// Case- and whitespace-insensitive identity, used to keep the same item
    /// from arriving twice across chunk digests and the final merge.
    var dedupeKey: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Persisted Notion-style digest bullet.
struct AmbientDigestBullet: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var lead: String
    var text: String
    var sourceSegmentIDs: [String]

    init(
        id: String = UUID().uuidString,
        lead: String = "",
        text: String,
        sourceSegmentIDs: [String] = []
    ) {
        self.id = id
        self.lead = lead
        self.text = text
        self.sourceSegmentIDs = sourceSegmentIDs
    }
}

/// Persisted Notion-style digest section.
struct AmbientDigestSection: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var heading: String
    var bullets: [AmbientDigestBullet]

    init(
        id: String = UUID().uuidString,
        heading: String,
        bullets: [AmbientDigestBullet]
    ) {
        self.id = id
        self.heading = heading
        self.bullets = bullets
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
    /// Optional Sortformer (or other) model chosen from note detail for labeling.
    var diarizationModelID: String?
    var retentionPolicy: AmbientRetentionPolicy
    var context: AmbientCaptureContext
    var deviceModel: String
    var osVersion: String
    var segments: [AmbientSegmentRecord]

    /// The note-level summary, written by the merge pass at stop.
    /// Flattened prose kept for search/titles; structured UI prefers `digestSections`.
    var summary: String
    /// Suggested title from the structured digest (optional).
    var digestTitle: String?
    /// Notion-style sectioned summary.
    var digestSections: [AmbientDigestSection]
    var actionItems: [AmbientActionItem]
    /// Output of each chunk digest, persisted as it lands so a crash or a
    /// deferred merge still leaves something readable behind.
    var partialSummaries: [String]
    /// How many map-pass chunks have been committed into `partialSummaries`.
    /// Used to resume a killed digester without redoing finished chunks.
    var digestMapChunksCompleted: Int
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
    var speakerLabelingState: AmbientSpeakerLabelingState
    /// Human-readable progress / error for the Label speakers card.
    var speakerLabelingDetail: String?
    /// True when speaker labels arrived after an existing summary.
    var digestStale: Bool
    var speakerCount: Int?

    init(
        id: String,
        startedAt: Date,
        endedAt: Date? = nil,
        profileID: String,
        vadModelID: String,
        sttModelID: String,
        digestModelID: String? = nil,
        diarizationModelID: String? = nil,
        retentionPolicy: AmbientRetentionPolicy,
        context: AmbientCaptureContext,
        deviceModel: String,
        osVersion: String,
        segments: [AmbientSegmentRecord] = [],
        summary: String = "",
        digestTitle: String? = nil,
        digestSections: [AmbientDigestSection] = [],
        actionItems: [AmbientActionItem] = [],
        partialSummaries: [String] = [],
        digestMapChunksCompleted: Int = 0,
        audioRelativePath: String? = nil,
        customTitle: String? = nil,
        summaryPending: Bool = false,
        stopReason: String? = nil,
        speakerLabelingState: AmbientSpeakerLabelingState = .notConfigured,
        speakerLabelingDetail: String? = nil,
        digestStale: Bool = false,
        speakerCount: Int? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.profileID = profileID
        self.vadModelID = vadModelID
        self.sttModelID = sttModelID
        self.digestModelID = digestModelID
        self.diarizationModelID = diarizationModelID
        self.retentionPolicy = retentionPolicy
        self.context = context
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.segments = segments
        self.summary = summary
        self.digestTitle = digestTitle
        self.digestSections = digestSections
        self.actionItems = actionItems
        self.partialSummaries = partialSummaries
        self.digestMapChunksCompleted = digestMapChunksCompleted
        self.audioRelativePath = audioRelativePath
        self.customTitle = customTitle
        self.summaryPending = summaryPending
        self.stopReason = stopReason
        self.speakerLabelingState = speakerLabelingState
        self.speakerLabelingDetail = speakerLabelingDetail
        self.digestStale = digestStale
        self.speakerCount = speakerCount
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
        diarizationModelID = try container.decodeIfPresent(String.self, forKey: .diarizationModelID)
        retentionPolicy = try container.decode(AmbientRetentionPolicy.self, forKey: .retentionPolicy)
        context = try container.decode(AmbientCaptureContext.self, forKey: .context)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        segments = try container.decodeIfPresent([AmbientSegmentRecord].self, forKey: .segments) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        digestTitle = try container.decodeIfPresent(String.self, forKey: .digestTitle)
        digestSections = try container.decodeIfPresent([AmbientDigestSection].self, forKey: .digestSections) ?? []
        actionItems = try container.decodeIfPresent([AmbientActionItem].self, forKey: .actionItems) ?? []
        partialSummaries = try container.decodeIfPresent([String].self, forKey: .partialSummaries) ?? []
        digestMapChunksCompleted = try container.decodeIfPresent(Int.self, forKey: .digestMapChunksCompleted)
            ?? partialSummaries.count
        audioRelativePath = try container.decodeIfPresent(String.self, forKey: .audioRelativePath)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        summaryPending = try container.decodeIfPresent(Bool.self, forKey: .summaryPending) ?? false
        stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)
        speakerLabelingState = try container.decodeIfPresent(
            AmbientSpeakerLabelingState.self,
            forKey: .speakerLabelingState
        ) ?? .notConfigured
        speakerLabelingDetail = try container.decodeIfPresent(String.self, forKey: .speakerLabelingDetail)
        digestStale = try container.decodeIfPresent(Bool.self, forKey: .digestStale) ?? false
        speakerCount = try container.decodeIfPresent(Int.self, forKey: .speakerCount)
    }

    /// True when a prior digester pass saved map chunks but never finished merge.
    var hasResumableDigest: Bool {
        summaryPending && (!partialSummaries.isEmpty || digestMapChunksCompleted > 0)
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
        segments
            .filter { !($0.transcript ?? "").isEmpty }
            .sorted { $0.index < $1.index }
    }

    /// The whole note as one string, so the detail view and search both read a
    /// single body instead of walking segments.
    var fullTranscript: String {
        transcribedSegments
            .compactMap { $0.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Transcript with speaker prefixes when labels exist — preferred for
    /// display and LLM digests after labeling.
    var attributedTranscript: String {
        transcribedSegments.compactMap { segment in
            guard let text = segment.transcript?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            if let speaker = segment.speakerLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !speaker.isEmpty {
                return "\(speaker): \(text)"
            }
            return text
        }
        .joined(separator: "\n")
    }

    /// Source text for Summarize / Rewrite with `[S12]` markers for citations.
    var digestSourceTranscript: String {
        numberedDigestTranscript
    }

    /// Numbered turns the digest model can cite (`[S12] Speaker: text`).
    var numberedDigestTranscript: String {
        transcribedSegments.compactMap { segment in
            guard let text = segment.transcript?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            let speaker = segment.speakerLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let speaker, !speaker.isEmpty {
                return "[S\(segment.index)] \(speaker): \(text)"
            }
            return "[S\(segment.index)] \(text)"
        }
        .joined(separator: "\n")
    }

    var hasStructuredDigest: Bool {
        !digestSections.isEmpty
    }

    /// Map model-cited segment indices onto persisted segment ids.
    func segmentIDs(forIndices indices: [Int]) -> [String] {
        let byIndex = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0.id) })
        return indices.compactMap { byIndex[$0] }
    }

    /// Apply a structured digest onto summary, sections, and machine action items.
    mutating func applyStructuredDigest(_ digest: RAAmbientNoteDigest) {
        summary = digest.summary
        if !digest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            digestTitle = digest.title
            if customTitle == nil {
                // Leave customTitle alone; list title prefers custom, then digestTitle via firstClause(summary).
            }
        }
        digestSections = digest.sections.map { section in
            AmbientDigestSection(
                heading: section.heading,
                bullets: section.bullets.map { bullet in
                    AmbientDigestBullet(
                        lead: bullet.lead,
                        text: bullet.text,
                        sourceSegmentIDs: segmentIDs(forIndices: bullet.sourceSegmentIndices)
                    )
                }
            )
        }
        let cited = digest.citedActionItems.isEmpty
            ? digest.actionItems.map { RAAmbientDigestActionItem(text: $0) }
            : digest.citedActionItems
        replaceMachineActionItems(with: cited.map { item in
            (item.text, segmentIDs(forIndices: item.sourceSegmentIndices))
        })
        summaryPending = false
        digestStale = false
    }

    var hasAudio: Bool { audioRelativePath != nil }

    var isSpeakerLabelingBusy: Bool {
        switch speakerLabelingState {
        case .loadingModel, .labeling: return true
        default: return false
        }
    }

    var hasSpeakerLabels: Bool {
        segments.contains { $0.speakerLabel != nil }
    }

    var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if let digestTitle, !digestTitle.isEmpty { return digestTitle }
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

    /// Fill missing recording-relative offsets from segment order + duration
    /// so citation seek works even when older pipeline events omitted stamps.
    mutating func stampRecordingOffsetsIfNeeded() {
        var cursor = 0
        let order = segments.indices.sorted { segments[$0].index < segments[$1].index }
        for i in order {
            if let start = segments[i].startOffsetMs {
                cursor = segments[i].endOffsetMs ?? (start + segments[i].durationMs)
                continue
            }
            segments[i].startOffsetMs = cursor
            segments[i].endOffsetMs = cursor + segments[i].durationMs
            cursor += segments[i].durationMs
        }
    }

    /// Upsert by id so a replayed event never appends a second copy.
    /// Preserves manual speaker renames and prior machine labels across ASR
    /// segment replays.
    mutating func upsert(_ segment: AmbientSegmentRecord) {
        if let index = segments.firstIndex(where: { $0.id == segment.id }) {
            var merged = segment
            let existing = segments[index]
            if existing.isSpeakerManual {
                merged.speakerLabel = existing.speakerLabel
                merged.isSpeakerManual = true
            } else if merged.speakerLabel == nil {
                merged.speakerLabel = existing.speakerLabel
            }
            if merged.machineSpeakerLabel == nil {
                merged.machineSpeakerLabel = existing.machineSpeakerLabel
            }
            if merged.startOffsetMs == nil {
                merged.startOffsetMs = existing.startOffsetMs
            }
            if merged.endOffsetMs == nil {
                merged.endOffsetMs = existing.endOffsetMs
            }
            segments[index] = merged
        } else {
            segments.append(segment)
        }
    }

    /// Apply diarization assignments while preserving user renames.
    mutating func applyDiarizationLabels(
        _ assignments: [String: String],
        modelID: String,
        speakerCount: Int
    ) {
        for index in segments.indices {
            guard let machine = assignments[segments[index].id] else { continue }
            segments[index].machineSpeakerLabel = machine
            if !segments[index].isSpeakerManual {
                segments[index].speakerLabel = machine
            }
        }
        diarizationModelID = modelID
        self.speakerCount = speakerCount
        speakerLabelingState = .completed
        speakerLabelingDetail = speakerCount > 0
            ? "\(speakerCount) speakers labeled."
            : "Labeling finished — no distinct speakers found."
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            digestStale = true
        }
    }

    /// Rename every segment that currently uses `from` to `to`, marking them manual.
    mutating func renameSpeaker(from oldLabel: String, to newLabel: String) {
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for index in segments.indices where segments[index].speakerLabel == oldLabel {
            segments[index].speakerLabel = trimmed
            segments[index].isSpeakerManual = true
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
        replaceMachineActionItems(with: incoming.map { ($0, [String]()) })
    }

    /// Replace machine items, carrying citation segment ids from the digest.
    mutating func replaceMachineActionItems(with incoming: [(text: String, sourceSegmentIDs: [String])]) {
        let manual = actionItems.filter(\.isManual)
        let previousState = Dictionary(
            actionItems.map { ($0.dedupeKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set(manual.map(\.dedupeKey))
        var rebuilt: [AmbientActionItem] = []
        for entry in incoming {
            let candidate = AmbientActionItem(text: entry.text, sourceSegmentIDs: entry.sourceSegmentIDs)
            guard !candidate.dedupeKey.isEmpty, seen.insert(candidate.dedupeKey).inserted else { continue }
            if let previous = previousState[candidate.dedupeKey] {
                rebuilt.append(AmbientActionItem(
                    id: previous.id,
                    text: entry.text,
                    isDone: previous.isDone,
                    sourceSegmentIDs: entry.sourceSegmentIDs.isEmpty
                        ? previous.sourceSegmentIDs
                        : entry.sourceSegmentIDs
                ))
            } else {
                rebuilt.append(candidate)
            }
        }
        actionItems = manual + rebuilt
    }
}

// MARK: - File-run metrics

/// Stage timings and memory samples for one offline file dogfood run.
struct AmbientFileRunMetrics: Codable, Sendable, Equatable {
    var fixtureName: String
    var sessionID: String
    var convertMs: Int = 0
    var asrMs: Int = 0
    var firstTranscriptMs: Int = 0
    var diarizationMs: Int = 0
    var digestMs: Int = 0
    var totalMs: Int = 0
    var peakMemoryBytes: Int64 = 0
    var memoryAfterASR: Int64 = 0
    var memoryAfterDiarization: Int64 = 0
    var memoryAfterDigest: Int64 = 0
    var segmentCount: Int = 0
    var transcribedCount: Int = 0
    var speakerCount: Int = 0
    var sectionCount: Int = 0
    var bulletCount: Int = 0
    var actionItemCount: Int = 0
    var audioDurationMs: Int = 0
    var vadModelID: String = ""
    var asrModelID: String = ""
    var diarizationModelID: String?
    var digestModelID: String?
    var deviceModel: String = ""
    var osVersion: String = ""
    var thermalState: String = ""
    var error: String?
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
    /// Updated when a post-pass digest amends the live sample.
    var medianExtractionMs: Double
    let firstTranscriptLatencyMs: Double

    /// Updated as post-pass Label/Summarize peaks are merged in.
    var peakMemoryBytes: Int64
    let batteryDeltaPerHour: Double
    let thermalState: String
    let interruptionCount: Int
    let retainedAudioBytes: Int64

    /// "live" mic capture or "file" offline import dogfood.
    var runKind: String
    var convertMs: Int
    var asrMs: Int
    var diarizationMs: Int
    var digestMs: Int
    var sectionCount: Int
    var bulletCount: Int
    var speakerCount: Int
    var fixtureName: String?

    // MARK: Performance-feature instrumentation

    /// Live VAD mode: `silero`, `economy`, `hybrid`, or `offline-energy` for file runs.
    var vadMode: String
    /// Warm-keep policy: `none`, `diarization`, or `digester`.
    var warmKeep: String
    /// Developer toggle was on for streaming Sortformer during capture.
    var streamDiarEnabled: Bool
    /// Sortformer stream actually loaded and ran alongside ASR.
    var streamDiarUsed: Bool
    /// Free RAM reported at session start.
    var availableMemoryAtStartBytes: Int64
    /// Process footprint at session start.
    var memoryAtStartBytes: Int64
    /// Peak footprint while capture / ASR was resident.
    var memoryPeakCaptureBytes: Int64
    /// Footprint right after ASR/VAD unload.
    var memoryAfterASRUnloadBytes: Int64
    /// Footprint after diarization stage (stream finish or post-pass).
    var memoryAfterDiarizationBytes: Int64
    /// Footprint after digest stage.
    var memoryAfterDigestBytes: Int64
    /// Battery fraction at start/end (`-1` when unavailable).
    var batteryLevelStart: Float
    var batteryLevelEnd: Float
    var thermalStateStart: String
    var thermalStateEnd: String
    /// True when Sortformer was already warm (skipped cold load).
    var warmKeepDiarizationHit: Bool
    /// True when digester was already warm (skipped cold load).
    var warmKeepDigestHit: Bool
    /// Wall time spent loading Sortformer (0 on warm hit).
    var diarizationLoadMs: Int
    /// Wall time spent loading the digester (0 on warm hit).
    var digestLoadMs: Int
    /// How many times the live STT backlog shed a segment.
    var backpressureEventCount: Int

    init(
        id: UUID,
        recordedAt: Date,
        sessionID: String,
        profileID: String,
        deviceModel: String,
        chipName: String,
        osVersion: String,
        audioRoute: String,
        environment: String,
        placement: String,
        sessionSeconds: Double,
        speechSeconds: Double,
        segmentCount: Int,
        transcribedSegmentCount: Int,
        droppedSegmentCount: Int,
        actionItemCount: Int,
        completedActionItemCount: Int,
        medianTranscriptionMs: Double,
        medianRealTimeFactor: Double,
        medianExtractionMs: Double,
        firstTranscriptLatencyMs: Double,
        peakMemoryBytes: Int64,
        batteryDeltaPerHour: Double,
        thermalState: String,
        interruptionCount: Int,
        retainedAudioBytes: Int64,
        runKind: String = "live",
        convertMs: Int = 0,
        asrMs: Int = 0,
        diarizationMs: Int = 0,
        digestMs: Int = 0,
        sectionCount: Int = 0,
        bulletCount: Int = 0,
        speakerCount: Int = 0,
        fixtureName: String? = nil,
        vadMode: String = "silero",
        warmKeep: String = "none",
        streamDiarEnabled: Bool = false,
        streamDiarUsed: Bool = false,
        availableMemoryAtStartBytes: Int64 = 0,
        memoryAtStartBytes: Int64 = 0,
        memoryPeakCaptureBytes: Int64 = 0,
        memoryAfterASRUnloadBytes: Int64 = 0,
        memoryAfterDiarizationBytes: Int64 = 0,
        memoryAfterDigestBytes: Int64 = 0,
        batteryLevelStart: Float = -1,
        batteryLevelEnd: Float = -1,
        thermalStateStart: String = "",
        thermalStateEnd: String = "",
        warmKeepDiarizationHit: Bool = false,
        warmKeepDigestHit: Bool = false,
        diarizationLoadMs: Int = 0,
        digestLoadMs: Int = 0,
        backpressureEventCount: Int = 0
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.sessionID = sessionID
        self.profileID = profileID
        self.deviceModel = deviceModel
        self.chipName = chipName
        self.osVersion = osVersion
        self.audioRoute = audioRoute
        self.environment = environment
        self.placement = placement
        self.sessionSeconds = sessionSeconds
        self.speechSeconds = speechSeconds
        self.segmentCount = segmentCount
        self.transcribedSegmentCount = transcribedSegmentCount
        self.droppedSegmentCount = droppedSegmentCount
        self.actionItemCount = actionItemCount
        self.completedActionItemCount = completedActionItemCount
        self.medianTranscriptionMs = medianTranscriptionMs
        self.medianRealTimeFactor = medianRealTimeFactor
        self.medianExtractionMs = medianExtractionMs
        self.firstTranscriptLatencyMs = firstTranscriptLatencyMs
        self.peakMemoryBytes = peakMemoryBytes
        self.batteryDeltaPerHour = batteryDeltaPerHour
        self.thermalState = thermalState
        self.interruptionCount = interruptionCount
        self.retainedAudioBytes = retainedAudioBytes
        self.runKind = runKind
        self.convertMs = convertMs
        self.asrMs = asrMs
        self.diarizationMs = diarizationMs
        self.digestMs = digestMs
        self.sectionCount = sectionCount
        self.bulletCount = bulletCount
        self.speakerCount = speakerCount
        self.fixtureName = fixtureName
        self.vadMode = vadMode
        self.warmKeep = warmKeep
        self.streamDiarEnabled = streamDiarEnabled
        self.streamDiarUsed = streamDiarUsed
        self.availableMemoryAtStartBytes = availableMemoryAtStartBytes
        self.memoryAtStartBytes = memoryAtStartBytes
        self.memoryPeakCaptureBytes = memoryPeakCaptureBytes
        self.memoryAfterASRUnloadBytes = memoryAfterASRUnloadBytes
        self.memoryAfterDiarizationBytes = memoryAfterDiarizationBytes
        self.memoryAfterDigestBytes = memoryAfterDigestBytes
        self.batteryLevelStart = batteryLevelStart
        self.batteryLevelEnd = batteryLevelEnd
        self.thermalStateStart = thermalStateStart
        self.thermalStateEnd = thermalStateEnd
        self.warmKeepDiarizationHit = warmKeepDiarizationHit
        self.warmKeepDigestHit = warmKeepDigestHit
        self.diarizationLoadMs = diarizationLoadMs
        self.digestLoadMs = digestLoadMs
        self.backpressureEventCount = backpressureEventCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        profileID = try container.decode(String.self, forKey: .profileID)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        chipName = try container.decode(String.self, forKey: .chipName)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        audioRoute = try container.decode(String.self, forKey: .audioRoute)
        environment = try container.decode(String.self, forKey: .environment)
        placement = try container.decode(String.self, forKey: .placement)
        sessionSeconds = try container.decode(Double.self, forKey: .sessionSeconds)
        speechSeconds = try container.decode(Double.self, forKey: .speechSeconds)
        segmentCount = try container.decode(Int.self, forKey: .segmentCount)
        transcribedSegmentCount = try container.decode(Int.self, forKey: .transcribedSegmentCount)
        droppedSegmentCount = try container.decode(Int.self, forKey: .droppedSegmentCount)
        actionItemCount = try container.decode(Int.self, forKey: .actionItemCount)
        completedActionItemCount = try container.decode(Int.self, forKey: .completedActionItemCount)
        medianTranscriptionMs = try container.decode(Double.self, forKey: .medianTranscriptionMs)
        medianRealTimeFactor = try container.decode(Double.self, forKey: .medianRealTimeFactor)
        medianExtractionMs = try container.decode(Double.self, forKey: .medianExtractionMs)
        firstTranscriptLatencyMs = try container.decode(Double.self, forKey: .firstTranscriptLatencyMs)
        peakMemoryBytes = try container.decode(Int64.self, forKey: .peakMemoryBytes)
        batteryDeltaPerHour = try container.decode(Double.self, forKey: .batteryDeltaPerHour)
        thermalState = try container.decode(String.self, forKey: .thermalState)
        interruptionCount = try container.decode(Int.self, forKey: .interruptionCount)
        retainedAudioBytes = try container.decode(Int64.self, forKey: .retainedAudioBytes)
        runKind = try container.decodeIfPresent(String.self, forKey: .runKind) ?? "live"
        convertMs = try container.decodeIfPresent(Int.self, forKey: .convertMs) ?? 0
        asrMs = try container.decodeIfPresent(Int.self, forKey: .asrMs) ?? 0
        diarizationMs = try container.decodeIfPresent(Int.self, forKey: .diarizationMs) ?? 0
        digestMs = try container.decodeIfPresent(Int.self, forKey: .digestMs) ?? 0
        sectionCount = try container.decodeIfPresent(Int.self, forKey: .sectionCount) ?? 0
        bulletCount = try container.decodeIfPresent(Int.self, forKey: .bulletCount) ?? 0
        speakerCount = try container.decodeIfPresent(Int.self, forKey: .speakerCount) ?? 0
        fixtureName = try container.decodeIfPresent(String.self, forKey: .fixtureName)
        vadMode = try container.decodeIfPresent(String.self, forKey: .vadMode) ?? "silero"
        warmKeep = try container.decodeIfPresent(String.self, forKey: .warmKeep) ?? "none"
        streamDiarEnabled = try container.decodeIfPresent(Bool.self, forKey: .streamDiarEnabled) ?? false
        streamDiarUsed = try container.decodeIfPresent(Bool.self, forKey: .streamDiarUsed) ?? false
        availableMemoryAtStartBytes = try container.decodeIfPresent(Int64.self, forKey: .availableMemoryAtStartBytes) ?? 0
        memoryAtStartBytes = try container.decodeIfPresent(Int64.self, forKey: .memoryAtStartBytes) ?? 0
        memoryPeakCaptureBytes = try container.decodeIfPresent(Int64.self, forKey: .memoryPeakCaptureBytes) ?? 0
        memoryAfterASRUnloadBytes = try container.decodeIfPresent(Int64.self, forKey: .memoryAfterASRUnloadBytes) ?? 0
        memoryAfterDiarizationBytes = try container.decodeIfPresent(Int64.self, forKey: .memoryAfterDiarizationBytes) ?? 0
        memoryAfterDigestBytes = try container.decodeIfPresent(Int64.self, forKey: .memoryAfterDigestBytes) ?? 0
        batteryLevelStart = try container.decodeIfPresent(Float.self, forKey: .batteryLevelStart) ?? -1
        batteryLevelEnd = try container.decodeIfPresent(Float.self, forKey: .batteryLevelEnd) ?? -1
        thermalStateStart = try container.decodeIfPresent(String.self, forKey: .thermalStateStart) ?? ""
        thermalStateEnd = try container.decodeIfPresent(String.self, forKey: .thermalStateEnd) ?? thermalState
        warmKeepDiarizationHit = try container.decodeIfPresent(Bool.self, forKey: .warmKeepDiarizationHit) ?? false
        warmKeepDigestHit = try container.decodeIfPresent(Bool.self, forKey: .warmKeepDigestHit) ?? false
        diarizationLoadMs = try container.decodeIfPresent(Int.self, forKey: .diarizationLoadMs) ?? 0
        digestLoadMs = try container.decodeIfPresent(Int.self, forKey: .digestLoadMs) ?? 0
        backpressureEventCount = try container.decodeIfPresent(Int.self, forKey: .backpressureEventCount) ?? droppedSegmentCount
    }

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
