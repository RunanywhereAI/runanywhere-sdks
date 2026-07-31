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
    private var interruptionCount = 0
    private var transcriptionMs: [Double] = []
    private var realTimeFactors: [Double] = []
    private var extractionMs: [Double] = []
    private var firstTranscriptLatencyMs: Double?
    private var peakMemoryBytes: Int64 = 0

    // MARK: - Lifecycle

    func begin(sessionID: String, conditions: AmbientDeviceConditions) {
        self.sessionID = sessionID
        self.startedAt = Date()
        self.conditions = conditions
        self.startBatteryLevel = conditions.batteryLevel
        self.audioRoute = Self.currentAudioRoute()

        speechMilliseconds = 0
        segmentCount = 0
        droppedSegmentCount = 0
        interruptionCount = 0
        transcriptionMs.removeAll()
        realTimeFactors.removeAll()
        extractionMs.removeAll()
        firstTranscriptLatencyMs = nil
        peakMemoryBytes = 0
    }

    func markSpeechStarted() {
        peakMemoryBytes = max(peakMemoryBytes, Self.residentMemoryBytes())
    }

    func markSpeechEnded(durationMs: Int) {
        speechMilliseconds += durationMs
    }

    func markSegment() {
        segmentCount += 1
        peakMemoryBytes = max(peakMemoryBytes, Self.residentMemoryBytes())
    }

    func markTranscript(_ transcript: RAAmbientTranscript) {
        transcriptionMs.append(Double(transcript.transcriptionMs))
        realTimeFactors.append(transcript.realTimeFactor)
        if firstTranscriptLatencyMs == nil, let startedAt {
            firstTranscriptLatencyMs = Date().timeIntervalSince(startedAt) * 1000
        }
    }

    func markDigest(_ digest: RAAmbientNoteDigest) {
        extractionMs.append(Double(digest.extractionMs))
        peakMemoryBytes = max(peakMemoryBytes, Self.residentMemoryBytes())
    }

    func markGate(_ gate: RAAmbientResourceGate) {
        guard gate.isActive, gate.reason == .backpressure else { return }
        droppedSegmentCount += 1
    }

    func markInterruption() {
        interruptionCount += 1
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
            thermalState: conditions.thermalDescription,
            interruptionCount: interruptionCount,
            retainedAudioBytes: await store.retainedAudioBytes()
        )

        await store.append(sample)
        self.sessionID = nil
        self.startedAt = nil
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

    private static func residentMemoryBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    private static func currentBatteryLevel() -> Float {
        #if canImport(UIKit) && !os(macOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
        #else
        return -1
        #endif
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
