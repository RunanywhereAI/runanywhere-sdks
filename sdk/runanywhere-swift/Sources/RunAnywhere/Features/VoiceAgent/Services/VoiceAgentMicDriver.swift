//
//  VoiceAgentMicDriver.swift
//  RunAnywhere SDK
//
//  Audio ingress for the voice agent. The C ABI owns no microphone access;
//  the platform SDK captures mic audio and pushes complete utterances into
//  the C core via rac_voice_agent_process_turn_proto.
//

import AVFoundation
import CRACommons
import Foundation
import os

/// Captures mic audio and drives per-utterance voice-agent turns.
///
/// Mirrors Kotlin `VoiceAgentMicDriver.kt`. Endpointing is energy-based;
/// mic chunks that arrive while a turn is processing are discarded.
final class VoiceAgentMicDriver: @unchecked Sendable {
    private let handle: rac_voice_agent_handle_t
    private let capture = AudioCaptureManager()
    private let playback = AudioPlaybackManager()
    private let logger = SDKLogger(category: "VoiceAgentMic")

    private let chunkLock = OSAllocatedUnfairLock<[Data]>(initialState: [])
    private let processingLock = OSAllocatedUnfairLock(initialState: false)

    init(handle: rac_voice_agent_handle_t) {
        self.handle = handle
    }

    /// Runs until the calling task is cancelled.
    func run() async throws {
        guard await capture.requestPermission() else {
            throw SDKException(
                code: .permissionDenied,
                message: "Microphone permission denied",
                category: .component
            )
        }

        // The voice agent owns a single full-duplex session for the whole turn-
        // taking loop. Capture and playback must NOT reconfigure or deactivate it:
        // a `.record` override silences the reply and disables voice-processing
        // AGC on the mic signal, and a playback deactivate tears down the live
        // capture engine mid-session.
        try await configureVoiceAudioSession()
        playback.managesAudioSession = false
        try await capture.startRecording(configureSession: false) { [weak self] chunk in
            self?.enqueueChunk(chunk)
        }
        logger.info("Voice-agent mic capture started")

        defer {
            capture.stopRecording(deactivateSession: true)
            playback.stop()
            chunkLock.withLock { $0.removeAll() }
            logger.info("Voice-agent mic capture stopped")
        }

        try await segmentLoop()
    }

    // MARK: - Audio session

    private func configureVoiceAudioSession() async throws {
        #if os(iOS) || os(tvOS)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    // `.default` (not `.voiceChat`): the agent is half-duplex — the
                    // mic is gated while TTS plays, so we don't need voice-processing
                    // echo cancellation. `.voiceChat` forces the telephony I/O path,
                    // which attenuates speaker output to call levels (quiet replies)
                    // and runs an AGC that suppresses the mic after a long playout,
                    // breaking endpointing on every turn after the first.
                    try session.setCategory(
                        .playAndRecord,
                        mode: .default,
                        options: [.defaultToSpeaker, .allowBluetooth]
                    )
                    try session.setActive(true)
                    // Force the loud speaker route; `.defaultToSpeaker` alone can fall
                    // back to the receiver under `.playAndRecord`.
                    try session.overrideOutputAudioPort(.speaker)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #endif
    }

    // MARK: - Chunk queue

    private func enqueueChunk(_ chunk: Data) {
        if processingLock.withLock({ $0 }) { return }
        chunkLock.withLock { queue in
            queue.append(chunk)
            if queue.count > MicConstants.channelCapacity {
                queue.removeFirst(queue.count - MicConstants.channelCapacity)
            }
        }
    }

    private func drainChunks() -> [Data] {
        chunkLock.withLock { queue in
            let drained = queue
            queue.removeAll()
            return drained
        }
    }

    private func discardPendingChunks() {
        chunkLock.withLock { $0.removeAll() }
    }

    // MARK: - Segmentation

    private func segmentLoop() async throws {
        var preRoll: [Data] = []
        var utterance = Data()
        var inSpeech = false
        var speechMs = 0
        var silenceMs = 0
        var noiseFloor = MicConstants.speechRMSThreshold

        while !Task.isCancelled {
            let chunks = drainChunks()
            if chunks.isEmpty {
                try await Task.sleep(nanoseconds: 20_000_000)
                continue
            }

            for chunk in chunks {
                if Task.isCancelled { return }

                let chunkMs = Self.chunkDurationMs(chunk)
                // Adaptive endpointing. A fixed RMS threshold misses the end-of-
                // utterance pause on devices whose mic noise floor sits above the
                // constant. Track the ambient floor and require a chunk to rise
                // clearly above it.
                let level = Self.rms(chunk)
                let threshold = max(MicConstants.speechRMSThreshold, noiseFloor * MicConstants.speechFloorMultiplier)
                let isSpeech = level >= threshold
                // Only adapt the floor while idle (between utterances). Adapting
                // mid-utterance lets inter-word pauses and the end-of-utterance
                // silence tail inflate the floor; it then stays high (it's never
                // reset across turns) and locks out the next turn's speech. Drop
                // instantly to any quieter ambient; creep up slowly otherwise.
                if !inSpeech {
                    if level < noiseFloor {
                        noiseFloor = level
                    } else if !isSpeech {
                        noiseFloor += (level - noiseFloor) * MicConstants.noiseFloorRise
                    }
                }

                if !inSpeech {
                    preRoll.append(chunk)
                    if preRoll.count > MicConstants.preRollChunks {
                        preRoll.removeFirst()
                    }
                    if isSpeech {
                        inSpeech = true
                        speechMs = chunkMs
                        silenceMs = 0
                        utterance = Data()
                        for buffered in preRoll { utterance.append(buffered) }
                        preRoll.removeAll()
                    }
                    continue
                }

                utterance.append(chunk)
                if isSpeech {
                    speechMs += chunkMs
                    silenceMs = 0
                } else {
                    silenceMs += chunkMs
                }

                let utteranceMs = (utterance.count / MicConstants.bytesPerSample) * 1000 / MicConstants.sampleRateHz
                if silenceMs >= MicConstants.endOfUtteranceSilenceMs || utteranceMs >= MicConstants.maxUtteranceMs {
                    let audio = utterance
                    inSpeech = false
                    utterance = Data()
                    if speechMs >= MicConstants.minSpeechMs {
                        try await processTurn(audio: audio)
                        // Drop chunks captured while the turn ran (agent thinking /
                        // speaking) so stale audio is not folded into the next turn.
                        discardPendingChunks()
                    } else {
                        logger.debug("Utterance discarded (\(speechMs)ms speech < \(MicConstants.minSpeechMs)ms)")
                    }
                    speechMs = 0
                    silenceMs = 0
                }
            }
        }
    }

    // MARK: - Turn processing

    private func processTurn(audio: Data) async throws {
        processingLock.withLock { $0 = true }
        defer { processingLock.withLock { $0 = false } }

        var request = RAVoiceAgentTurnRequest()
        request.requestID = UUID().uuidString
        request.audioData = audio
        request.sampleRateHz = Int32(MicConstants.sampleRateHz)
        request.channels = 1
        request.encoding = .pcmS16Le

        logger.info("Submitting voice turn (\(audio.count) bytes)")

        var ttsPCM = Data()
        var ttsSampleRate: Int32 = 0
        var ttsEncoding: RAAudioEncoding = .unspecified

        let rc = try CppBridge.VoiceAgent.processTurnProto(handle: handle, request: request) { event in
            guard case let .audio(frame) = event.payload else { return }
            guard !frame.pcm.isEmpty else { return }
            ttsPCM.append(frame.pcm)
            if frame.sampleRateHz > 0 { ttsSampleRate = frame.sampleRateHz }
            if frame.encoding != .unspecified { ttsEncoding = frame.encoding }
        }

        if rc == RAC_ERROR_NOT_INITIALIZED {
            throw SDKException(
                code: .notInitialized,
                message: "Voice agent is no longer initialized",
                category: .component
            )
        }
        if rc != RAC_SUCCESS {
            logger.warning("Voice turn failed: rc=\(rc)")
        }

        try await playTTSReply(pcm: ttsPCM, sampleRateHz: ttsSampleRate, encoding: ttsEncoding)
    }

    private func playTTSReply(pcm: Data, sampleRateHz: Int32, encoding: RAAudioEncoding) async throws {
        guard !pcm.isEmpty else { return }

        let sampleRate = sampleRateHz > 0 ? sampleRateHz : MicConstants.defaultTTSSampleRateHz
        let wav: Data
        switch encoding {
        case .pcmS16Le:
            wav = try Self.pcmS16ToWAV(pcm: pcm, sampleRate: sampleRate)
        default:
            wav = try Self.float32PCMToWAV(pcm: pcm, sampleRate: sampleRate)
        }

        guard !wav.isEmpty else {
            logger.warning("TTS audio conversion failed (\(pcm.count) bytes, \(sampleRate)Hz, \(encoding))")
            return
        }

        logger.info("Playing agent reply (\(pcm.count) PCM bytes @ \(sampleRate)Hz)")
        try await playback.play(wav)
    }

    // MARK: - Audio helpers

    private static func rms(_ chunk: Data) -> Double {
        let sampleCount = chunk.count / MicConstants.bytesPerSample
        guard sampleCount > 0 else { return 0 }

        var sum = 0.0
        chunk.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for index in 0..<sampleCount {
                let lo = Int(bytes[2 * index])
                let hi = Int(Int8(bitPattern: bytes[2 * index + 1]))
                let sample = Double((hi << 8) | lo)
                sum += sample * sample
            }
        }
        return sqrt(sum / Double(sampleCount)) / Double(Int16.max)
    }

    private static func chunkDurationMs(_ chunk: Data) -> Int {
        let samples = chunk.count / MicConstants.bytesPerSample
        return (samples * 1000) / MicConstants.sampleRateHz
    }

    private static func pcmS16ToWAV(pcm: Data, sampleRate: Int32) throws -> Data {
        var wavDataPtr: UnsafeMutableRawPointer?
        var wavSize = 0
        let rc = pcm.withUnsafeBytes { raw in
            rac_audio_int16_to_wav(
                raw.baseAddress,
                pcm.count,
                sampleRate,
                &wavDataPtr,
                &wavSize
            )
        }
        guard rc == RAC_SUCCESS, let ptr = wavDataPtr, wavSize > 0 else {
            throw SDKException(
                code: .processingFailed,
                message: "Failed to convert Int16 PCM to WAV: \(rc)",
                category: .component
            )
        }
        defer { rac_free(ptr) }
        return Data(bytes: ptr, count: wavSize)
    }

    private static func float32PCMToWAV(pcm: Data, sampleRate: Int32) throws -> Data {
        var wavDataPtr: UnsafeMutableRawPointer?
        var wavSize = 0
        let rc = pcm.withUnsafeBytes { raw in
            rac_audio_float32_to_wav(
                raw.baseAddress,
                pcm.count,
                sampleRate,
                &wavDataPtr,
                &wavSize
            )
        }
        guard rc == RAC_SUCCESS, let ptr = wavDataPtr, wavSize > 0 else {
            throw SDKException(
                code: .processingFailed,
                message: "Failed to convert Float32 PCM to WAV: \(rc)",
                category: .component
            )
        }
        defer { rac_free(ptr) }
        return Data(bytes: ptr, count: wavSize)
    }
}

private enum MicConstants {
    static let sampleRateHz = 16_000
    static let bytesPerSample = 2
    static let channelCapacity = 128
    static let speechRMSThreshold = 0.015
    static let speechFloorMultiplier = 2.2
    static let noiseFloorRise = 0.05
    static let endOfUtteranceSilenceMs = 800
    static let minSpeechMs = 300
    static let maxUtteranceMs = 15_000
    static let preRollChunks = 3
    static let defaultTTSSampleRateHz: Int32 = 22_050
}
