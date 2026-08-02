//
//  AmbientBenchmarkSheet.swift
//  RunAnywhereAI
//
//  Ambient run history and export. Kept separate from the synthetic STT
//  benchmark dashboard so a multi-hour, environment-dependent ambient run
//  never gets averaged into deterministic scenario numbers.
//

#if os(iOS)
import SwiftUI
import UIKit

struct AmbientBenchmarkSheet: View {
    @StateObject private var viewModel = AmbientBenchmarkViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var exportDocument: AmbientExportDocument?
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.samples.isEmpty {
                    VStack(spacing: AppSpacing.smallMedium) {
                        Text("No ambient runs recorded yet.")
                            .font(AppTypography.subheadlineMedium)
                        Text(
                            "Every session you stop writes one sample: VAD mode, warm-keep, "
                            + "stream-diar flags, RTF, RAM checkpoints, battery start/end, "
                            + "thermals, and post-pass Label/Summarize load times."
                        )
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(AppSpacing.large)
                } else {
                    List {
                        Section("Across \(viewModel.samples.count) runs") {
                            LabeledContent(
                                "Median RTF",
                                value: String(format: "%.2f", viewModel.medianRealTimeFactor)
                            )
                            LabeledContent(
                                "Median battery/hour",
                                value: String(format: "%.1f%%", viewModel.medianBatteryPerHour)
                            )
                            LabeledContent("Total listening", value: viewModel.totalListeningDescription)
                            LabeledContent(
                                "Action items done",
                                value: String(format: "%.0f%%", viewModel.completedActionItemRate * 100)
                            )
                        }

                        ForEach(Array(viewModel.samples.reversed())) { sample in
                            AmbientBenchmarkRow(sample: sample)
                        }
                    }
                }
            }
            .navigationTitle("Ambient Benchmarks")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Export CSV") { exportDocument = viewModel.csvDocument() }
                        Button("Export JSON") { exportDocument = viewModel.jsonDocument() }
                        Divider()
                        Button("Clear samples", role: .destructive) { showClearConfirmation = true }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.samples.isEmpty)
                }
            }
            .adaptiveSheet(isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            )) {
                if let exportDocument {
                    ActivityShareSheet(items: [exportDocument.url])
                }
            }
            .confirmationDialog(
                "Clear benchmark samples?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    Task { await viewModel.clear() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task { await viewModel.load() }
        }
    }
}

// MARK: - Row

struct AmbientBenchmarkRow: View {
    let sample: AmbientBenchmarkSample

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(sample.profileID.capitalized) · \(Self.formatter.string(from: sample.recordedAt))")
                .font(AppTypography.subheadlineMedium)
            Text(detailLine)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
            Text(environmentLine)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private var detailLine: String {
        if sample.runKind == "file" {
            return String(
                format: "file · convert %d · asr %d · diar %d · digest %d ms · peak %@",
                sample.convertMs,
                sample.asrMs,
                sample.diarizationMs,
                sample.digestMs,
                sample.peakMemoryBytes.formattedFileSize
            )
        }
        var battery = ""
        if sample.batteryLevelStart >= 0, sample.batteryLevelEnd >= 0 {
            battery = String(
                format: " · bat %.0f→%.0f%% (%.1f%%/h)",
                sample.batteryLevelStart * 100,
                sample.batteryLevelEnd * 100,
                sample.batteryDeltaPerHour
            )
        }
        return String(
            format: "%@ · %@ · RTF %.2f · first %.0f ms · peak %@%@",
            AmbientMemoryView.duration(Int(sample.sessionSeconds)),
            sample.vadMode,
            sample.medianRealTimeFactor,
            sample.firstTranscriptLatencyMs,
            sample.peakMemoryBytes.formattedFileSize,
            battery
        )
    }

    private var environmentLine: String {
        var parts = ["\(sample.segmentCount) segments", "\(sample.actionItemCount) action items"]
        parts.append("warm \(sample.warmKeep)")
        if sample.streamDiarEnabled {
            parts.append(sample.streamDiarUsed ? "stream-diar on" : "stream-diar skipped")
        }
        if sample.warmKeepDiarizationHit { parts.append("diar warm-hit") }
        if sample.warmKeepDigestHit { parts.append("digest warm-hit") }
        if sample.diarizationLoadMs > 0 { parts.append("diar-load \(sample.diarizationLoadMs)ms") }
        if sample.digestLoadMs > 0 { parts.append("digest-load \(sample.digestLoadMs)ms") }
        if sample.memoryAfterASRUnloadBytes > 0 {
            parts.append("after-asr \(sample.memoryAfterASRUnloadBytes.formattedFileSize)")
        }
        if sample.runKind == "file" {
            if let fixture = sample.fixtureName, !fixture.isEmpty { parts.insert(fixture, at: 0) }
            if sample.sectionCount > 0 { parts.append("\(sample.sectionCount) sections") }
            if sample.speakerCount > 0 { parts.append("\(sample.speakerCount) speakers") }
        }
        if sample.backpressureEventCount > 0 {
            parts.append("\(sample.backpressureEventCount) backpressure")
        } else if sample.droppedSegmentCount > 0 {
            parts.append("\(sample.droppedSegmentCount) dropped")
        }
        if sample.interruptionCount > 0 { parts.append("\(sample.interruptionCount) interruptions") }
        let thermal = sample.thermalStateEnd.isEmpty ? sample.thermalState : sample.thermalStateEnd
        if sample.thermalStateStart != thermal, !sample.thermalStateStart.isEmpty {
            parts.append("thermals \(sample.thermalStateStart)→\(thermal)")
        } else {
            parts.append("thermals \(thermal)")
        }
        if !sample.environment.isEmpty { parts.append(sample.environment) }
        if !sample.placement.isEmpty { parts.append(sample.placement) }
        return parts.joined(separator: " · ")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - View Model

@MainActor
final class AmbientBenchmarkViewModel: ObservableObject {
    @Published private(set) var samples: [AmbientBenchmarkSample] = []

    private let store = AmbientMemoryStore.shared

    func load() async {
        samples = await store.loadBenchmarkSamples()
    }

    func clear() async {
        await store.clearBenchmarkSamples()
        samples = []
    }

    var medianRealTimeFactor: Double {
        AmbientBenchmarkRecorder.median(samples.map(\.medianRealTimeFactor))
    }

    var medianBatteryPerHour: Double {
        AmbientBenchmarkRecorder.median(samples.map(\.batteryDeltaPerHour))
    }

    var totalListeningDescription: String {
        AmbientMemoryView.duration(Int(samples.reduce(0) { $0 + $1.sessionSeconds }))
    }

    var completedActionItemRate: Double {
        let total = samples.reduce(0) { $0 + $1.actionItemCount }
        guard total > 0 else { return 0 }
        let done = samples.reduce(0) { $0 + $1.completedActionItemCount }
        return Double(done) / Double(total)
    }

    // MARK: Export

    func csvDocument() -> AmbientExportDocument? {
        let header = [
            "recordedAt", "sessionId", "profile", "device", "chip", "os", "audioRoute",
            "environment", "placement", "sessionSeconds", "speechSeconds", "speechRatio",
            "segments", "transcribed", "dropped", "actionItems", "completedActionItems",
            "medianTranscriptionMs", "medianRTF", "medianDigestMs", "firstTranscriptMs",
            "peakMemoryBytes", "batteryPerHour", "thermalState", "interruptions", "retainedAudioBytes",
            "runKind", "convertMs", "asrMs", "diarizationMs", "digestMs",
            "sectionCount", "bulletCount", "speakerCount", "fixtureName",
            "vadMode", "warmKeep", "streamDiarEnabled", "streamDiarUsed",
            "availableMemoryAtStartBytes", "memoryAtStartBytes", "memoryPeakCaptureBytes",
            "memoryAfterASRUnloadBytes", "memoryAfterDiarizationBytes", "memoryAfterDigestBytes",
            "batteryLevelStart", "batteryLevelEnd", "thermalStateStart", "thermalStateEnd",
            "warmKeepDiarizationHit", "warmKeepDigestHit",
            "diarizationLoadMs", "digestLoadMs", "backpressureEventCount",
        ].joined(separator: ",")

        let rows = samples.map { Self.csvRow(for: $0) }
        return write(([header] + rows).joined(separator: "\n"), extension: "csv")
    }

    private static func csvRow(for sample: AmbientBenchmarkSample) -> String {
        let cells: [String] = [
            ISO8601DateFormatter().string(from: sample.recordedAt),
            sample.sessionID,
            sample.profileID,
            sample.deviceModel,
            sample.chipName,
            sample.osVersion,
            sample.audioRoute,
            sample.environment,
            sample.placement,
            String(format: "%.1f", sample.sessionSeconds),
            String(format: "%.1f", sample.speechSeconds),
            String(format: "%.3f", sample.speechRatio),
            String(sample.segmentCount),
            String(sample.transcribedSegmentCount),
            String(sample.droppedSegmentCount),
            String(sample.actionItemCount),
            String(sample.completedActionItemCount),
            String(format: "%.1f", sample.medianTranscriptionMs),
            String(format: "%.3f", sample.medianRealTimeFactor),
            String(format: "%.1f", sample.medianExtractionMs),
            String(format: "%.1f", sample.firstTranscriptLatencyMs),
            String(sample.peakMemoryBytes),
            String(format: "%.2f", sample.batteryDeltaPerHour),
            sample.thermalState,
            String(sample.interruptionCount),
            String(sample.retainedAudioBytes),
            sample.runKind,
            String(sample.convertMs),
            String(sample.asrMs),
            String(sample.diarizationMs),
            String(sample.digestMs),
            String(sample.sectionCount),
            String(sample.bulletCount),
            String(sample.speakerCount),
            sample.fixtureName ?? "",
            sample.vadMode,
            sample.warmKeep,
            sample.streamDiarEnabled ? "1" : "0",
            sample.streamDiarUsed ? "1" : "0",
            String(sample.availableMemoryAtStartBytes),
            String(sample.memoryAtStartBytes),
            String(sample.memoryPeakCaptureBytes),
            String(sample.memoryAfterASRUnloadBytes),
            String(sample.memoryAfterDiarizationBytes),
            String(sample.memoryAfterDigestBytes),
            String(format: "%.3f", sample.batteryLevelStart),
            String(format: "%.3f", sample.batteryLevelEnd),
            sample.thermalStateStart,
            sample.thermalStateEnd,
            sample.warmKeepDiarizationHit ? "1" : "0",
            sample.warmKeepDigestHit ? "1" : "0",
            String(sample.diarizationLoadMs),
            String(sample.digestLoadMs),
            String(sample.backpressureEventCount),
        ]
        return cells.map(escapeCSV).joined(separator: ",")
    }

    func jsonDocument() -> AmbientExportDocument? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(samples),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return write(text, extension: "json")
    }

    private func write(_ contents: String, extension pathExtension: String) -> AmbientExportDocument? {
        let name = "ambient-benchmarks-\(Int(Date().timeIntervalSince1970)).\(pathExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return AmbientExportDocument(url: url)
        } catch {
            return nil
        }
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

/// Identifiable wrapper so a freshly written export file can drive a sheet.
struct AmbientExportDocument: Identifiable {
    let url: URL
    var id: String { url.path }
}

// MARK: - Share Sheet

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
