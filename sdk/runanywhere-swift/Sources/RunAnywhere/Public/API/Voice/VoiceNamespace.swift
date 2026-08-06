//
//  VoiceNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.voice` — one call replaces the old five-step ritual of loading
//  three models, ensuring a VAD, and composing the agent.
//

import Foundation

public extension RunAnywhere {

    /// Live voice agents.
    static var voice: VoiceNamespace { VoiceNamespace() }

    /// Build a voice session that listens, thinks, and speaks.
    ///
    /// Named `VoiceNamespace` rather than `Voice` so the spec's `Voice` type
    /// (a TTS voice) keeps its name at module scope.
    struct VoiceNamespace: Sendable {

        /// Create a voice session, loading everything it needs first.
        ///
        /// ```swift
        /// let session = try await RunAnywhere.voice.createSession(stt: "whisper", llm: "qwen", tts: "piper")
        /// try session.start()
        /// ```
        ///
        /// - Parameter vad: `nil` ensures the catalogued default Silero VAD.
        /// - Throws: `SDKException` when a model cannot be downloaded or loaded,
        ///   or the native pipeline refuses the configuration.
        public func createSession(
            stt: ModelRef,
            llm: ModelRef,
            tts: ModelRef,
            vad: VadOptions? = nil,
            turnHandling: TurnHandlingOptions? = nil,
            generation: LlmOptions? = nil,
            downloadIfNeeded: Bool = true
        ) async throws -> VoiceSession {
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await RunAnywhere.ensureServicesReady()

            let sttId = try await RunAnywhere.ensureLoaded(
                modelId: stt.id,
                category: .speechRecognition,
                downloadIfNeeded: downloadIfNeeded
            )
            let llmId = try await RunAnywhere.ensureLoaded(
                modelId: llm.id,
                category: .language,
                downloadIfNeeded: downloadIfNeeded
            )
            _ = try await RunAnywhere.ensureLoaded(
                modelId: tts.id,
                category: .speechSynthesis,
                downloadIfNeeded: downloadIfNeeded
            )
            try await RunAnywhere.ensureResidentVAD(downloadIfNeeded: downloadIfNeeded)

            var config = RAVoiceAgentComposeConfig()
            config.sttModelID = sttId
            config.llmModelID = llmId
            // The voice id selects a voice *within* the loaded TTS model and is
            // not the model id; leaving it unset lets single-voice engines pick
            // their own default.
            if let voiceId = tts.voice, !voiceId.isEmpty {
                config.ttsVoiceID = voiceId
            }
            if let vad {
                var vadConfig = RAVADConfiguration.defaults()
                if let threshold = vad.activationThreshold {
                    vadConfig.activationThreshold = threshold
                }
                config.vadConfig = vadConfig
            }
            if let generation {
                config.llmGeneration = generation.toProto()
            }
            // VoiceSessionConfig/AudioPipelineConfig were deleted outright
            // (idl/voice_agent_service.proto): turn-taking now flows through
            // TurnDetection, and autoPlayTts/continuousMode/voiceId have no
            // wire home left — audio playback is unconditional (see
            // VoiceSession), and the voice id is already set via ttsVoiceID.
            config.turnDetection = VoiceNamespace.turnDetection(
                vad: vad,
                turnHandling: turnHandling
            )

            let handle = try await CppBridge.VoiceAgent.shared.getHandle()
            _ = try await CppBridge.VoiceAgent.shared.initialize(config)

            var ttsOptions = RATTSOptions.defaults()
            if let voiceId = tts.voice, !voiceId.isEmpty {
                ttsOptions.voice = voiceId
            }
            return VoiceSession(handle: handle, ttsOptions: ttsOptions)
        }

        /// `VoiceSessionConfig` was deleted outright (idl/voice_agent_service.proto):
        /// turn-taking now flows entirely through `TurnDetection`. Only
        /// `vad.activationThreshold` and `turnHandling.endpointing.minDelayMs`
        /// reach the compose ABI today; the remaining knobs
        /// (`endpointing.maxDelayMs`, `interruption`) are logged and ignored,
        /// same as before this migration.
        private static func turnDetection(
            vad: VadOptions?,
            turnHandling: TurnHandlingOptions?
        ) -> RATurnDetection {
            var detection = RATurnDetection()
            detection.type = .turnDetectionTypeVad
            if let threshold = vad?.activationThreshold {
                detection.threshold = threshold
            }
            guard let turnHandling else { return detection }

            detection.silenceDurationMs = Int32(turnHandling.endpointing.minDelayMs)
            SDKLogger.voiceAgent.warning(
                "TurnHandlingOptions endpointing.maxDelayMs and interruption are not carried by the compose ABI yet"
            )
            return detection
        }
    }
}

// MARK: - Default VAD

extension RunAnywhere {

    /// Make sure a VAD model is resident before a voice session starts.
    ///
    /// Without a lifecycle VAD load, the orchestrator falls back to an energy
    /// detector that never emits the speech-start / speech-end events the turn
    /// loop listens for, so the session stays silent after init.
    internal static func ensureResidentVAD(downloadIfNeeded: Bool) async throws {
        let snapshot = loadedModelSnapshot(category: .voiceActivityDetection)
        if snapshot.found, !snapshot.modelID.isEmpty { return }

        let modelId = RADefaults.VoiceAgent.defaultVadModelID
        guard !modelId.isEmpty else {
            throw SDKException(
                code: .modelNotFound,
                message: "No default VAD model is declared",
                category: .validation
            )
        }
        _ = try await ensureLoaded(
            modelId: modelId,
            category: .voiceActivityDetection,
            downloadIfNeeded: downloadIfNeeded
        )
    }
}
