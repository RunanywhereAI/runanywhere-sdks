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
    /// Only observe the offline runner at this level. Session / model-list
    /// observation lives in `AmbientMemoryInteractiveContent` so Metal digests
    /// cannot invalidate a heavy SwiftUI tree (scene-update watchdog).
    @ObservedObject private var offlineRunner = AmbientOfflineImportRunner.shared
    @ObservedObject private var ambientRouter = AmbientRouter.shared

    @State private var showDeveloper = false
    @State private var showPurgeConfirmation = false
    @State private var pendingAutoStart = false

    /// Set by the App Shortcut / Action Button deep link so recording starts as
    /// soon as the screen is up and consent is already in place.
    var autoStartRequested: Bool = false

    var body: some View {
        Group {
            if offlineRunner.isRunning {
                AmbientOfflineDogfoodOverlay(runner: offlineRunner)
            } else {
                AmbientMemoryInteractiveContent(
                    viewModel: viewModel,
                    offlineRunner: offlineRunner,
                    showDeveloper: $showDeveloper,
                    showPurgeConfirmation: $showPurgeConfirmation,
                    pendingAutoStart: $pendingAutoStart
                )
            }
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
                .disabled(offlineRunner.isRunning)
            }
        }
        .adaptiveSheet(isPresented: $showDeveloper) {
            AmbientDeveloperView(viewModel: viewModel)
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
            // Dogfood must not wait on registry/library refresh — that was
            // leaving the Notes sheet idle with no status while onAppear hung.
            if let dogfood = ambientRouter.consumeDogfood() {
                Task { await viewModel.onAppear() }
                await runDogfood(dogfood)
                return
            }
            await viewModel.onAppear()
            if autoStartRequested {
                pendingAutoStart = true
            }
        }
        .onChange(of: ambientRouter.pendingDogfood) { _, request in
            guard request != nil, let dogfood = ambientRouter.consumeDogfood() else { return }
            Task { await runDogfood(dogfood) }
        }
    }

    private func runDogfood(_ request: AmbientDogfoodRequest) async {
        if request.remergeOnly {
            _ = await offlineRunner.remergeMappedNotes(
                selection: viewModel.selection,
                digestModelOverride: request.digestModelID
            )
            await viewModel.refreshLibrary()
            return
        }
        if request.digestPendingOnly {
            _ = await offlineRunner.digestPendingNotes(
                selection: viewModel.selection,
                digestModelOverride: request.digestModelID,
                maxSourceChars: request.digestMaxChars,
                rewrite: request.rewriteDigest
            )
            await viewModel.refreshLibrary()
            return
        }
        guard viewModel.isCaptureStackReady else {
            viewModel.errorMessage = "Pick and download VAD + ASR before dogfood."
            return
        }
        _ = await offlineRunner.runAllFixtures(
            selection: viewModel.selection,
            labelSpeakers: request.labelSpeakers,
            summarize: request.summarize && !(viewModel.selection.digestModelID ?? "").isEmpty,
            context: viewModel.context
        )
        await viewModel.refreshLibrary()
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

/// Full-screen digester recovery — no Notes list, search field, or nav stack.
struct AmbientDigestPendingCover: View {
    @ObservedObject private var router = AmbientRouter.shared
    @ObservedObject private var runner = AmbientOfflineImportRunner.shared
    @StateObject private var viewModel = AmbientMemoryViewModel()

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Digest recovery")
                    .font(AppTypography.title3)
                AmbientOfflineDogfoodOverlay(runner: runner)
                if let err = runner.lastError ?? viewModel.errorMessage {
                    Text(err)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.statusRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !runner.isRunning {
                    Button("Close") {
                        router.isDigestPendingCoverPresented = false
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.mediumLarge)
        }
        .interactiveDismissDisabled(runner.isRunning)
        .task {
            guard let request = router.consumeDogfood() else { return }
            // Do not await registry refresh — that blocked digests earlier.
            Task { await viewModel.onAppear() }
            if request.remergeOnly {
                _ = await runner.remergeMappedNotes(
                    selection: viewModel.selection,
                    digestModelOverride: request.digestModelID
                )
            } else {
                _ = await runner.digestPendingNotes(
                    selection: viewModel.selection,
                    digestModelOverride: request.digestModelID,
                    maxSourceChars: request.digestMaxChars,
                    rewrite: request.rewriteDigest
                )
            }
            await viewModel.refreshLibrary()
        }
    }
}

/// Minimal overlay — observes only the offline runner so AttributeGraph stays quiet.
struct AmbientOfflineDogfoodOverlay: View {
    @ObservedObject var runner: AmbientOfflineImportRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            offlineLiveCard
            Text("Screen may freeze for a few minutes while the digester loads — that is expected. Do not lock the phone.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.statusOrange)
                .fixedSize(horizontal: false, vertical: true)
            Text("Status updates only between chunks. A stuck spinner does not mean it failed.")
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.mediumLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transaction { $0.animation = nil }
    }

    private var offlineLiveCard: some View {
        let live = runner.live
        let status = runner.statusMessage.isEmpty ? live.stage : runner.statusMessage
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(live.fixtureName.isEmpty ? "Offline digest" : live.fixtureName)
                        .font(AppTypography.subheadlineMedium)
                    Text(status.isEmpty ? "Starting…" : status)
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            ProgressView(value: max(0.02, live.progress))
                .tint(AppColors.primaryBlue)
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Full Notes chrome — mounted only when offline dogfood is not running.
private struct AmbientMemoryInteractiveContent: View {
    @ObservedObject var viewModel: AmbientMemoryViewModel
    @ObservedObject var offlineRunner: AmbientOfflineImportRunner
    @ObservedObject private var session = AmbientSessionManager.shared
    @ObservedObject private var modelList = ModelListViewModel.shared

    @Binding var showDeveloper: Bool
    @Binding var showPurgeConfirmation: Bool
    @Binding var pendingAutoStart: Bool

    @State private var showConsent = false
    @State private var showVADPicker = false
    @State private var showASRPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                modelsSection
                recordControl
                if isCapturing { liveRow }
                if !offlineRunner.live.recentLines.isEmpty || !offlineRunner.statusMessage.isEmpty {
                    offlineLiveCard
                }
                if let warning = warningMessage { warningLine(warning) }
                if let error = session.lastError ?? viewModel.errorMessage ?? offlineRunner.lastError {
                    errorBanner(error)
                }
                searchField
                notesList
            }
            .padding(AppSpacing.mediumLarge)
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
        .onChange(of: pendingAutoStart) { _, should in
            guard should else { return }
            pendingAutoStart = false
            Task {
                if !viewModel.hasRecordingConsent {
                    showConsent = true
                } else if viewModel.canStartSession, !session.isRecording {
                    await viewModel.startSession()
                }
            }
        }
        .task {
            if pendingAutoStart {
                pendingAutoStart = false
                if !viewModel.hasRecordingConsent {
                    showConsent = true
                } else if viewModel.canStartSession, !session.isRecording {
                    await viewModel.startSession()
                }
            }
        }
    }

    /// Live offline import — mirrors the recording row so file dogfood feels
    /// like capture: progress, RTF, and streaming transcript lines.
    private var offlineLiveCard: some View {
        let live = offlineRunner.live
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if offlineRunner.isRunning {
                    ProgressView()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(live.fixtureName.isEmpty ? "Offline import" : live.fixtureName)
                        .font(AppTypography.subheadlineMedium)
                    Text(offlineRunner.statusMessage.isEmpty ? live.stage : offlineRunner.statusMessage)
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if live.realtimeFactor > 0 {
                    Text(String(format: "%.1f×", live.realtimeFactor))
                        .font(AppTypography.captionMedium)
                        .foregroundColor(AppColors.statusGreen)
                }
            }

            ProgressView(value: live.progress)
                .tint(AppColors.primaryBlue)

            HStack {
                Text("\(Self.clock(live.processedAudioMs)) / \(Self.clock(live.totalAudioMs))")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text("\(live.transcribedCount)/\(live.segmentCount) turns")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }

            // Only show a short tail — animating large transcript stacks during
            // ASR/digest contended with Metal and tripped iOS's 10s scene watchdog.
            if live.stage == "Transcribing", let line = live.recentLines.last, !line.isEmpty {
                Text(line)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(AppColors.backgroundPrimary.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transaction { $0.animation = nil }
    }

    private static func clock(_ ms: Int) -> String {
        let totalSec = max(0, ms / 1000)
        return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
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

            Text("Pick a summarizing LLM on each note when you tap Summarize — it is not needed to record.")
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)

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
                Text(AmbientMemoryView.duration(session.elapsedSeconds))
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

                if record.summary.isEmpty,
                   !record.fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   record.digestModelID != nil || record.summaryPending {
                    Text("Tap to summarize")
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
