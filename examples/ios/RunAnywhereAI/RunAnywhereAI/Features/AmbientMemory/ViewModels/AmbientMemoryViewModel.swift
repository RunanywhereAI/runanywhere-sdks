//
//  AmbientMemoryViewModel.swift
//  RunAnywhereAI
//
//  State for the offline notes screens: the notes list, global text search,
//  note editing, free model picks, storage accounting, and deletion.
//
//  Capture itself belongs to `AmbientSessionManager`; this view model reads
//  that manager and owns everything around a recording.
//
//  Nothing here touches the app's RAG index. That index is single-tenant and
//  belongs to Chat's document Q&A: indexing notes into it would let a question
//  about an attached PDF retrieve private recordings, and attaching a document
//  would wipe whatever notes had put there. Search is plain text instead.
//

#if os(iOS)
import Combine
import Foundation
import RunAnywhere
import os

@MainActor
final class AmbientMemoryViewModel: ObservableObject {

    // MARK: - Setup

    @Published var selectedProfileID: String = AmbientModelProfile.quality.id
    /// Explicit user picks only — never auto-filled from a profile on appear.
    @Published var selection: AmbientModelSelection = AmbientModelSelection(
        profileID: AmbientModelProfile.quality.id,
        vadModelID: "",
        asrModelID: ""
    )
    @Published var retentionPolicy: AmbientRetentionPolicy = .default
    @Published var audioExpiry: AmbientRetentionWindow = .default
    @Published var context = AmbientCaptureContext.empty
    @Published private(set) var conditions: AmbientDeviceConditions?
    @Published private(set) var recommendedProfileID: String?

    /// One-time consent, shown as a first-run sheet so recording afterwards is
    /// a single tap.
    @Published private(set) var hasRecordingConsent = false

    // MARK: - Library

    @Published private(set) var sessions: [AmbientSessionRecord] = []
    @Published var searchText = ""
    @Published private(set) var searchHits: [AmbientSearchHit] = []
    @Published private(set) var storageBytes: Int64 = 0
    @Published private(set) var retainedAudioBytes: Int64 = 0

    @Published private(set) var errorMessage: String?

    // MARK: - Collaborators

    private let logger = Logger(subsystem: "com.runanywhere", category: "AmbientNotes")
    private let store = AmbientMemoryStore.shared
    private let resolver = AmbientModelProfileResolver()
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var hasLoaded = false

    let sessionManager = AmbientSessionManager.shared

    var profile: AmbientModelProfile {
        AmbientModelProfile.profile(id: selectedProfileID) ?? .quality
    }

    /// True when VAD and ASR have been picked and their files are on disk.
    var isCaptureStackReady: Bool {
        isDownloaded(selection.vadModelID) && isDownloaded(selection.asrModelID)
    }

    /// Recording is one tap once consent has been given and the capture stack
    /// is on disk — any framework the user chose, including GPU ASR.
    var canStartSession: Bool {
        hasRecordingConsent && isCaptureStackReady && !sessionManager.isCapturing
    }

    /// Shown when Record cannot start because a required model is unset or not
    /// downloaded yet. Never points the user at the Models tab.
    var missingModelMessage: String? {
        guard !isCaptureStackReady else { return nil }
        if selection.vadModelID.isEmpty || selection.asrModelID.isEmpty {
            return "Pick and download a speech detector and a transcription model below."
        }
        return "Download the speech detector and transcription model below to start recording."
    }

    /// Soft warning when a GPU ASR was chosen, or when summarizing will wait
    /// for the foreground after a Lock Screen stop — Record stays enabled.
    var backgroundRiskMessage: String? {
        var parts: [String] = []
        if !selection.asrModelID.isEmpty, !selection.isASRBackgroundSafe {
            parts.append(
                "This transcription model uses the GPU, so lock-screen transcription may stall."
            )
        }
        if selection.digestModelID != nil {
            parts.append(
                "Summarizing finishes when the app is open — stopping from the Lock Screen saves the note and summarizes on return."
            )
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    func modelInfo(for modelID: String) -> RAModelInfo? {
        guard !modelID.isEmpty else { return nil }
        return ModelListViewModel.shared.availableModels.first { $0.id == modelID }
    }

    func displayName(for modelID: String) -> String {
        guard !modelID.isEmpty else { return "None" }
        if let model = modelInfo(for: modelID) {
            return model.consumerDisplayName
        }
        return modelID
    }

    func isDownloaded(_ modelID: String) -> Bool {
        guard !modelID.isEmpty, let model = modelInfo(for: modelID) else { return false }
        return model.isBuiltIn || model.localPathURL != nil
    }

    /// Notes matching the current query, or every note when the field is empty.
    var visibleSessions: [AmbientSessionRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return sessions }
        let order = Dictionary(uniqueKeysWithValues: searchHits.enumerated().map { ($0.element.sessionID, $0.offset) })
        return sessions
            .filter { order[$0.id] != nil }
            .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    func searchHit(for sessionID: String) -> AmbientSearchHit? {
        searchHits.first { $0.sessionID == sessionID }
    }

    var totalActionItemCount: Int {
        sessions.reduce(0) { $0 + $1.actionItems.count }
    }

    var totalSegmentCount: Int {
        sessions.reduce(0) { $0 + $1.segments.count }
    }

    // MARK: - Lifecycle

    func onAppear() async {
        if ModelListViewModel.shared.availableModels.isEmpty {
            await ModelListViewModel.shared.loadModelsFromRegistry()
        }
        refreshConditions()
        guard !hasLoaded else {
            refreshBackgroundFlags()
            await refreshLibrary()
            return
        }
        hasLoaded = true
        restoreSettings()
        observeSearch()
        observeDeferredMerges()
        await store.expireAudio(olderThan: audioExpiry)
        await refreshLibrary()
    }

    func refreshConditions() {
        let current = resolver.currentConditions(deviceInfo: DeviceInfoService.shared.deviceInfo)
        conditions = current
        recommendedProfileID = resolver.recommendedProfile(
            for: current,
            available: ModelListViewModel.shared.availableModels
        ).id
    }

    /// Explicit Developer action: copy this profile's preferred catalog IDs
    /// into the three slots. Does not download anything.
    func applyProfile(_ profileID: String) {
        selectedProfileID = profileID
        let resolved = resolver.resolve(
            profile: AmbientModelProfile.profile(id: profileID) ?? .quality,
            available: ModelListViewModel.shared.availableModels
        )
        selection = resolved
        persistSettings()
    }

    func select(vad model: RAModelInfo) {
        selection.vadModelID = model.id
        persistSettings()
    }

    func select(asr model: RAModelInfo) {
        selection.asrModelID = model.id
        selection.isASRBackgroundSafe = model.isBackgroundSafe
        persistSettings()
    }

    func select(digest model: RAModelInfo?) {
        selection.digestModelID = model?.id
        selection.isDigestBackgroundSafe = model?.isBackgroundSafe ?? true
        persistSettings()
    }

    func clearDigest() {
        select(digest: nil)
    }

    func grantRecordingConsent() {
        hasRecordingConsent = true
        persistSettings()
    }

    func setRetention(_ policy: AmbientRetentionPolicy) {
        retentionPolicy = policy
        persistSettings()
    }

    /// Change how long recordings are kept. Note text is never affected.
    func setAudioExpiry(_ window: AmbientRetentionWindow) {
        audioExpiry = window
        persistSettings()
        Task {
            await store.expireAudio(olderThan: window)
            await refreshLibrary()
        }
    }

    // MARK: - Capture

    func startSession() async {
        guard canStartSession else { return }
        refreshConditions()
        guard let conditions else { return }
        await sessionManager.start(
            selection: selection,
            retention: retentionPolicy,
            context: context,
            conditions: conditions
        )
    }

    func stopSession() async {
        await sessionManager.stop()
        await refreshLibrary()
    }

    /// Re-run summarization for a note that has a transcript but no summary.
    func retrySummary(sessionID: String) async {
        await sessionManager.retrySummary(for: sessionID)
        await refreshLibrary()
    }

    func togglePause() async {
        if sessionManager.phase == .paused {
            await sessionManager.resume()
        } else {
            await sessionManager.pause()
        }
    }

    // MARK: - Library

    func refreshLibrary() async {
        sessions = await store.loadSessions()
        storageBytes = await store.totalBytes()
        retainedAudioBytes = await store.retainedAudioBytes()
        updateSearchResults()
    }

    func note(id: String) -> AmbientSessionRecord? {
        sessions.first { $0.id == id }
    }

    func delete(sessionID: String) async {
        await store.delete(sessionID: sessionID)
        await refreshLibrary()
    }

    /// Remove every note, recording, and benchmark sample. Deliberately leaves
    /// the shared RAG index alone: it holds Chat's attached document, not
    /// anything this feature wrote.
    func purgeEverything() async {
        await store.purgeEverything()
        await refreshLibrary()
    }

    /// Absolute location of a note's recording, or `nil` once the audio has
    /// expired or been purged.
    func audioURL(for relativePath: String) async -> URL? {
        let url = await store.audioURL(for: relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Note Editing

    func rename(sessionID: String, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        await update(sessionID: sessionID) { note in
            note.customTitle = trimmed.isEmpty ? nil : trimmed
        }
    }

    func toggleActionItem(_ itemID: String, in sessionID: String) async {
        await update(sessionID: sessionID) { note in
            guard let index = note.actionItems.firstIndex(where: { $0.id == itemID }) else { return }
            note.actionItems[index].isDone.toggle()
        }
    }

    func addActionItem(_ text: String, to sessionID: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await update(sessionID: sessionID) { note in
            note.actionItems.append(AmbientActionItem(text: trimmed, isManual: true))
        }
    }

    func deleteActionItem(_ itemID: String, from sessionID: String) async {
        await update(sessionID: sessionID) { note in
            note.actionItems.removeAll { $0.id == itemID }
        }
    }

    private func update(sessionID: String, _ mutate: (inout AmbientSessionRecord) -> Void) async {
        guard var note = sessions.first(where: { $0.id == sessionID }) else { return }
        mutate(&note)
        await store.save(note)
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index] = note
        }
    }

    // MARK: - Search

    private func observeSearch() {
        $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateSearchResults()
            }
            .store(in: &cancellables)
    }

    /// A note whose merge was deferred to the foreground has just gained its
    /// summary, so the list has to reload to stop showing "Summary pending".
    private func observeDeferredMerges() {
        sessionManager.didFinishDeferredMerge
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.refreshLibrary() }
            }
            .store(in: &cancellables)
    }

    private func updateSearchResults() {
        searchHits = store.search(searchText, in: sessions)
    }

    // MARK: - Settings Persistence

    private enum SettingsKey {
        static let profile = "ambient.profileID"
        static let vad = "ambient.vadModelID"
        static let asr = "ambient.asrModelID"
        static let digest = "ambient.digestModelID"
        static let retention = "ambient.retentionPolicy"
        static let window = "ambient.audioExpiryWindow"
        static let consent = "ambient.recordingConsent"
    }

    /// Restore saved picks only — never fill empty slots from a profile.
    private func restoreSettings() {
        selectedProfileID = defaults.string(forKey: SettingsKey.profile) ?? AmbientModelProfile.quality.id
        retentionPolicy = defaults.string(forKey: SettingsKey.retention)
            .flatMap(AmbientRetentionPolicy.init(rawValue:)) ?? .default
        if defaults.object(forKey: SettingsKey.window) != nil {
            audioExpiry = AmbientRetentionWindow(rawValue: defaults.integer(forKey: SettingsKey.window))
                ?? .default
        }
        hasRecordingConsent = defaults.bool(forKey: SettingsKey.consent)

        selection = AmbientModelSelection(
            profileID: selectedProfileID,
            vadModelID: defaults.string(forKey: SettingsKey.vad) ?? "",
            asrModelID: defaults.string(forKey: SettingsKey.asr) ?? "",
            digestModelID: defaults.string(forKey: SettingsKey.digest)
        )
        refreshBackgroundFlags()
    }

    private func refreshBackgroundFlags() {
        if let asr = modelInfo(for: selection.asrModelID) {
            selection.isASRBackgroundSafe = asr.isBackgroundSafe
        } else if selection.asrModelID.isEmpty {
            selection.isASRBackgroundSafe = true
        }
        if let digestID = selection.digestModelID, let digest = modelInfo(for: digestID) {
            selection.isDigestBackgroundSafe = digest.isBackgroundSafe
        } else {
            selection.isDigestBackgroundSafe = true
        }
    }

    private func persistSettings() {
        defaults.set(selectedProfileID, forKey: SettingsKey.profile)
        defaults.set(selection.vadModelID, forKey: SettingsKey.vad)
        defaults.set(selection.asrModelID, forKey: SettingsKey.asr)
        defaults.set(selection.digestModelID, forKey: SettingsKey.digest)
        defaults.set(retentionPolicy.rawValue, forKey: SettingsKey.retention)
        defaults.set(audioExpiry.rawValue, forKey: SettingsKey.window)
        defaults.set(hasRecordingConsent, forKey: SettingsKey.consent)
    }
}
#endif
