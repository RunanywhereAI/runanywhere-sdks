//
//  AmbientBenchmarkRecorder.swift
//  RunAnywhereAI
//
//  Instrumentation for a live ambient session.
//
//  Deliberately separate from `BenchmarkRunner`: that suite measures
//  deterministic synthetic scenarios, and folding a multi-hour, environment-
//  dependent ambient run into it would change what its STT numbers mean.
//  This recorder produces `AmbientBenchmarkSample`s that export alongside them.
//

import Foundation
import RunAnywhere
#if os(iOS)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Accumulates per-session timings while a session runs, then reduces them to
/// one exportable sample when it ends.
@MainActor
final class AmbientBenchmarkRecorder {

    private var sessionID: String?
    private var startedAt: Date?
    private var conditions: AmbientDeviceConditions?
    private var startBatteryLevel: Float = -1
    private var audioRoute: String = "unknown"

    private var speechMilliseconds = 0
    private var segmentCount = 0
    private var droppedSegmentCount = 0
    private var backpressureEventCount = 0
    private var interruptionCount = 0
    private var transcriptionMs: [Double] = []
    private var realTimeFactors: [Double] = []
    private var extractionMs: [Double] = []
    private var firstTranscriptLatencyMs: Double?
    private var peakMemoryBytes: Int64 = 0

    // Performance feature config + resource checkpoints
    private var vadMode = "silero"
    private var warmKeep = "none"
    private var streamDiarEnabled = false
    private var streamDiarUsed = false
    private var availableMemoryAtStartBytes: Int64 = 0
    private var memoryAtStartBytes: Int64 = 0
    private var memoryPeakCaptureBytes: Int64 = 0
    private var memoryAfterASRUnloadBytes: Int64 = 0
    private var memoryAfterDiarizationBytes: Int64 = 0
    private var memoryAfterDigestBytes: Int64 = 0
    private var thermalStateStart = ""
    private var warmKeepDiarizationHit = false
    private var warmKeepDigestHit = false
    private var diarizationLoadMs = 0
    private var digestLoadMs = 0
    private var diarizationMs = 0
    private var digestMs = 0

    // MARK: - Lifecycle

    func begin(sessionID: String, conditions: AmbientDeviceConditions) {
        self.sessionID = sessionID
        self.startedAt = Date()
        self.conditions = conditions
        self.startBatteryLevel = conditions.batteryLevel
        self.audioRoute = Self.currentAudioRoute()
        self.thermalStateStart = conditions.thermalDescription
        self.availableMemoryAtStartBytes = conditions.availableMemoryBytes
        self.memoryAtStartBytes = Self.residentMemoryBytes()
        self.peakMemoryBytes = memoryAtStartBytes
        self.memoryPeakCaptureBytes = memoryAtStartBytes

        speechMilliseconds = 0
        segmentCount = 0
        droppedSegmentCount = 0
        backpressureEventCount = 0
        interruptionCount = 0
        transcriptionMs.removeAll()
        realTimeFactors.removeAll()
        extractionMs.removeAll()
        firstTranscriptLatencyMs = nil
        streamDiarUsed = false
        memoryAfterASRUnloadBytes = 0
        memoryAfterDiarizationBytes = 0
        memoryAfterDigestBytes = 0
        warmKeepDiarizationHit = false
        warmKeepDigestHit = false
        diarizationLoadMs = 0
        digestLoadMs = 0
        diarizationMs = 0
        digestMs = 0
    }

    /// Snapshot Developer performance knobs so samples can be compared A/B.
    func configurePerformance(_ settings: AmbientCapturePerformanceSettings) {
        vadMode = settings.vadMode.rawValue
        warmKeep = settings.warmKeep.rawValue
        streamDiarEnabled = settings.streamDiarDuringCapture
    }

    func markSpeechStarted() {
        sampleCaptureMemory()
    }

    func markSpeechEnded(durationMs: Int) {
        speechMilliseconds += durationMs
    }

    func markSegment() {
        segmentCount += 1
        sampleCaptureMemory()
    }

    func markTranscript(_ transcript: RAAmbientTranscript) {
        transcriptionMs.append(Double(transcript.transcriptionMs))
        realTimeFactors.append(transcript.realTimeFactor)
        sampleCaptureMemory()
        if firstTranscriptLatencyMs == nil, let startedAt {
            firstTranscriptLatencyMs = Date().timeIntervalSince(startedAt) * 1000
        }
    }

    func markDigest(_ digest: RAAmbientNoteDigest) {
        extractionMs.append(Double(digest.extractionMs))
        digestMs += digest.extractionMs
        markMemoryAfterDigest()
    }

    func markGate(_ gate: RAAmbientResourceGate) {
        guard gate.isActive, gate.reason == .backpressure else { return }
        droppedSegmentCount += 1
        backpressureEventCount += 1
    }

    func markInterruption() {
        interruptionCount += 1
    }

    func markStreamDiarUsed() {
        streamDiarUsed = true
        sampleCaptureMemory()
    }

    func markMemoryAfterASRUnload() {
        memoryAfterASRUnloadBytes = Self.residentMemoryBytes()
        peakMemoryBytes = max(peakMemoryBytes, memoryAfterASRUnloadBytes)
    }

    func markMemoryAfterDiarization() {
        memoryAfterDiarizationBytes = Self.residentMemoryBytes()
        peakMemoryBytes = max(peakMemoryBytes, memoryAfterDiarizationBytes)
    }

    func markMemoryAfterDigest() {
        memoryAfterDigestBytes = Self.residentMemoryBytes()
        peakMemoryBytes = max(peakMemoryBytes, memoryAfterDigestBytes)
    }

    func markDiarizationLoad(ms: Int, warmHit: Bool) {
        diarizationLoadMs += max(0, ms)
        if warmHit { warmKeepDiarizationHit = true }
    }

    func markDigestLoad(ms: Int, warmHit: Bool) {
        digestLoadMs += max(0, ms)
        if warmHit { warmKeepDigestHit = true }
    }

    func markDiarizationWallTime(ms: Int) {
        diarizationMs += max(0, ms)
    }

    /// Reduce the run to one sample and persist it. No-op when the session was
    /// never started (e.g. a failed model load).
    func finish(record: AmbientSessionRecord, store: AmbientMemoryStore) async {
        guard let sessionID, let startedAt, let conditions else { return }

        let now = Date()
        let elapsedHours = max(now.timeIntervalSince(startedAt) / 3600, 0.0001)
        let endBattery = Self.currentBatteryLevel()
        let batteryDeltaPerHour = (startBatteryLevel >= 0 && endBattery >= 0)
            ? Double(startBatteryLevel - endBattery) * 100 / elapsedHours
            : 0
        let endThermal = Self.currentThermalDescription()
        peakMemoryBytes = max(
            peakMemoryBytes,
            memoryPeakCaptureBytes,
            memoryAfterASRUnloadBytes,
            memoryAfterDiarizationBytes,
            memoryAfterDigestBytes,
            Self.residentMemoryBytes()
        )

        let deviceInfo = DeviceInfoService.shared.deviceInfo
        let sample = AmbientBenchmarkSample(
            id: UUID(),
            recordedAt: now,
            sessionID: sessionID,
            profileID: record.profileID,
            deviceModel: deviceInfo?.modelName ?? record.deviceModel,
            chipName: deviceInfo?.chipName ?? "",
            osVersion: record.osVersion,
            audioRoute: audioRoute,
            environment: record.context.environment,
            placement: record.context.placement,
            sessionSeconds: now.timeIntervalSince(startedAt),
            speechSeconds: Double(speechMilliseconds) / 1000.0,
            segmentCount: segmentCount,
            transcribedSegmentCount: record.transcribedSegments.count,
            droppedSegmentCount: droppedSegmentCount,
            actionItemCount: record.actionItems.count,
            completedActionItemCount: record.actionItems.filter(\.isDone).count,
            medianTranscriptionMs: Self.median(transcriptionMs),
            medianRealTimeFactor: Self.median(realTimeFactors),
            medianExtractionMs: Self.median(extractionMs),
            firstTranscriptLatencyMs: firstTranscriptLatencyMs ?? 0,
            peakMemoryBytes: peakMemoryBytes,
            batteryDeltaPerHour: batteryDeltaPerHour,
            thermalState: endThermal,
            interruptionCount: interruptionCount,
            retainedAudioBytes: await store.retainedAudioBytes(),
            runKind: "live",
            diarizationMs: diarizationMs,
            digestMs: digestMs,
            sectionCount: record.digestSections.count,
            bulletCount: record.digestSections.reduce(0) { $0 + $1.bullets.count },
            speakerCount: record.speakerCount ?? 0,
            vadMode: vadMode,
            warmKeep: warmKeep,
            streamDiarEnabled: streamDiarEnabled,
            streamDiarUsed: streamDiarUsed,
            availableMemoryAtStartBytes: availableMemoryAtStartBytes,
            memoryAtStartBytes: memoryAtStartBytes,
            memoryPeakCaptureBytes: memoryPeakCaptureBytes,
            memoryAfterASRUnloadBytes: memoryAfterASRUnloadBytes,
            memoryAfterDiarizationBytes: memoryAfterDiarizationBytes,
            memoryAfterDigestBytes: memoryAfterDigestBytes,
            batteryLevelStart: startBatteryLevel,
            batteryLevelEnd: endBattery,
            thermalStateStart: thermalStateStart,
            thermalStateEnd: endThermal,
            warmKeepDiarizationHit: warmKeepDiarizationHit,
            warmKeepDigestHit: warmKeepDigestHit,
            diarizationLoadMs: diarizationLoadMs,
            digestLoadMs: digestLoadMs,
            backpressureEventCount: backpressureEventCount
        )

        await store.append(sample)
        // Keep sessionID so Label/Summarize can amend the same sample after stop.
        self.startedAt = nil
        self.conditions = nil
    }

    /// Fold post-pass Sortformer metrics into the sample written at stop.
    func amendDiarizationPass(
        sessionID: String,
        store: AmbientMemoryStore,
        loadMs: Int,
        warmHit: Bool,
        wallMs: Int,
        memoryBytes: Int64
    ) async {
        _ = await store.updateBenchmarkSample(sessionID: sessionID) { sample in
            sample.diarizationLoadMs += max(0, loadMs)
            sample.diarizationMs += max(0, wallMs)
            if warmHit { sample.warmKeepDiarizationHit = true }
            sample.memoryAfterDiarizationBytes = max(sample.memoryAfterDiarizationBytes, memoryBytes)
            sample.peakMemoryBytes = max(sample.peakMemoryBytes, memoryBytes)
            if sample.warmKeep == "none" {
                sample.warmKeep = AmbientCapturePerformanceSettings.load().warmKeep.rawValue
            }
        }
    }

    /// Fold post-pass digester metrics into the sample written at stop.
    func amendDigestPass(
        sessionID: String,
        store: AmbientMemoryStore,
        loadMs: Int,
        warmHit: Bool,
        wallMs: Int,
        memoryBytes: Int64,
        sectionCount: Int,
        bulletCount: Int
    ) async {
        _ = await store.updateBenchmarkSample(sessionID: sessionID) { sample in
            sample.digestLoadMs += max(0, loadMs)
            sample.digestMs += max(0, wallMs)
            sample.medianExtractionMs = sample.digestMs > 0 ? Double(sample.digestMs) : sample.medianExtractionMs
            if warmHit { sample.warmKeepDigestHit = true }
            sample.memoryAfterDigestBytes = max(sample.memoryAfterDigestBytes, memoryBytes)
            sample.peakMemoryBytes = max(sample.peakMemoryBytes, memoryBytes)
            sample.sectionCount = max(sample.sectionCount, sectionCount)
            sample.bulletCount = max(sample.bulletCount, bulletCount)
            if sample.warmKeep == "none" {
                sample.warmKeep = AmbientCapturePerformanceSettings.load().warmKeep.rawValue
            }
        }
    }

    // MARK: - Measurement Helpers

    /// Median rather than mean: one cold-start segment or a thermal spike
    /// should not define the headline number for a multi-hour run.
    static func median(_ values: [Double]) -> Double {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    static func residentMemoryBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    private func sampleCaptureMemory() {
        let bytes = Self.residentMemoryBytes()
        memoryPeakCaptureBytes = max(memoryPeakCaptureBytes, bytes)
        peakMemoryBytes = max(peakMemoryBytes, bytes)
    }

    private static func currentBatteryLevel() -> Float {
        #if canImport(UIKit) && !os(macOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
        #else
        return -1
        #endif
    }

    private static func currentThermalDescription() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func currentAudioRoute() -> String {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.inputs
        return outputs.first?.portType.rawValue ?? "unknown"
        #else
        return "unknown"
        #endif
    }
}
