//
//  AmbientMemoryView.swift
//  RunAnywhereAI
//
//  The notes screen: one Record button, a live row while recording, global
//  search, and the notes list. Pure SwiftUI — capture and inference live in
//  `AmbientSessionManager` and the SDK's ambient solution.
//

#if os(iOS)
import RunAnywhere
import SwiftUI

struct AmbientMemoryView: View {
    @StateObject private var viewModel = AmbientMemoryViewModel()
    @ObservedObject private var session = AmbientSessionManager.shared
    /// Observed so Ready / Needs download labels refresh after Get in a sheet.
    @ObservedObject private var modelList = ModelListViewModel.shared

    @State private var showDeveloper = false
    @State private var showPurgeConfirmation = false
    @State private var showConsent = false
    @State private var showVADPicker = false
    @State private var showASRPicker = false
    @State private var showDigestPicker = false

    /// Set by the App Shortcut / Action Button deep link so recording starts as
    /// soon as the screen is up and consent is already in place.
    var autoStartRequested: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                modelsSection
                recordControl
                if isCapturing { liveRow }
                if let warning = warningMessage { warningLine(warning) }
                if let error = session.lastError ?? viewModel.errorMessage { errorBanner(error) }
                searchField
                notesList
            }
            .padding(AppSpacing.mediumLarge)
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Developer") { showDeveloper = true }
                    Divider()
                    Button("Delete everything", role: .destructive) { showPurgeConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .adaptiveSheet(isPresented: $showDeveloper) {
            AmbientDeveloperView(viewModel: viewModel)
        }
        .adaptiveSheet(isPresented: $showConsent) {
            AmbientConsentSheet {
                viewModel.grantRecordingConsent()
                showConsent = false
                Task { await viewModel.startSession() }
            }
        }
        .adaptiveSheet(isPresented: $showVADPicker) {
            ModelSelectionSheet(context: .vad) { model in
                viewModel.select(vad: model)
            }
        }
        .adaptiveSheet(isPresented: $showASRPicker) {
            ModelSelectionSheet(context: .stt) { model in
                viewModel.select(asr: model)
            }
        }
        .adaptiveSheet(isPresented: $showDigestPicker) {
            ModelSelectionSheet(context: .llm) { model in
                viewModel.select(digest: model)
            }
        }
        .confirmationDialog(
            "Delete every note?",
            isPresented: $showPurgeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete all notes and recordings", role: .destructive) {
                Task { await viewModel.purgeEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every transcript, summary, action item, recording, and benchmark sample.")
        }
        .task {
            await viewModel.onAppear()
            if autoStartRequested, viewModel.canStartSession, !session.isRecording {
                await viewModel.startSession()
            }
        }
    }

    private var isCapturing: Bool {
        session.isRecording || session.phase == .paused || session.phase == .preparing
    }

    // MARK: - Models

    /// Free picks for each role — any catalog model, Get/Use in the sheet.
    private var modelsSection: some View {
        // Touch the list so downloads in a sheet invalidate Ready labels.
        let _ = modelList.availableModels.count
        return AmbientCard {
            Text("Models")
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textPrimary)

            modelRow(
                title: "Speech detector",
                modelID: viewModel.selection.vadModelID,
                required: true
            ) { showVADPicker = true }

            modelRow(
                title: "Transcription",
                modelID: viewModel.selection.asrModelID,
                required: true
            ) { showASRPicker = true }

            modelRow(
                title: "Summarizing",
                modelID: viewModel.selection.digestModelID ?? "",
                required: false
            ) { showDigestPicker = true }

            if let risk = viewModel.backgroundRiskMessage {
                Text(risk)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.statusOrange)
            }
        }
    }

    private func modelRow(
        title: String,
        modelID: String,
        required: Bool,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.smallMedium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                Text(viewModel.displayName(for: modelID))
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Text(statusLabel(for: modelID, required: required))
                    .font(AppTypography.caption2)
                    .foregroundColor(statusColor(for: modelID, required: required))
            }
            Spacer(minLength: AppSpacing.small)
            Button("Change", action: onChange)
                .font(AppTypography.caption)
                .buttonStyle(.bordered)
                .disabled(isCapturing)
        }
    }

    private func statusLabel(for modelID: String, required: Bool) -> String {
        if modelID.isEmpty {
            return required ? "Required" : "Optional"
        }
        return viewModel.isDownloaded(modelID) ? "Ready" : "Download in picker"
    }

    private func statusColor(for modelID: String, required: Bool) -> Color {
        if modelID.isEmpty {
            return required ? AppColors.statusOrange : AppColors.textSecondary
        }
        return viewModel.isDownloaded(modelID) ? AppColors.statusGreen : AppColors.statusOrange
    }

    // MARK: - Record

    private var recordControl: some View {
        VStack(spacing: AppSpacing.smallMedium) {
            Button {
                Task { await toggleRecording() }
            } label: {
                Label(
                    isCapturing ? "Stop" : "Record",
                    systemImage: isCapturing ? "stop.fill" : "mic.fill"
                )
                .font(AppTypography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.small)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCapturing ? AppColors.statusRed : AppColors.primaryAccent)
            .disabled(!isCapturing && viewModel.missingModelMessage != nil)

            // Avoid duplicating the red error banner — fail() sets both.
            if !session.statusMessage.isEmpty, session.statusMessage != session.lastError {
                Text(session.statusMessage)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func toggleRecording() async {
        if isCapturing {
            await viewModel.stopSession()
            return
        }
        guard viewModel.isCaptureStackReady else { return }
        guard viewModel.hasRecordingConsent else {
            // First run: take consent once, then record on one tap forever after.
            showConsent = true
            return
        }
        await viewModel.startSession()
    }

    private var liveRow: some View {
        AmbientCard {
            HStack {
                Label(session.phase.displayName, systemImage: "waveform")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.statusRed)
                Spacer()
                Text(Self.duration(session.elapsedSeconds))
                    .font(AppTypography.caption.monospacedDigit())
                    .foregroundColor(AppColors.textSecondary)
                Button(session.phase == .paused ? "Resume" : "Pause") {
                    Task { await viewModel.togglePause() }
                }
                .font(AppTypography.caption)
                .buttonStyle(.bordered)
            }

            AmbientLevelMeter(level: session.audioLevel)

            if !session.liveTranscript.isEmpty {
                Text(session.liveTranscript)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    /// Missing-model copy, then any active resource gate — background-risk
    /// soft-warn lives under the Models section so Record stays available.
    private var warningMessage: String? {
        if let missing = viewModel.missingModelMessage, !isCapturing { return missing }
        return session.activeGates.values.sorted().first
    }

    // MARK: - Notes

    private var searchField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textSecondary)
            TextField("Search all notes", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.smallMedium)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
        )
    }

    @ViewBuilder
    private var notesList: some View {
        let notes = viewModel.visibleSessions
        if notes.isEmpty {
            Text(
                viewModel.searchText.isEmpty
                    ? "No notes yet. Tap Record to make your first one."
                    : "No notes match that search."
            )
            .font(AppTypography.caption)
            .foregroundColor(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVStack(spacing: AppSpacing.small) {
                ForEach(notes) { record in
                    NavigationLink {
                        AmbientSessionDetailView(sessionID: record.id, viewModel: viewModel)
                    } label: {
                        AmbientCard {
                            AmbientSessionRow(record: record, hit: viewModel.searchHit(for: record.id))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Building Blocks

    private func warningLine(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(AppTypography.caption)
            .foregroundColor(AppColors.statusOrange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundColor(AppColors.statusRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.small)
            .background(
                AppColors.statusRed.opacity(0.1),
                in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
            )
    }

    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Consent

/// Shown once, before the first recording. Consent is a property of the
/// feature rather than of each session, so recording afterwards is one tap.
struct AmbientConsentSheet: View {
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                Text("Recording a note")
                    .font(AppTypography.title3)
                    .foregroundColor(AppColors.textPrimary)

                Text(
                    "A note records this room until you press Stop, and stays visible in a Live Activity "
                    + "the whole time. Speech detection, transcription, and summarizing all run on this "
                    + "device; nothing is uploaded."
                )
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)

                Text(
                    "The recording is kept alongside the transcript so you can hear what the model heard. "
                    + "Delete a note to remove both, or set an audio expiry under Developer."
                )
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

                Spacer()

                Button("Start recording") { onAccept() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(AppSpacing.mediumLarge)
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Shared Components

struct AmbientCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.mediumLarge)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
        )
    }
}

struct AmbientLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(AppColors.statusGreen)
                    .frame(width: geometry.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

struct AmbientSessionRow: View {
    let record: AmbientSessionRecord
    /// Present while searching, so the row can show the text that matched
    /// instead of the summary the note usually leads with.
    var hit: AmbientSearchHit?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)

                if let hit {
                    Text(hit.snippet)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                    Text(hit.kind.label)
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                } else {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                if record.summaryPending {
                    Text("Summary pending")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.statusOrange)
                } else if let reason = record.stopReason {
                    Text(reason)
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.statusOrange)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, AppSpacing.xSmall)
    }

    private var subtitle: String {
        var parts = [AmbientMemoryView.duration(Int(record.duration))]
        let open = record.actionItems.filter { !$0.isDone }.count
        if open > 0 { parts.append("\(open) to do") }
        if record.hasAudio { parts.append("Recording") }
        return parts.joined(separator: " · ")
    }
}
#endif
