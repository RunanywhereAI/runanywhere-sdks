//
//  AmbientOfflineImportRunner.swift
//  RunAnywhereAI
//
//  File-based Notes dogfood: import m4a/WAV → offline ASR via ambient
//  pipeline → optional Sortformer → structured digest, with stage metrics.
//

#if os(iOS)
import AVFoundation
import Foundation
import RunAnywhere
import UIKit
import os

/// Live UI state while an offline file is being transcribed.
struct AmbientOfflineLiveProgress: Equatable, Sendable {
    var fixtureName: String = ""
    var stage: String = ""
    var totalAudioMs: Int = 0
    var processedAudioMs: Int = 0
    var segmentCount: Int = 0
    var transcribedCount: Int = 0
    var latestTranscript: String = ""
    /// Rolling transcript tail shown in the live card (newest last).
    var recentLines: [String] = []
    var wallStartedAt: Date = .distantPast

    var progress: Double {
        guard totalAudioMs > 0 else { return 0 }
        return min(1, Double(processedAudioMs) / Double(totalAudioMs))
    }

    /// How many× faster than realtime (audio-seconds / wall-seconds).
    var realtimeFactor: Double {
        let wall = Date().timeIntervalSince(wallStartedAt)
        guard wall > 0.5, processedAudioMs > 0 else { return 0 }
        return (Double(processedAudioMs) / 1000.0) / wall
    }
}

@MainActor
final class AmbientOfflineImportRunner: ObservableObject {
    static let shared = AmbientOfflineImportRunner()

    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var lastMetrics: AmbientFileRunMetrics?
    @Published private(set) var lastError: String?
    @Published private(set) var live = AmbientOfflineLiveProgress()

    private let logger = Logger(subsystem: "com.runanywhere", category: "AmbientOffline")
    private let store = AmbientMemoryStore.shared
    private var lastUIPublish: Date = .distantPast

    private init() {}

    /// Documents/AmbientMemory/Fixtures — drop converted WAVs or m4as here.
    static var fixturesDirectory: URL {
        // Resolved via store root when available; fall back to Documents.
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AmbientMemory/Fixtures", isDirectory: true)
    }

    /// Import `fileURL` (m4a or wav), run the selected stack, persist a note.
    func run(
        fileURL: URL,
        selection: AmbientModelSelection,
        labelSpeakers: Bool,
        summarize: Bool,
        context: AmbientCaptureContext
    ) async -> AmbientFileRunMetrics {
        guard !isRunning else {
            var busy = AmbientFileRunMetrics(fixtureName: fileURL.lastPathComponent, sessionID: "")
            busy.error = "Another offline run is already in progress."
            lastError = busy.error
            return busy
        }
        isRunning = true
        lastError = nil
        defer {
            isRunning = false
            if lastError == nil, statusMessage.hasPrefix("Transcribing") {
                statusMessage = ""
            }
        }

        let started = Date()
        var metrics = AmbientFileRunMetrics(
            fixtureName: fileURL.lastPathComponent,
            sessionID: UUID().uuidString
        )
        metrics.vadModelID = selection.vadModelID
        metrics.asrModelID = selection.asrModelID
        metrics.digestModelID = selection.digestModelID
        metrics.deviceModel = UIDevice.current.model
        metrics.osVersion = UIDevice.current.systemVersion
        metrics.thermalState = ProcessInfo.processInfo.thermalStateDescription
        live = AmbientOfflineLiveProgress(
            fixtureName: fileURL.lastPathComponent,
            stage: "Preparing",
            wallStartedAt: started
        )

        do {
            statusMessage = "Converting audio…"
            live.stage = "Converting"
            let convertStarted = Date()
            let wavURL = try await Self.ensureWAV16kMono(from: fileURL, sessionID: metrics.sessionID)
            metrics.convertMs = Int(Date().timeIntervalSince(convertStarted) * 1000)
            metrics.peakMemoryBytes = max(metrics.peakMemoryBytes, Self.residentMemoryBytes())

            let pcm = try AmbientWAVPCMReader.pcm16Mono(from: wavURL, expectedSampleRate: 16_000)
            metrics.audioDurationMs = pcm.count / 2 * 1000 / 16_000
            live.totalAudioMs = metrics.audioDurationMs

            // Persist WAV under the note's audio path.
            let relative = try await store.importRecording(
                from: wavURL,
                sessionID: metrics.sessionID
            )

            statusMessage = "Transcribing offline…"
            live.stage = "Transcribing"
            let asrStarted = Date()
            var record = try await transcribeOffline(
                pcm: pcm,
                sessionID: metrics.sessionID,
                selection: selection,
                context: context,
                audioRelativePath: relative,
                displayTitle: fileURL.deletingPathExtension().lastPathComponent,
                onFirstTranscript: { latencyMs in
                    if metrics.firstTranscriptMs == 0 {
                        metrics.firstTranscriptMs = latencyMs
                    }
                }
            )
            metrics.asrMs = Int(Date().timeIntervalSince(asrStarted) * 1000)
            metrics.segmentCount = record.segments.count
            metrics.transcribedCount = record.transcribedSegments.count
            metrics.memoryAfterASR = Self.residentMemoryBytes()
            metrics.peakMemoryBytes = max(metrics.peakMemoryBytes, metrics.memoryAfterASR)

            // Unload capture models before heavier stages.
            await unload(modelID: selection.asrModelID, category: .speechRecognition)
            await unload(modelID: selection.vadModelID, category: .voiceActivityDetection)

            if labelSpeakers {
                statusMessage = "Labeling speakers…"
                live.stage = "Labeling speakers"
                // Prefer an already-downloaded Sortformer catalog id.
                let diarID = record.diarizationModelID
                    ?? "diar-streaming-sortformer-4spk-v2.1"
                metrics.diarizationModelID = diarID
                let diarStarted = Date()
                await AmbientSessionManager.shared.setDiarizationModel(
                    for: metrics.sessionID,
                    modelID: diarID
                )
                // Reload note after set
                if let fresh = await store.loadSession(id: metrics.sessionID) {
                    record = fresh
                }
                await AmbientSessionManager.shared.labelSpeakers(
                    for: metrics.sessionID,
                    modelID: diarID
                )
                metrics.diarizationMs = Int(Date().timeIntervalSince(diarStarted) * 1000)
                if let fresh = await store.loadSession(id: metrics.sessionID) {
                    record = fresh
                    metrics.speakerCount = record.speakerCount ?? 0
                }
                metrics.memoryAfterDiarization = Self.residentMemoryBytes()
                metrics.peakMemoryBytes = max(metrics.peakMemoryBytes, metrics.memoryAfterDiarization)
            }

            if summarize, let digestID = selection.digestModelID, !digestID.isEmpty {
                statusMessage = "Summarizing…"
                live.stage = "Summarizing"
                let digestStarted = Date()
                await AmbientSessionManager.shared.generateSummary(
                    for: metrics.sessionID,
                    modelID: digestID,
                    rewrite: false
                )
                metrics.digestMs = Int(Date().timeIntervalSince(digestStarted) * 1000)
                if let fresh = await store.loadSession(id: metrics.sessionID) {
                    record = fresh
                    metrics.sectionCount = record.digestSections.count
                    metrics.bulletCount = record.digestSections.reduce(0) { $0 + $1.bullets.count }
                    metrics.actionItemCount = record.actionItems.count
                }
                metrics.memoryAfterDigest = Self.residentMemoryBytes()
                metrics.peakMemoryBytes = max(metrics.peakMemoryBytes, metrics.memoryAfterDigest)
            }

            metrics.totalMs = Int(Date().timeIntervalSince(started) * 1000)
            statusMessage = "Offline run finished."
            live.stage = "Done"
            live.processedAudioMs = live.totalAudioMs
            lastMetrics = metrics
            await store.appendFileRunMetrics(metrics)
            await appendBenchmarkSample(metrics: metrics, record: record, selection: selection)
            logger.info("Offline run \(metrics.fixtureName, privacy: .public) done in \(metrics.totalMs)ms")
            return metrics
        } catch {
            metrics.error = error.localizedDescription
            metrics.totalMs = Int(Date().timeIntervalSince(started) * 1000)
            lastError = metrics.error
            lastMetrics = metrics
            statusMessage = metrics.error ?? "Offline run failed."
            live.stage = "Failed"
            await store.appendFileRunMetrics(metrics)
            logger.error("Offline run failed: \(error.localizedDescription, privacy: .public)")
            return metrics
        }
    }

    /// Run every audio file in the Fixtures directory.
    func runAllFixtures(
        selection: AmbientModelSelection,
        labelSpeakers: Bool,
        summarize: Bool,
        context: AmbientCaptureContext
    ) async -> [AmbientFileRunMetrics] {
        let dir = Self.fixturesDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ))?
            .filter { ["wav", "m4a", "mp4", "caf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            ?? []
        guard !urls.isEmpty else {
            lastError = "No fixtures in \(dir.path). Copy WAV/m4a files there first."
            statusMessage = lastError ?? ""
            return []
        }
        var results: [AmbientFileRunMetrics] = []
        for url in urls {
            results.append(await run(
                fileURL: url,
                selection: selection,
                labelSpeakers: labelSpeakers,
                summarize: summarize,
                context: context
            ))
        }
        return results
    }

    // MARK: - Offline ASR

    /// Fast file path: skip Silero (tens of thousands of frame calls) and run
    /// energy segmentation + direct `RunAnywhere.transcribe` on speech spans.
    /// Live capture still uses the ambient VAD pipeline; offline does not need it.
    private func transcribeOffline(
        pcm: Data,
        sessionID: String,
        selection: AmbientModelSelection,
        context: AmbientCaptureContext,
        audioRelativePath: String,
        displayTitle: String,
        onFirstTranscript: @escaping (Int) -> Void
    ) async throws -> AmbientSessionRecord {
        let sampleRate = 16_000
        let asrWallStart = Date()
        let totalMs = pcm.count / 32
        live.totalAudioMs = totalMs
        live.wallStartedAt = asrWallStart
        live.stage = "Loading ASR"

        try await ensureASRLoaded(selection.asrModelID)

        var record = AmbientSessionRecord(
            id: sessionID,
            startedAt: Date(),
            profileID: selection.profileID,
            vadModelID: selection.vadModelID,
            sttModelID: selection.asrModelID,
            digestModelID: selection.digestModelID,
            retentionPolicy: .retainAudio,
            context: context,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            audioRelativePath: audioRelativePath
        )
        record.customTitle = displayTitle
        await store.save(record)

        live.stage = "Transcribing"
        let spans = Self.energySpeechSpans(pcm16: pcm, sampleRate: sampleRate)
        var sawFirstTranscript = false
        var eventsSinceSave = 0
        let baseDate = Date()

        for (index, span) in spans.enumerated() {
            let startMs = span.startSample * 1000 / sampleRate
            let endMs = span.endSample * 1000 / sampleRate
            let durationMs = max(1, endMs - startMs)
            let byteStart = span.startSample * 2
            let byteEnd = min(pcm.count, span.endSample * 2)
            guard byteEnd > byteStart else { continue }

            let slice = pcm.subdata(in: byteStart..<byteEnd)
            let startedAt = baseDate.addingTimeInterval(Double(startMs) / 1000)
            let endedAt = baseDate.addingTimeInterval(Double(endMs) / 1000)
            let segmentID = "\(sessionID)-\(index)"

            var segment = AmbientSegmentRecord(
                id: segmentID,
                sessionID: sessionID,
                index: index,
                startedAt: startedAt,
                endedAt: endedAt,
                durationMs: durationMs,
                sampleRate: sampleRate,
                peakConfidence: span.peakEnergy,
                startOffsetMs: startMs,
                endOffsetMs: endMs
            )

            let sttStarted = Date()
            let output = try await RunAnywhere.transcribe(audio: slice, options: .defaults())
            let transcriptionMs = Int(Date().timeIntervalSince(sttStarted) * 1000)
            let text = output.errorMessage.isEmpty
                ? output.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            if !text.isEmpty {
                let transcript = RAAmbientTranscript(
                    id: segmentID,
                    sessionID: sessionID,
                    segmentID: segmentID,
                    segmentIndex: index,
                    text: text,
                    confidence: output.confidence,
                    languageCode: output.hasLanguageCode ? output.languageCode : "",
                    startedAt: startedAt,
                    endedAt: endedAt,
                    audioDurationMs: durationMs,
                    transcriptionMs: transcriptionMs,
                    modelID: selection.asrModelID
                )
                segment.apply(transcript)
                if !sawFirstTranscript {
                    sawFirstTranscript = true
                    onFirstTranscript(Int(Date().timeIntervalSince(asrWallStart) * 1000))
                }
            }

            record.upsert(segment)
            publishLive(
                processedMs: endMs,
                segments: record.segments.count,
                transcribed: record.transcribedSegments.count,
                line: text.isEmpty ? nil : text,
                force: true
            )

            eventsSinceSave += 1
            if eventsSinceSave >= 4 {
                await store.save(record)
                eventsSinceSave = 0
            }
        }

        record.endedAt = Date()
        if record.customTitle == nil {
            record.customTitle = displayTitle
        }
        await store.save(record)
        return record
    }

    private func ensureASRLoaded(_ modelID: String) async throws {
        var current = RACurrentModelRequest()
        current.category = .speechRecognition
        if RunAnywhere.currentModel(current).modelID == modelID { return }

        var load = RAModelLoadRequest()
        load.modelID = modelID
        load.category = .speechRecognition
        let result = await RunAnywhere.loadModel(load)
        guard result.success else {
            throw NSError(
                domain: "AmbientOffline",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: result.errorMessage.isEmpty
                    ? "Failed to load ASR model \(modelID)"
                    : result.errorMessage]
            )
        }
    }

    /// Cheap offline speech finder — RMS energy with hangover. Avoids loading
    /// Silero for file imports (the dominant cost of the streaming path).
    private static func energySpeechSpans(
        pcm16: Data,
        sampleRate: Int,
        frameMs: Int = 30,
        hangoverMs: Int = 400,
        minSpeechMs: Int = 400,
        maxSpeechMs: Int = 20_000
    ) -> [(startSample: Int, endSample: Int, peakEnergy: Float)] {
        let sampleCount = pcm16.count / 2
        guard sampleCount > 0 else { return [] }

        let frameSamples = max(1, sampleRate * frameMs / 1000)
        let hangoverFrames = max(1, hangoverMs / frameMs)
        let minFrames = max(1, minSpeechMs / frameMs)
        let maxFrames = max(minFrames, maxSpeechMs / frameMs)

        // First pass: per-frame RMS.
        var energies: [Float] = []
        energies.reserveCapacity(sampleCount / frameSamples + 1)
        pcm16.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            var i = 0
            while i < samples.count {
                let end = min(samples.count, i + frameSamples)
                var acc: Float = 0
                let n = end - i
                for j in i..<end {
                    let v = Float(samples[j])
                    acc += v * v
                }
                energies.append(n > 0 ? sqrt(acc / Float(n)) : 0)
                i = end
            }
        }

        // Adaptive threshold from a quiet percentile of frames.
        let sorted = energies.sorted()
        let noiseIdx = min(sorted.count - 1, max(0, sorted.count / 10))
        let noise = sorted.isEmpty ? 0 : sorted[noiseIdx]
        let threshold = max(350, noise * 3.5)

        var spans: [(startSample: Int, endSample: Int, peakEnergy: Float)] = []
        var inSpeech = false
        var startFrame = 0
        var peak: Float = 0
        var silenceRun = 0
        var speechFrames = 0

        func close(at endFrame: Int) {
            guard inSpeech else { return }
            if speechFrames >= minFrames {
                let start = startFrame * frameSamples
                let end = min(sampleCount, endFrame * frameSamples)
                if end > start {
                    spans.append((start, end, min(1, peak / 8000)))
                }
            }
            inSpeech = false
            peak = 0
            silenceRun = 0
            speechFrames = 0
        }

        for (frame, energy) in energies.enumerated() {
            let speech = energy >= threshold
            if speech {
                if !inSpeech {
                    inSpeech = true
                    startFrame = frame
                    peak = energy
                    speechFrames = 1
                } else {
                    peak = max(peak, energy)
                    speechFrames += 1
                    // Force-split long monologues so STT stays snappy.
                    if speechFrames >= maxFrames {
                        close(at: frame + 1)
                    }
                }
                silenceRun = 0
            } else if inSpeech {
                silenceRun += 1
                speechFrames += 1
                if silenceRun >= hangoverFrames {
                    close(at: frame + 1 - silenceRun)
                } else if speechFrames >= maxFrames {
                    close(at: frame + 1)
                }
            }
        }
        close(at: energies.count)

        // Fallback: fixed windows if energy found nothing (very quiet file).
        if spans.isEmpty {
            let window = sampleRate * 15
            var start = 0
            while start < sampleCount {
                let end = min(sampleCount, start + window)
                spans.append((start, end, 0.5))
                start = end
            }
        }
        return spans
    }

    // MARK: - Audio convert

    /// Convert any AVFoundation-readable file to 16 kHz mono PCM16 WAV.
    static func ensureWAV16kMono(from source: URL, sessionID: String) async throws -> URL {
        if source.pathExtension.lowercased() == "wav" {
            // Validate; if already correct, reuse.
            if let _ = try? AmbientWAVPCMReader.pcm16Mono(from: source, expectedSampleRate: 16_000) {
                return source
            }
        }

        let outDir = fixturesDirectory.appendingPathComponent("Converted", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appendingPathComponent("\(sessionID).wav")
        if FileManager.default.fileExists(atPath: outURL.path) {
            try FileManager.default.removeItem(at: outURL)
        }

        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(
                domain: "AmbientOffline",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No audio track in \(source.lastPathComponent)"]
            )
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(
                domain: "AmbientOffline",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start audio reader"]
            )
        }

        let writer = try WAVFileWriter(url: outURL, sampleRate: 16_000)
        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            if let dataPointer, length > 0 {
                let data = Data(bytes: dataPointer, count: length)
                try writer.append(data)
            }
        }
        try writer.close()
        if reader.status == .failed {
            throw reader.error ?? NSError(
                domain: "AmbientOffline",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Audio conversion failed"]
            )
        }
        return outURL
    }

    private func unload(modelID: String, category: RAModelCategory) async {
        guard !modelID.isEmpty else { return }
        var request = RAModelUnloadRequest()
        request.modelID = modelID
        request.category = category
        _ = await RunAnywhere.unloadModel(request)
    }

    private func appendBenchmarkSample(
        metrics: AmbientFileRunMetrics,
        record: AmbientSessionRecord,
        selection: AmbientModelSelection
    ) async {
        let sample = AmbientBenchmarkSample(
            id: UUID(),
            recordedAt: Date(),
            sessionID: metrics.sessionID,
            profileID: selection.profileID,
            deviceModel: metrics.deviceModel,
            chipName: DeviceInfoService.shared.deviceInfo?.chipName ?? "",
            osVersion: metrics.osVersion,
            audioRoute: "file:\(metrics.fixtureName)",
            environment: record.context.environment,
            placement: record.context.placement,
            sessionSeconds: Double(metrics.audioDurationMs) / 1000.0,
            speechSeconds: Double(metrics.audioDurationMs) / 1000.0,
            segmentCount: metrics.segmentCount,
            transcribedSegmentCount: metrics.transcribedCount,
            droppedSegmentCount: 0,
            actionItemCount: metrics.actionItemCount,
            completedActionItemCount: 0,
            medianTranscriptionMs: Double(metrics.asrMs),
            medianRealTimeFactor: metrics.audioDurationMs > 0
                ? Double(metrics.asrMs) / Double(metrics.audioDurationMs)
                : 0,
            medianExtractionMs: Double(metrics.digestMs),
            firstTranscriptLatencyMs: Double(metrics.firstTranscriptMs),
            peakMemoryBytes: metrics.peakMemoryBytes,
            batteryDeltaPerHour: 0,
            thermalState: metrics.thermalState,
            interruptionCount: 0,
            retainedAudioBytes: Int64(metrics.audioDurationMs) * 32, // rough PCM16 mono @16k
            runKind: "file",
            convertMs: metrics.convertMs,
            asrMs: metrics.asrMs,
            diarizationMs: metrics.diarizationMs,
            digestMs: metrics.digestMs,
            sectionCount: metrics.sectionCount,
            bulletCount: metrics.bulletCount,
            speakerCount: metrics.speakerCount,
            fixtureName: metrics.fixtureName
        )
        await store.append(sample)
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

    /// Throttled UI publish so transcript lines feel live without thrashing SwiftUI.
    private func publishLive(
        processedMs: Int,
        segments: Int,
        transcribed: Int,
        line: String?,
        force: Bool = false
    ) {
        let now = Date()
        if !force, line == nil, now.timeIntervalSince(lastUIPublish) < 0.2 {
            live.processedAudioMs = max(live.processedAudioMs, processedMs)
            return
        }
        lastUIPublish = now
        live.processedAudioMs = max(live.processedAudioMs, processedMs)
        live.segmentCount = segments
        live.transcribedCount = transcribed
        if let line, !line.isEmpty {
            live.latestTranscript = line
            var lines = live.recentLines
            lines.append(line)
            if lines.count > 6 { lines = Array(lines.suffix(6)) }
            live.recentLines = lines
        }
        let pct = Int(live.progress * 100)
        let clock = Self.clock(live.processedAudioMs)
        let total = Self.clock(live.totalAudioMs)
        let rtf = live.realtimeFactor
        let rtfText = rtf > 0 ? String(format: " · %.1f×", rtf) : ""
        statusMessage = "\(live.fixtureName): \(clock) / \(total) (\(pct)%)\(rtfText)"
    }

    private static func clock(_ ms: Int) -> String {
        let totalSec = max(0, ms / 1000)
        let m = totalSec / 60
        let s = totalSec % 60
        return String(format: "%d:%02d", m, s)
    }
}

private extension ProcessInfo {
    var thermalStateDescription: String {
        switch thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
#endif
