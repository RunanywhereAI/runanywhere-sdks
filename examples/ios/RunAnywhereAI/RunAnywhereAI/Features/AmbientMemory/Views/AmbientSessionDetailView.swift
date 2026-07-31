//
//  AmbientSessionDetailView.swift
//  RunAnywhereAI
//
//  One note: its summary, action items, the continuous transcript, and
//  playback of the recording.
//

#if os(iOS)
import AVFoundation
import SwiftUI

struct AmbientSessionDetailView: View {
    let sessionID: String
    @ObservedObject var viewModel: AmbientMemoryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showDigestPicker = false
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var draftItem = ""
    @StateObject private var player = AmbientNotePlayer()

    private var record: AmbientSessionRecord? {
        viewModel.note(id: sessionID)
    }

    var body: some View {
        Group {
            if let record {
                content(for: record)
            } else {
                Text("This note is no longer on the device.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .navigationTitle(record?.title ?? "Note")
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Rename") {
                        draftTitle = record?.customTitle ?? record?.title ?? ""
                        isRenaming = true
                    }
                    Divider()
                    Button("Delete note", role: .destructive) { showDeleteConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(record == nil)
            }
        }
        .alert("Rename note", isPresented: $isRenaming) {
            TextField("Title", text: $draftTitle)
            Button("Save") {
                Task { await viewModel.rename(sessionID: sessionID, to: draftTitle) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it empty to go back to the summary-derived title.")
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete summary, transcript, and recording", role: .destructive) {
                Task {
                    player.stop()
                    await viewModel.delete(sessionID: sessionID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .adaptiveSheet(isPresented: $showDigestPicker) {
            ModelSelectionSheet(context: .llm) { model in
                viewModel.select(digest: model)
                Task {
                    // Persist the choice on this note so Rewrite reuses it.
                    if var note = viewModel.note(id: sessionID) {
                        note.digestModelID = model.id
                        await AmbientMemoryStore.shared.save(note)
                        await viewModel.refreshLibrary()
                    }
                }
            }
        }
        .onDisappear { player.stop() }
    }

    private func content(for record: AmbientSessionRecord) -> some View {
        List {
            summarySection(record)
            actionItemsSection(record)
            transcriptSection(record)
            recordingSection(record)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summarySection(_ record: AmbientSessionRecord) -> some View {
        let hasTranscript = !record.fullTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let digestID = record.digestModelID ?? viewModel.selection.digestModelID
        let busy = viewModel.sessionManager.isSummarizing
        let status = viewModel.sessionManager.statusMessage

        Section("Summary") {
            // LLM pick lives here — recording only needs VAD + ASR.
            Button {
                showDigestPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Summarizing model")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text(viewModel.displayName(for: digestID ?? ""))
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textPrimary)
                    }
                    Spacer()
                    Text(digestID == nil ? "Choose" : "Change")
                        .font(AppTypography.caption)
                }
            }
            .disabled(busy)

            if busy {
                Label(
                    status.isEmpty ? "Loading the summarizing model…" : status,
                    systemImage: "brain"
                )
                .font(AppTypography.caption)
                .foregroundColor(AppColors.primaryAccent)
            } else if let error = viewModel.sessionManager.lastError {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.statusRed)
            } else if record.summary.isEmpty, hasTranscript {
                Text(
                    digestID == nil
                        ? "Choose an LLM above, then tap Summarize."
                        : "Tap Summarize to load the LLM and write summary + action items."
                )
                .font(AppTypography.caption)
                .foregroundColor(AppColors.statusOrange)
            } else if record.summary.isEmpty {
                Text(hasTranscript ? "No summary yet." : "Nothing was said worth summarizing.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            } else {
                Text(record.summary)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textPrimary)
            }

            if hasTranscript {
                if record.summary.isEmpty {
                    Button {
                        if digestID == nil {
                            showDigestPicker = true
                        } else {
                            Task { await viewModel.summarize(sessionID: sessionID, modelID: digestID) }
                        }
                    } label: {
                        Label(
                            busy ? "Summarizing…" : "Summarize with LLM",
                            systemImage: "text.badge.star"
                        )
                    }
                    .disabled(busy)
                } else {
                    Button {
                        Task { await viewModel.rewriteSummary(sessionID: sessionID, modelID: digestID) }
                    } label: {
                        Label(
                            busy ? "Rewriting…" : "Rewrite summary & action items",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(busy || digestID == nil)
                }
            }

            Text("\(Self.dateFormatter.string(from: record.startedAt)) · "
                + AmbientMemoryView.duration(Int(record.duration)))
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Action Items

    @ViewBuilder
    private func actionItemsSection(_ record: AmbientSessionRecord) -> some View {
        Section("Action items") {
            ForEach(record.actionItems) { item in
                Button {
                    Task { await viewModel.toggleActionItem(item.id, in: sessionID) }
                } label: {
                    HStack(alignment: .top, spacing: AppSpacing.smallMedium) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(item.isDone ? AppColors.statusGreen : AppColors.textSecondary)
                        Text(item.text)
                            .font(AppTypography.callout)
                            .foregroundColor(item.isDone ? AppColors.textSecondary : AppColors.textPrimary)
                            .strikethrough(item.isDone)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteActionItem(item.id, from: sessionID) }
                    }
                }
            }

            HStack {
                TextField("Add item", text: $draftItem)
                    .font(AppTypography.callout)
                    .onSubmit { addItem() }
                Button("Add") { addItem() }
                    .font(AppTypography.caption)
                    .disabled(draftItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addItem() {
        let text = draftItem
        draftItem = ""
        Task { await viewModel.addActionItem(text, to: sessionID) }
    }

    // MARK: - Transcript and Recording

    @ViewBuilder
    private func transcriptSection(_ record: AmbientSessionRecord) -> some View {
        Section("Transcript") {
            if record.fullTranscript.isEmpty {
                Text("No speech was captured.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            } else {
                Text(record.fullTranscript)
                    .font(AppTypography.callout)
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func recordingSection(_ record: AmbientSessionRecord) -> some View {
        Section("Recording") {
            if let path = record.audioRelativePath {
                AmbientRecordingPlayerView(relativePath: path, player: player) {
                    await viewModel.audioURL(for: path)
                }
            } else {
                Text("Recording removed to save space.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Playback

/// Voice Memos-style transport: play/pause, scrubber, and elapsed/remaining.
struct AmbientRecordingPlayerView: View {
    let relativePath: String
    @ObservedObject var player: AmbientNotePlayer
    let resolveURL: () async -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
            HStack(spacing: AppSpacing.mediumLarge) {
                Button {
                    Task { await toggle() }
                } label: {
                    Image(systemName: player.isPlaying(relativePath) ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AppColors.primaryAccent)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { player.displayProgress(for: relativePath) },
                            set: { player.seek(to: $0, key: relativePath) }
                        ),
                        in: 0...max(player.duration(for: relativePath), 0.01)
                    )
                    .tint(AppColors.primaryAccent)

                    HStack {
                        Text(Self.format(player.displayProgress(for: relativePath)))
                        Spacer()
                        Text(Self.format(player.duration(for: relativePath)))
                    }
                    .font(AppTypography.caption2.monospacedDigit())
                    .foregroundColor(AppColors.textSecondary)
                }
            }

            if let error = player.lastError {
                Text(error)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.statusRed)
            }
        }
        .task {
            // Load duration even before the first play so the scrubber isn't empty.
            if let url = await resolveURL() {
                player.prepare(url: url, key: relativePath)
            }
        }
    }

    private func toggle() async {
        if player.isPlaying(relativePath) {
            player.pause()
            return
        }
        if player.isLoaded(relativePath) {
            player.resume()
            return
        }
        guard let url = await resolveURL() else {
            player.reportMissingFile()
            return
        }
        player.play(url: url, key: relativePath)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Plays a note's recording with seek support.
///
/// `AVAudioPlayer` streams the WAV from disk, which matters because a note can
/// run for hours and decoding one into memory would not fit.
@MainActor
final class AmbientNotePlayer: NSObject, ObservableObject {
    @Published private(set) var playingKey: String?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastError: String?

    private var player: AVAudioPlayer?
    private var loadedKey: String?
    private var tick: Timer?
    /// True while the user is dragging the scrubber so the timer doesn't fight them.
    private var isScrubbing = false

    func isPlaying(_ key: String) -> Bool {
        playingKey == key && (player?.isPlaying ?? false)
    }

    func isLoaded(_ key: String) -> Bool { loadedKey == key && player != nil }

    func duration(for key: String) -> TimeInterval {
        loadedKey == key ? duration : 0
    }

    func displayProgress(for key: String) -> TimeInterval {
        loadedKey == key ? currentTime : 0
    }

    /// Open the file to learn its duration without starting playback.
    func prepare(url: URL, key: String) {
        guard loadedKey != key else { return }
        do {
            try configureSession()
            let prepared = try AVAudioPlayer(contentsOf: url)
            prepared.prepareToPlay()
            player = prepared
            loadedKey = key
            playingKey = nil
            duration = prepared.duration
            currentTime = 0
            lastError = nil
        } catch {
            lastError = "Could not open the recording: \(error.localizedDescription)"
            clearEngine()
        }
    }

    func play(url: URL, key: String) {
        if loadedKey != key || player == nil {
            prepare(url: url, key: key)
        }
        guard let player else { return }
        do {
            try configureSession()
            player.delegate = self
            player.play()
            playingKey = key
            lastError = nil
            startTicking()
        } catch {
            lastError = "Could not play the recording: \(error.localizedDescription)"
            clearEngine()
        }
    }

    func pause() {
        player?.pause()
        playingKey = nil
        stopTicking()
        currentTime = player?.currentTime ?? currentTime
    }

    func resume() {
        guard let player, loadedKey != nil else { return }
        do {
            try configureSession()
            player.play()
            playingKey = loadedKey
            lastError = nil
            startTicking()
        } catch {
            lastError = "Could not resume playback: \(error.localizedDescription)"
        }
    }

    func seek(to time: TimeInterval, key: String) {
        guard loadedKey == key, let player else { return }
        isScrubbing = true
        let clamped = min(max(0, time), max(player.duration, 0))
        player.currentTime = clamped
        currentTime = clamped
        isScrubbing = false
    }

    func stop() {
        stopTicking()
        player?.stop()
        clearEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func reportMissingFile() {
        lastError = "Recording file is missing or was never finished."
    }

    private func configureSession() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
    }

    private func startTicking() {
        stopTicking()
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickProgress() }
        }
    }

    private func stopTicking() {
        tick?.invalidate()
        tick = nil
    }

    private func tickProgress() {
        guard !isScrubbing, let player else { return }
        currentTime = player.currentTime
        duration = player.duration
        if !player.isPlaying, playingKey != nil {
            // Ended or interrupted without the delegate firing.
            playingKey = nil
            stopTicking()
        }
    }

    private func clearEngine() {
        player = nil
        loadedKey = nil
        playingKey = nil
        currentTime = 0
        duration = 0
    }
}

extension AmbientNotePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.currentTime = self.duration
            self.playingKey = nil
            self.stopTicking()
        }
    }
}
#endif
