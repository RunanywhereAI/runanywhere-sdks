//
//  AmbientMemoryStore.swift
//  RunAnywhereAI
//
//  Local persistence for notes: note documents, the one recording each note
//  owns, audio expiry, search, and purge.
//
//  Written with until-first-unlock protection so a note can keep appending
//  and saving while the screen is locked (the point of background capture).
//  Bytes stay encrypted until the first unlock after boot. Nothing here
//  talks to the network.
//

import Foundation
import os

/// Serialised owner of the Lab's on-disk state.
///
/// An actor rather than a main-actor singleton: transcription and audio writes
/// happen while the UI is scrolling, and the write path must never block the
/// main thread.
actor AmbientMemoryStore {
    static let shared = AmbientMemoryStore()

    private let logger = Logger(subsystem: "com.runanywhere", category: "AmbientMemoryStore")
    private let fileManager = FileManager.default

    private let rootDirectory: URL
    private let sessionsDirectory: URL
    private let audioDirectory: URL
    private let benchmarksURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Sessions the caller deleted this run. A late write from an in-flight
    /// transcription must not resurrect them.
    private var deletedSessionIDs: Set<String> = []

    /// The recording currently being appended to, if a note is capturing.
    private var activeRecording: WAVFileWriter?

    private init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootDirectory = documents.appendingPathComponent("AmbientMemory", isDirectory: true)
        sessionsDirectory = rootDirectory.appendingPathComponent("Sessions", isDirectory: true)
        audioDirectory = rootDirectory.appendingPathComponent("Audio", isDirectory: true)
        benchmarksURL = rootDirectory.appendingPathComponent("benchmarks.json")
        createDirectories()
    }

    // MARK: - Sessions

    /// All sessions, newest first. Empty orphans from a failed mic start are
    /// deleted on load so the list never shows date-only husks.
    func loadSessions() -> [AmbientSessionRecord] {
        let files = (try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> AmbientSessionRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(AmbientSessionRecord.self, from: data)
            }
            .filter { !deletedSessionIDs.contains($0.id) }
            .compactMap { session -> AmbientSessionRecord? in
                guard session.isEmptyOrphan else { return session }
                delete(sessionID: session.id)
                logger.info("Removed empty orphan note \(session.id, privacy: .public)")
                return nil
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func loadSession(id: String) -> AmbientSessionRecord? {
        guard !deletedSessionIDs.contains(id),
              let data = try? Data(contentsOf: sessionURL(id)) else { return nil }
        return try? decoder.decode(AmbientSessionRecord.self, from: data)
    }

    /// Write a session document atomically. Tombstoned sessions are ignored so
    /// a deletion during an active recording stays deleted.
    func save(_ session: AmbientSessionRecord) {
        guard !deletedSessionIDs.contains(session.id) else { return }
        do {
            let data = try encoder.encode(session)
            try write(data, to: sessionURL(session.id))
        } catch let encoding as EncodingError {
            let detail = Self.describe(encoding)
            logger.error(
                "Ambient session encode failed for \(session.id, privacy: .public): \(detail, privacy: .public)"
            )
        } catch {
            logger.error("Ambient session write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func describe(_ error: EncodingError) -> String {
        switch error {
        case .invalidValue(let value, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "invalidValue(\(String(describing: value))) at \(path): \(context.debugDescription)"
        @unknown default:
            return String(describing: error)
        }
    }

    /// Delete one note and every artifact it owns. The only path besides an
    /// explicit purge that destroys note text, and both are user-initiated.
    func delete(sessionID: String) {
        deletedSessionIDs.insert(sessionID)
        try? fileManager.removeItem(at: sessionURL(sessionID))
        removeAudio(sessionID: sessionID)
    }

    /// Remove every note, recording, and benchmark sample. Never touches the
    /// app's shared RAG index, which belongs to Chat.
    func purgeEverything() {
        finishRecording()
        try? fileManager.removeItem(at: sessionsDirectory)
        try? fileManager.removeItem(at: audioDirectory)
        try? fileManager.removeItem(at: benchmarksURL)
        deletedSessionIDs.removeAll()
        createDirectories()
        logger.info("Ambient memory purged")
    }

    /// Delete the *recordings* of notes older than the window, leaving the
    /// notes themselves untouched. Returns the ids whose audio went, so the
    /// caller can refresh its in-memory list.
    ///
    /// Expiry is scoped to audio on purpose: a recording is a temporary
    /// dogfood artifact that costs roughly 115 MB an hour, while the note is
    /// the thing the tester came for and outlives every window.
    @discardableResult
    func expireAudio(olderThan window: AmbientRetentionWindow, now: Date = Date()) -> [String] {
        guard let cutoff = window.expiryCutoff(from: now) else { return [] }

        var expired: [String] = []
        for var session in loadSessions() where session.hasAudio {
            guard (session.endedAt ?? session.startedAt) < cutoff else { continue }
            removeAudio(sessionID: session.id)
            session.audioRelativePath = nil
            save(session)
            expired.append(session.id)
        }
        if !expired.isEmpty {
            logger.info("Audio expiry removed \(expired.count) recording(s), notes kept")
        }
        return expired
    }

    // MARK: - Note Audio

    /// Open the note's recording. Every ingested buffer is appended to this one
    /// file, so playback is a real voice memo rather than a stitched-together
    /// set of speech fragments.
    func beginRecording(sessionID: String, sampleRate: Int) -> String? {
        finishRecording()
        let relativePath = Self.audioRelativePath(sessionID: sessionID)
        do {
            activeRecording = try WAVFileWriter(
                url: rootDirectory.appendingPathComponent(relativePath),
                sampleRate: sampleRate
            )
            return relativePath
        } catch {
            logger.error("Recording could not be opened: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func appendRecording(_ pcm16: Data) {
        guard let activeRecording else { return }
        do {
            try activeRecording.append(pcm16)
        } catch {
            // Keep the writer — a single failed append (e.g. brief lock race)
            // must not kill the rest of a multi-hour note.
            logger.error("Recording append failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Close the recording and stamp its real length into the header.
    func finishRecording() {
        guard let activeRecording else { return }
        self.activeRecording = nil
        do {
            try activeRecording.close()
        } catch {
            logger.error("Recording could not be finalized: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeAudio(sessionID: String) {
        try? fileManager.removeItem(
            at: rootDirectory.appendingPathComponent(Self.audioRelativePath(sessionID: sessionID))
        )
        // Notes recorded before the switch to one file per note kept a
        // directory of per-segment clips under the same id.
        try? fileManager.removeItem(at: audioDirectory.appendingPathComponent(sessionID, isDirectory: true))
    }

    func audioURL(for relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath)
    }

    private static func audioRelativePath(sessionID: String) -> String {
        "Audio/\(sessionID).wav"
    }

    // MARK: - Storage Accounting

    /// Bytes currently used by retained audio.
    func retainedAudioBytes() -> Int64 {
        directorySize(audioDirectory)
    }

    /// Bytes used by session documents plus retained audio.
    func totalBytes() -> Int64 {
        directorySize(rootDirectory)
    }

    /// Free space on the volume backing the Lab's storage.
    func availableCapacityBytes() -> Int64 {
        let values = try? rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Search

    /// Case-insensitive substring match across every note's title, summary,
    /// action items, and transcript, newest first. One hit per note, carrying
    /// the snippet around the match so the list can show why it matched.
    ///
    /// Deliberately plain text: the app's RAG index is single-tenant and
    /// belongs to Chat, so notes never touch it.
    nonisolated func search(_ query: String, in sessions: [AmbientSessionRecord]) -> [AmbientSearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        return sessions.compactMap { session -> AmbientSearchHit? in
            guard let match = Self.firstMatch(for: needle, in: session) else { return nil }
            return AmbientSearchHit(
                id: session.id,
                sessionID: session.id,
                kind: match.kind,
                snippet: match.snippet,
                timestamp: session.startedAt,
                sessionTitle: session.title
            )
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    /// Fields are checked most-summarized first so the snippet shown is the
    /// most readable place the term appears, not the first place it happens to
    /// occur in a raw transcript.
    private static func firstMatch(
        for needle: String,
        in session: AmbientSessionRecord
    ) -> (kind: AmbientSearchHit.Kind, snippet: String)? {
        if session.title.lowercased().contains(needle) {
            return (.title, session.title)
        }
        if session.summary.lowercased().contains(needle) {
            return (.summary, snippet(of: session.summary, around: needle))
        }
        if let item = session.actionItems.first(where: { $0.text.lowercased().contains(needle) }) {
            return (.actionItem, item.text)
        }
        let transcript = session.fullTranscript
        if transcript.lowercased().contains(needle) {
            return (.transcript, snippet(of: transcript, around: needle))
        }
        return nil
    }

    /// A window of text centered on the match, so a two-hour transcript shows
    /// the sentence that matched rather than its opening words.
    private static func snippet(of text: String, around needle: String, radius: Int = 60) -> String {
        guard let range = text.lowercased().range(of: needle) else { return String(text.prefix(140)) }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        let body = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = start == text.startIndex ? "" : "…"
        let suffix = end == text.endIndex ? "" : "…"
        return prefix + body + suffix
    }

    // MARK: - Benchmarks

    func loadBenchmarkSamples() -> [AmbientBenchmarkSample] {
        guard let data = try? Data(contentsOf: benchmarksURL) else { return [] }
        return (try? decoder.decode([AmbientBenchmarkSample].self, from: data)) ?? []
    }

    func append(_ sample: AmbientBenchmarkSample) {
        var samples = loadBenchmarkSamples()
        samples.append(sample)
        if samples.count > Self.maxBenchmarkSamples {
            samples = Array(samples.suffix(Self.maxBenchmarkSamples))
        }
        do {
            try write(try encoder.encode(samples), to: benchmarksURL)
        } catch {
            logger.error("Ambient benchmark write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearBenchmarkSamples() {
        try? fileManager.removeItem(at: benchmarksURL)
    }

    // MARK: - Private

    private static let maxBenchmarkSamples = 200

    private func createDirectories() {
        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    }

    private func sessionURL(_ id: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(id).json")
    }

    /// Atomic write that stays writable after the screen locks. Complete
    /// protection refuses every write while locked, which silently destroys
    /// mid-note transcripts for a background session.
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}

// MARK: - Search Hit

/// One matching note plus the snippet that matched, so the list can show why
/// the note came back before the tester opens it.
struct AmbientSearchHit: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable {
        case title
        case summary
        case actionItem
        case transcript

        var label: String {
            switch self {
            case .title: return "Title"
            case .summary: return "Summary"
            case .actionItem: return "Action item"
            case .transcript: return "Transcript"
            }
        }
    }

    let id: String
    let sessionID: String
    let kind: Kind
    let snippet: String
    let timestamp: Date
    let sessionTitle: String
}
