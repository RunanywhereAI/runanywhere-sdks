//
//  AmbientDeveloperView.swift
//  RunAnywhereAI
//
//  Everything a tester needs and a user does not: optional profile presets,
//  the same free model pickers as the Notes screen, audio expiry, capture
//  labels, device conditions, storage, and the benchmark export.
//

#if os(iOS)
import RunAnywhere
import SwiftUI
import UniformTypeIdentifiers

struct AmbientDeveloperView: View {
    @ObservedObject var viewModel: AmbientMemoryViewModel
    @ObservedObject private var modelList = ModelListViewModel.shared
    @ObservedObject private var offlineRunner = AmbientOfflineImportRunner.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showBenchmarks = false
    @State private var showVADPicker = false
    @State private var showASRPicker = false
    @State private var showDigestPicker = false
    @State private var showImporter = false
    @State private var dogfoodLabelSpeakers = true
    @State private var dogfoodSummarize = true

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                modelSection
                performanceSection
                offlineDogfoodSection
                audioSection
                contextSection
                deviceSection
                benchmarkSection
            }
            .navigationTitle("Developer")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .adaptiveSheet(isPresented: $showBenchmarks) {
                AmbientBenchmarkSheet()
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
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, UTType(filenameExtension: "wav")].compactMap { $0 },
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task { await importAndRun(url) }
            }
            .task {
                if modelList.availableModels.isEmpty {
                    await modelList.loadModelsFromRegistry()
                }
            }
        }
    }

    // MARK: - Offline dogfood

    private var offlineDogfoodSection: some View {
        Section {
            Toggle("Label speakers after ASR", isOn: $dogfoodLabelSpeakers)
            Toggle("Structured digest after ASR", isOn: $dogfoodSummarize)

            Button("Import audio file…") { showImporter = true }
                .disabled(offlineRunner.isRunning || !viewModel.isCaptureStackReady)

            Button("Run all Fixtures") {
                Task { await runAllFixtures() }
            }
            .disabled(offlineRunner.isRunning || !viewModel.isCaptureStackReady)

            if offlineRunner.isRunning || !offlineRunner.statusMessage.isEmpty {
                Text(offlineRunner.statusMessage)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            if let metrics = offlineRunner.lastMetrics {
                Text(Self.metricsSummary(metrics))
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
            if let error = offlineRunner.lastError {
                Text(error)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.statusOrange)
            }
        } header: {
            Text("Long-audio dogfood")
        } footer: {
            Text(
                "Drop WAV/m4a into Documents/AmbientMemory/Fixtures, or import one file. "
                + "Stages: convert → offline ASR → optional Sortformer → structured digest. "
                + "Metrics land in Benchmark samples (runKind=file)."
            )
        }
    }

    private func importAndRun(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard viewModel.isCaptureStackReady else { return }
        _ = await offlineRunner.run(
            fileURL: url,
            selection: viewModel.selection,
            labelSpeakers: dogfoodLabelSpeakers,
            summarize: dogfoodSummarize && !(viewModel.selection.digestModelID ?? "").isEmpty,
            context: viewModel.context
        )
        await viewModel.refreshLibrary()
    }

    private func runAllFixtures() async {
        guard viewModel.isCaptureStackReady else { return }
        _ = await offlineRunner.runAllFixtures(
            selection: viewModel.selection,
            labelSpeakers: dogfoodLabelSpeakers,
            summarize: dogfoodSummarize && !(viewModel.selection.digestModelID ?? "").isEmpty,
            context: viewModel.context
        )
        await viewModel.refreshLibrary()
    }

    private static func metricsSummary(_ m: AmbientFileRunMetrics) -> String {
        var parts = [
            "\(m.fixtureName)",
            "convert \(m.convertMs)ms",
            "asr \(m.asrMs)ms",
            "first \(m.firstTranscriptMs)ms",
        ]
        if m.diarizationMs > 0 { parts.append("diar \(m.diarizationMs)ms") }
        if m.digestMs > 0 { parts.append("digest \(m.digestMs)ms") }
        parts.append("segs \(m.segmentCount)")
        if m.sectionCount > 0 { parts.append("sections \(m.sectionCount)") }
        parts.append("peak \(m.peakMemoryBytes.formattedFileSize)")
        return parts.joined(separator: " · ")
    }

    // MARK: - Profile

    private var profileSection: some View {
        Section {
            Picker("Profile", selection: profileBinding) {
                ForEach(AmbientModelProfile.allProfiles) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.profile.summary)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            if let recommended = viewModel.recommendedProfileID,
               recommended != viewModel.selectedProfileID,
               let profile = AmbientModelProfile.profile(id: recommended) {
                Button("Apply recommended \(profile.displayName) IDs") {
                    viewModel.applyProfile(recommended)
                }
                .font(AppTypography.caption)
            }
        } header: {
            Text("Lab profile preset")
        } footer: {
            Text(
                "Applying a profile copies VAD + ASR candidates only. "
                + "Summarizer is never auto-selected — pick one under Models when you want digests. "
                + "Nothing downloads automatically — use Change → Get → Use for each role."
            )
        }
    }

    private var profileBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedProfileID },
            set: { viewModel.applyProfile($0) }
        )
    }

    // MARK: - Models

    private var modelSection: some View {
        Section {
            modelButtonRow(
                title: "Speech detector",
                modelID: viewModel.selection.vadModelID
            ) { showVADPicker = true }

            modelButtonRow(
                title: "Transcription",
                modelID: viewModel.selection.asrModelID
            ) { showASRPicker = true }

            modelButtonRow(
                title: "Summarizing",
                modelID: viewModel.selection.digestModelID ?? ""
            ) { showDigestPicker = true }

            if viewModel.selection.digestModelID != nil {
                Button("Clear summarizer", role: .destructive) {
                    viewModel.clearDigest()
                }
                .font(AppTypography.caption)
            }

            if let risk = viewModel.backgroundRiskMessage {
                Text(risk)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.statusOrange)
            }
        } header: {
            Text("Models")
        } footer: {
            Text(
                "Capture needs detector + transcription. Summarizer is optional — leave it unset until you want digests. "
                + "Any catalog model is allowed, including GPU backends. "
                + "A soft warning appears when lock-screen transcription or background summarizing may stall."
            )
        }
    }

    private func modelButtonRow(
        title: String,
        modelID: String,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                Text(viewModel.displayName(for: modelID))
                    .font(AppTypography.body)
                    .lineLimit(1)
                Text(viewModel.isDownloaded(modelID) ? "Ready" : (modelID.isEmpty ? "Not set" : "Needs download"))
                    .font(AppTypography.caption2)
                    .foregroundColor(
                        viewModel.isDownloaded(modelID)
                            ? AppColors.statusGreen
                            : AppColors.statusOrange
                    )
            }
            Spacer()
            Button("Change", action: onChange)
                .font(AppTypography.caption)
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        Section {
            Picker("Live VAD", selection: vadModeBinding) {
                Text("Silero (quality)").tag(RAAmbientVADMode.silero)
                Text("Economy (energy)").tag(RAAmbientVADMode.economy)
                Text("Hybrid").tag(RAAmbientVADMode.hybrid)
            }

            Picker("Warm-keep", selection: warmKeepBinding) {
                ForEach(AmbientWarmKeepTarget.allCases, id: \.self) { target in
                    Text(target.displayName).tag(target)
                }
            }

            Toggle("Stream Sortformer during capture", isOn: streamDiarBinding)

            if let conditions = viewModel.conditions {
                let canStream = viewModel.performanceSettings.canStreamDiarization(
                    availableMemoryBytes: conditions.availableMemoryBytes,
                    tier: conditions.tier
                )
                if viewModel.performanceSettings.streamDiarDuringCapture && !canStream {
                    Text("Needs high-end tier and ~1.8 GB free (ASR + Sortformer).")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.statusOrange)
                }
            }
        } header: {
            Text("Capture performance")
        } footer: {
            Text(
                "Economy VAD skips Silero on every frame (best for long locked sessions). "
                + "Warm-keep leaves Sortformer or the digester resident between Label/Summarize — never both, never with ASR. "
                + "Streaming Sortformer hides diarization wall time behind recording when RAM allows."
            )
        }
    }

    private var vadModeBinding: Binding<RAAmbientVADMode> {
        Binding(
            get: { viewModel.performanceSettings.vadMode },
            set: { viewModel.setVADMode($0) }
        )
    }

    private var warmKeepBinding: Binding<AmbientWarmKeepTarget> {
        Binding(
            get: { viewModel.performanceSettings.warmKeep },
            set: { viewModel.setWarmKeep($0) }
        )
    }

    private var streamDiarBinding: Binding<Bool> {
        Binding(
            get: { viewModel.performanceSettings.streamDiarDuringCapture },
            set: { viewModel.setStreamDiarDuringCapture($0) }
        )
    }

    // MARK: - Audio

    private var audioSection: some View {
        Section {
            Picker("Keep", selection: retentionBinding) {
                ForEach(AmbientRetentionPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Picker("Delete recordings", selection: expiryBinding) {
                ForEach(AmbientRetentionWindow.allCases) { window in
                    Text(window.displayName).tag(window)
                }
            }

            LabeledContent("Recordings") {
                Text(viewModel.retainedAudioBytes.formattedFileSize)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            LabeledContent("Everything") {
                Text(viewModel.storageBytes.formattedFileSize)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        } header: {
            Text("Recordings and storage")
        } footer: {
            Text(
                "Expiry deletes recordings only — a note's summary, action items, and transcript are kept "
                + "until you delete the note. Audio costs roughly 115 MB per hour."
            )
        }
    }

    private var retentionBinding: Binding<AmbientRetentionPolicy> {
        Binding(
            get: { viewModel.retentionPolicy },
            set: { viewModel.setRetention($0) }
        )
    }

    private var expiryBinding: Binding<AmbientRetentionWindow> {
        Binding(
            get: { viewModel.audioExpiry },
            set: { viewModel.setAudioExpiry($0) }
        )
    }

    // MARK: - Context

    private var contextSection: some View {
        Section {
            TextField("Environment (quiet, office, café, car…)", text: $viewModel.context.environment)
            TextField("Placement (desk, pocket, face down…)", text: $viewModel.context.placement)
            TextField("Note", text: $viewModel.context.note)
        } header: {
            Text("Capture labels")
        } footer: {
            Text(
                "Labels are stored with the note and its benchmark sample so multi-hour runs "
                + "stay comparable across environments."
            )
        }
    }

    // MARK: - Device

    @ViewBuilder
    private var deviceSection: some View {
        if let conditions = viewModel.conditions {
            Section("This device") {
                LabeledContent("Tier", value: conditions.tier.displayName)
                LabeledContent("Available memory", value: conditions.availableMemoryBytes.formattedFileSize)
                LabeledContent("Thermal state", value: conditions.thermalDescription)
                LabeledContent("Low Power Mode", value: conditions.isLowPowerModeEnabled ? "On" : "Off")
                if conditions.batteryLevel >= 0 {
                    LabeledContent("Battery", value: "\(Int(conditions.batteryLevel * 100))%")
                }
            }
        }
    }

    private var benchmarkSection: some View {
        Section {
            Button("Benchmark samples") { showBenchmarks = true }
            LabeledContent("Notes", value: "\(viewModel.sessions.count)")
            LabeledContent("Segments", value: "\(viewModel.totalSegmentCount)")
            LabeledContent("Action items", value: "\(viewModel.totalActionItemCount)")
        } header: {
            Text("Instrumentation")
        }
    }
}
#endif
