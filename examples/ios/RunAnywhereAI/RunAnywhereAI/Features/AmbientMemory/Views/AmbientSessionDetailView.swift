//
//  AmbientSessionDetailView.swift
//  RunAnywhereAI
//
//  One note with Notion-like Summary / Speakers / Transcript tabs,
//  structured sections, citation chips, and seek-to-turn playback.
//

#if os(iOS)
import AVFoundation
import SwiftUI

private enum NoteDetailTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case speakers = "Speakers"
    case transcript = "Transcript"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .summary: return "list.bullet.rectangle"
        case .speakers: return "person.2.wave.2"
        case .transcript: return "text.alignleft"
        }
    }
}

struct AmbientSessionDetailView: View {
    let sessionID: String
    @ObservedObject var viewModel: AmbientMemoryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: NoteDetailTab = .summary
    @State private var showDeleteConfirmation = false
    @State private var showDigestPicker = false
    @State private var showDiarizationPicker = false
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var draftItem = ""
    @State private var draftSummary = ""
    @State private var summaryNoteID: String?
    @State private var summarySaveTask: Task<Void, Never>?
    @State private var renamingSpeakerFrom: String?
    @State private var draftSpeakerName = ""
    @State private var highlightedSegmentID: String?
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
                    if var note = viewModel.note(id: sessionID) {
                        note.digestModelID = model.id
                        await AmbientMemoryStore.shared.save(note)
                        await viewModel.refreshLibrary()
                    }
                }
            }
        }
        .adaptiveSheet(isPresented: $showDiarizationPicker) {
            ModelSelectionSheet(context: .diarization) { model in
                Task { await viewModel.selectDiarizationModel(model, for: sessionID) }
            }
        }
        .alert(
            "Rename speaker",
            isPresented: Binding(
                get: { renamingSpeakerFrom != nil },
                set: { if !$0 { renamingSpeakerFrom = nil } }
            )
        ) {
            TextField("Name", text: $draftSpeakerName)
            Button("Save") {
                if let from = renamingSpeakerFrom {
                    let name = draftSpeakerName
                    Task { await viewModel.renameSpeaker(from: from, to: name, in: sessionID) }
                }
                renamingSpeakerFrom = nil
            }
            Button("Cancel", role: .cancel) { renamingSpeakerFrom = nil }
        } message: {
            Text("Applies to every turn currently labeled \(renamingSpeakerFrom ?? "this speaker").")
        }
        .onDisappear { player.stop() }
        .onAppear { syncSummaryDraft(from: record) }
        .onChange(of: record?.summary) { _, _ in
            syncSummaryDraft(from: record, onlyIfIdle: true)
        }
        .onChange(of: viewModel.sessionManager.isSummarizing) { _, busy in
            if !busy { syncSummaryDraft(from: record) }
        }
    }

    private func syncSummaryDraft(from record: AmbientSessionRecord?, onlyIfIdle: Bool = false) {
        guard let record else { return }
        if onlyIfIdle, summaryNoteID == record.id, draftSummary != record.summary {
            if !record.summary.isEmpty, draftSummary.isEmpty {
                draftSummary = record.summary
                summaryNoteID = record.id
            }
            return
        }
        draftSummary = record.summary
        summaryNoteID = record.id
    }

    private func content(for record: AmbientSessionRecord) -> some View {
        VStack(spacing: 0) {
            headerBar(record)
            tabPicker
            tabBody(record)
        }
    }

    private func headerBar(_ record: AmbientSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Self.dateFormatter.string(from: record.startedAt)) · "
                + AmbientMemoryView.duration(Int(record.duration)))
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
            if let path = record.audioRelativePath {
                AmbientRecordingPlayerView(relativePath: path, player: player) {
                    await viewModel.audioURL(for: path)
                }
            }
        }
        .padding(.horizontal, AppSpacing.mediumLarge)
        .padding(.vertical, AppSpacing.smallMedium)
    }

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(NoteDetailTab.allCases) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppSpacing.mediumLarge)
        .padding(.bottom, AppSpacing.smallMedium)
    }

    @ViewBuilder
    private func tabBody(_ record: AmbientSessionRecord) -> some View {
        switch selectedTab {
        case .summary:
            List {
                summarizeControls(record)
                actionItemsSection(record)
                structuredSummarySection(record)
            }
            .listStyle(.insetGrouped)
        case .speakers:
            List { speakersSection(record) }
                .listStyle(.insetGrouped)
        case .transcript:
            List { transcriptSection(record) }
                .listStyle(.insetGrouped)
        }
    }

    // MARK: - Summarize controls

    @ViewBuilder
    private func summarizeControls(_ record: AmbientSessionRecord) -> some View {
        let hasTranscript = !record.fullTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let digestID = record.digestModelID ?? viewModel.selection.digestModelID
        let busy = viewModel.sessionManager.isSummarizing
            || viewModel.sessionManager.isLabelingSpeakers
            || record.isSpeakerLabelingBusy
        let status = viewModel.sessionManager.statusMessage

        Section {
            Button { showDigestPicker = true } label: {
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

            if viewModel.sessionManager.isSummarizing {
                let progress = viewModel.sessionManager.digestChunkProgress
                let progressText = progress.total > 0
                    ? "Chunk \(min(progress.completed + 1, progress.total))/\(progress.total)"
                    : nil
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        status.isEmpty ? "Loading the summarizing model…" : status,
                        systemImage: "brain"
                    )
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryAccent)
                    if let progressText {
                        Text(progressText)
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textSecondary)
                        ProgressView(
                            value: Double(progress.completed),
                            total: Double(max(progress.total, 1))
                        )
                    }
                    Text("Keep this screen open — locking the phone pauses the digester.")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.statusOrange)
                }
            } else if record.hasResumableDigest {
                Text("Digester paused after \(record.digestMapChunksCompleted) chunk(s). Resume to finish the full note.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.statusOrange)
            } else if record.digestStale {
                Text("Speakers were labeled after this summary. Rewrite to include who said what.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.statusOrange)
            } else if let error = viewModel.sessionManager.lastError,
                      !viewModel.sessionManager.isLabelingSpeakers {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.statusRed)
            }

            if hasTranscript {
                if record.hasResumableDigest {
                    Button {
                        if digestID == nil {
                            showDigestPicker = true
                        } else {
                            Task { await viewModel.summarize(sessionID: sessionID, modelID: digestID) }
                        }
                    } label: {
                        Label(
                            viewModel.sessionManager.isSummarizing
                                ? "Resuming…"
                                : "Resume digester",
                            systemImage: "play.fill"
                        )
                    }
                    .disabled(busy)
                } else if record.summary.isEmpty, !record.hasStructuredDigest {
                    Button {
                        if digestID == nil {
                            showDigestPicker = true
                        } else {
                            Task { await viewModel.summarize(sessionID: sessionID, modelID: digestID) }
                        }
                    } label: {
                        Label(
                            viewModel.sessionManager.isSummarizing ? "Summarizing…" : "Summarize with LLM",
                            systemImage: "text.badge.star"
                        )
                    }
                    .disabled(busy)
                } else {
                    Button {
                        Task { await viewModel.rewriteSummary(sessionID: sessionID, modelID: digestID) }
                    } label: {
                        Label(
                            viewModel.sessionManager.isSummarizing
                                ? "Rewriting…"
                                : (record.digestStale
                                    ? "Rewrite with speakers"
                                    : "Rewrite summary & action items"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(busy || digestID == nil)

                    if record.partialSummaries.count > 1 {
                        Button {
                            Task { await viewModel.remergeSummary(sessionID: sessionID, modelID: digestID) }
                        } label: {
                            Label(
                                viewModel.sessionManager.isSummarizing
                                    ? "Re-merging…"
                                    : "Rebuild summary from chunks",
                                systemImage: "square.stack.3d.up"
                            )
                        }
                        .disabled(busy || digestID == nil)
                    }
                }
            }
        }
    }

    // MARK: - Structured summary

    @ViewBuilder
    private func structuredSummarySection(_ record: AmbientSessionRecord) -> some View {
        let busy = viewModel.sessionManager.isSummarizing

        if record.hasStructuredDigest {
            ForEach(record.digestSections) { section in
                Section(section.heading) {
                    ForEach(section.bullets) { bullet in
                        VStack(alignment: .leading, spacing: 6) {
                            bulletText(bullet)
                            if !bullet.sourceSegmentIDs.isEmpty {
                                citationRow(ids: bullet.sourceSegmentIDs, in: record)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } else {
            Section("Overview") {
                TextEditor(text: $draftSummary)
                    .font(AppTypography.body)
                    .frame(minHeight: 120)
                    .disabled(busy)
                    .onChange(of: draftSummary) { _, newValue in
                        summarySaveTask?.cancel()
                        summarySaveTask = Task {
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            guard !Task.isCancelled else { return }
                            await viewModel.updateSummary(sessionID: sessionID, to: newValue)
                        }
                    }
                    .onDisappear {
                        summarySaveTask?.cancel()
                        Task { await viewModel.updateSummary(sessionID: sessionID, to: draftSummary) }
                    }

                if draftSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Type a summary, or choose an LLM and tap Summarize for a structured draft.")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func bulletText(_ bullet: AmbientDigestBullet) -> some View {
        if bullet.lead.isEmpty {
            Text(bullet.text)
                .font(AppTypography.callout)
                .foregroundColor(AppColors.textPrimary)
        } else {
            (Text(bullet.lead).fontWeight(.semibold) + Text(": \(bullet.text)"))
                .font(AppTypography.callout)
                .foregroundColor(AppColors.textPrimary)
        }
    }

    private func citationRow(ids: [String], in record: AmbientSessionRecord) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(ids.enumerated()), id: \.offset) { _, segmentID in
                if let segment = record.segments.first(where: { $0.id == segmentID }) {
                    Button {
                        jumpToSegment(segment, in: record)
                    } label: {
                        Text("\(segment.index)")
                            .font(AppTypography.caption2.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Circle().fill(AppColors.backgroundSecondary))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func jumpToSegment(_ segment: AmbientSegmentRecord, in record: AmbientSessionRecord) {
        highlightedSegmentID = segment.id
        selectedTab = .transcript
        let offsetMs = segment.startOffsetMs
            ?? AmbientSpeakerAlignment.recordingIntervals(for: [segment]).first?.startMs
            ?? 0
        let seconds = Double(offsetMs) / 1000.0
        if let path = record.audioRelativePath {
            Task {
                if let url = await viewModel.audioURL(for: path) {
                    player.prepare(url: url, key: path)
                    player.seek(to: seconds, key: path)
                    player.play(url: url, key: path)
                }
            }
        }
    }

    // MARK: - Action items

    @ViewBuilder
    private func actionItemsSection(_ record: AmbientSessionRecord) -> some View {
        Section("Action items") {
            if record.actionItems.isEmpty {
                Text("No action items yet — Summarize to extract them.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            ForEach(record.actionItems) { item in
                VStack(alignment: .leading, spacing: 6) {
                    EditableActionItemRow(
                        item: item,
                        onToggle: {
                            Task { await viewModel.toggleActionItem(item.id, in: sessionID) }
                        },
                        onSaveText: { text in
                            Task { await viewModel.updateActionItem(item.id, text: text, in: sessionID) }
                        }
                    )
                    if !item.sourceSegmentIDs.isEmpty {
                        citationRow(ids: item.sourceSegmentIDs, in: record)
                    }
                }
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

    // MARK: - Speakers

    @ViewBuilder
    private func speakersSection(_ record: AmbientSessionRecord) -> some View {
        let hasTranscript = !record.fullTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let busy = viewModel.sessionManager.isLabelingSpeakers || record.isSpeakerLabelingBusy
        let summarizing = viewModel.sessionManager.isSummarizing
        let diarizationID = record.diarizationModelID

        Section("Speakers") {
            Text(
                "Optional. Choose a speaker model, download it, then label who spoke. "
                    + "Your transcript stays saved either way."
            )
            .font(AppTypography.caption2)
            .foregroundColor(AppColors.textSecondary)

            Button { showDiarizationPicker = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speaker model")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Text(
                            diarizationID.map { viewModel.displayName(for: $0) }
                                ?? "Not selected"
                        )
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textPrimary)
                    }
                    Spacer()
                    Text(diarizationID == nil ? "Choose" : "Change")
                        .font(AppTypography.caption)
                }
            }
            .disabled(busy || summarizing)

            speakerStatusRow(record)

            if !record.hasAudio {
                Text("No recording on this note — keep audio when recording to enable labeling.")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
            } else if hasTranscript {
                Button {
                    if diarizationID == nil {
                        showDiarizationPicker = true
                    } else {
                        Task {
                            await viewModel.labelSpeakers(
                                sessionID: sessionID,
                                modelID: diarizationID
                            )
                        }
                    }
                } label: {
                    Label(
                        speakerActionTitle(for: record, busy: busy),
                        systemImage: "person.2.wave.2"
                    )
                }
                .disabled(busy || summarizing || !record.hasAudio)
            }

            if record.hasSpeakerLabels {
                let labels = Array(Set(record.segments.compactMap(\.speakerLabel))).sorted()
                ForEach(labels, id: \.self) { label in
                    Button {
                        draftSpeakerName = label
                        renamingSpeakerFrom = label
                    } label: {
                        HStack {
                            Text(label)
                                .font(AppTypography.callout)
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text("Rename")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .disabled(busy)
                }
            }
        }
    }

    @ViewBuilder
    private func speakerStatusRow(_ record: AmbientSessionRecord) -> some View {
        switch record.speakerLabelingState {
        case .notConfigured:
            EmptyView()
        case .modelSelected:
            Text("Model ready — tap Label speakers when you want to run it.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        case .loadingModel:
            Label(
                record.speakerLabelingDetail ?? "Loading speaker model…",
                systemImage: "arrow.down.circle"
            )
            .font(AppTypography.caption)
            .foregroundColor(AppColors.primaryAccent)
        case .labeling:
            Label(
                record.speakerLabelingDetail ?? "Labeling speakers…",
                systemImage: "waveform"
            )
            .font(AppTypography.caption)
            .foregroundColor(AppColors.primaryAccent)
        case .completed:
            Label(
                record.speakerLabelingDetail ?? "Speakers labeled.",
                systemImage: "checkmark.circle.fill"
            )
            .font(AppTypography.caption)
            .foregroundColor(AppColors.statusGreen)
        case .interrupted:
            Text(
                record.speakerLabelingDetail
                    ?? "Labeling interrupted — your transcript is safe. Tap Resume to try again."
            )
            .font(AppTypography.caption)
            .foregroundColor(AppColors.statusOrange)
        case .failed:
            Text(record.speakerLabelingDetail ?? "Speaker labeling failed.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.statusRed)
        }
    }

    private func speakerActionTitle(for record: AmbientSessionRecord, busy: Bool) -> String {
        if busy {
            switch record.speakerLabelingState {
            case .loadingModel: return "Loading speaker model…"
            default: return "Labeling speakers…"
            }
        }
        switch record.speakerLabelingState {
        case .completed: return "Re-label speakers"
        case .interrupted: return "Resume labeling"
        case .failed: return "Retry labeling"
        case .notConfigured: return "Choose speaker model"
        case .modelSelected, .loadingModel, .labeling: return "Label speakers"
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptSection(_ record: AmbientSessionRecord) -> some View {
        Section("Transcript") {
            if record.fullTranscript.isEmpty {
                Text("No speech was captured.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            } else {
                ForEach(record.transcribedSegments) { segment in
                    Button {
                        jumpToSegment(segment, in: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if let speaker = segment.speakerLabel {
                                    Text(speaker)
                                        .font(AppTypography.caption.weight(.semibold))
                                        .foregroundColor(AppColors.primaryAccent)
                                } else {
                                    Text("Turn \(segment.index)")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                Spacer()
                                Text(Self.clock(segment.startOffsetMs ?? 0))
                                    .font(AppTypography.caption2.monospacedDigit())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            Text(segment.transcript ?? "")
                                .font(AppTypography.callout)
                                .foregroundColor(AppColors.textPrimary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    highlightedSegmentID == segment.id
                                        ? AppColors.primaryAccent.opacity(0.12)
                                        : Color.clear
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static func clock(_ offsetMs: Int) -> String {
        let total = max(0, offsetMs) / 1000
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Checkmark + editable text for one action item.
private struct EditableActionItemRow: View {
    let item: AmbientActionItem
    let onToggle: () -> Void
    let onSaveText: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.smallMedium) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isDone ? AppColors.statusGreen : AppColors.textSecondary)
            }
            .buttonStyle(.plain)

            TextField("Action item", text: $draft, axis: .vertical)
                .font(AppTypography.callout)
                .foregroundColor(item.isDone ? AppColors.textSecondary : AppColors.textPrimary)
                .strikethrough(item.isDone)
                .focused($focused)
                .onAppear { draft = item.text }
                .onChange(of: item.text) { _, newValue in
                    if !focused { draft = newValue }
                }
                .onChange(of: focused) { _, isFocused in
                    guard !isFocused, draft != item.text else { return }
                    onSaveText(draft)
                }
                .onSubmit { onSaveText(draft) }
        }
    }
}

// MARK: - Playback

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

@MainActor
final class AmbientNotePlayer: NSObject, ObservableObject {
    @Published private(set) var playingKey: String?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastError: String?

    private var player: AVAudioPlayer?
    private var loadedKey: String?
    private var tick: Timer?
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
