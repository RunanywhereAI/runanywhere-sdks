//
//  CppBridge+Platform.swift
//  RunAnywhere SDK
//
//  Bridge extension for Platform backend (Apple Foundation Models + System TTS).
//  This file registers Swift callbacks with the C++ platform backend.
//

import CRACommons
import Foundation

// MARK: - Platform Bridge

extension CppBridge {

    /// Bridge for platform-native services (Foundation Models, System TTS)
    ///
    /// This bridge connects the C++ platform backend to Swift implementations.
    /// The C++ side handles registration with the service registry, while Swift
    /// provides the actual implementation through callbacks.
    public enum Platform {

        private static let logger = SDKLogger(category: "CppBridge.Platform")
        private static var isInitialized = false

        // MARK: - Service Handle Convention
        //
        // The platform C ABI (`rac_platform_llm_create_fn` /
        // `rac_platform_tts_create_fn`) documents the create return value as a
        // "Swift object pointer". We honour that literally: `create` retains the
        // freshly built service with `Unmanaged.passRetained` and returns its
        // opaque pointer as the `rac_handle_t`. `generate` / `synthesize` /
        // `stop` recover the same instance with `takeUnretainedValue()`, and
        // `destroy` balances the retain with `takeRetainedValue()`. Storing the
        // service inside the handle (rather than a single static slot) keeps
        // each session self-contained and supports concurrent sessions, mirroring
        // the `ProtoStreamContext` Unmanaged idiom used elsewhere in this bridge.

        // MARK: - Initialization

        /// Register the platform backend with C++.
        /// This must be called during SDK initialization.
        @MainActor
        public static func register() {
            guard !isInitialized else {
                logger.info("Platform backend already registered (skipping)")
                return
            }

            logger.info("🔧 Registering platform backend...")

            // Register Swift callbacks for LLM (Foundation Models)
            logger.info("  - Registering LLM callbacks...")
            registerLLMCallbacks()

            // Register Swift callbacks for TTS (System TTS)
            logger.info("  - Registering TTS callbacks...")
            registerTTSCallbacks()

            // Register the backend module and service providers
            logger.info("  - Calling rac_backend_platform_register()...")
            let result = rac_backend_platform_register()
            if result == RAC_SUCCESS || result == RAC_ERROR_MODULE_ALREADY_REGISTERED {
                isInitialized = true
                logger.info("✅ Platform backend registered successfully (result=\(result))")
            } else {
                logger.error("❌ Failed to register platform backend: \(result)")
                return
            }

            // `rac_backend_platform_register()` only registers the module
            // record + built-in catalog entries; it does NOT wire the
            // unified plugin vtable into the plugin router. Without this
            // step the router has no `platform` engine so `loadModel` for
            // `framework == .foundationModels / .systemTts / .coreml`
            // returns "no backend route". Register the vtable here so the
            // router can resolve the Apple FM + System TTS + CoreML
            // Diffusion primitives via `rac_plugin_entry_platform()`.
            registerPlatformPlugin()
        }

        /// Register the Apple platform engine plugin with the unified plugin
        /// registry so the router can route `framework == .foundationModels`
        /// (Apple FM), `.systemTts` (AVSpeechSynthesizer), and `.coreml`
        /// (Stable Diffusion) model loads to the platform vtable.
        @MainActor
        private static func registerPlatformPlugin() {
            guard let vtable = rac_plugin_entry_platform() else {
                logger.warning("Platform plugin entry returned null — FM / System TTS / CoreML will not route")
                return
            }

            let registerResult = vtable.withMemoryRebound(
                to: rac_engine_vtable_t.self, capacity: 1
            ) { typedPointer -> rac_result_t in
                return rac_plugin_register(typedPointer)
            }

            if registerResult == RAC_SUCCESS ||
               registerResult == RAC_ERROR_MODULE_ALREADY_REGISTERED {
                logger.info("Platform engine plugin registered (LLM + TTS + Diffusion via Apple APIs)")
            } else {
                let errorMsg = String(cString: rac_error_message(registerResult))
                logger.error("Platform plugin registration failed: \(errorMsg)")
            }
        }

        /// Unregister the platform backend.
        public static func unregister() {
            guard isInitialized else { return }

            _ = rac_backend_platform_unregister()
            isInitialized = false
            logger.info("Platform backend unregistered")
        }

        // MARK: - LLM Callbacks (Foundation Models)

        // swiftlint:disable:next function_body_length
        private static func registerLLMCallbacks() {
            var callbacks = rac_platform_llm_callbacks_t()

            callbacks.can_handle = { modelIdPtr, _ -> rac_bool_t in
                let modelId = modelIdPtr.map { String(cString: $0) }

                // Check if Foundation Models can handle this model on this runtime.
                guard SystemFoundationModels.isAvailable else {
                    return RAC_FALSE
                }

                guard let modelId = modelId, !modelId.isEmpty else {
                    return RAC_FALSE
                }

                let lowercased = modelId.lowercased()
                if lowercased.contains("foundation-models") ||
                   lowercased.contains("foundation") ||
                   lowercased.contains("apple-intelligence") ||
                   lowercased == "system-llm" {
                    return RAC_TRUE
                }

                return RAC_FALSE
            }

            callbacks.create = { _, _, _ -> rac_handle_t? in
                // Create Foundation Models service
                guard SystemFoundationModels.isAvailable else {
                    Platform.logger.error(
                        "Foundation Models unavailable: \(SystemFoundationModels.unavailableReason ?? "unknown reason")"
                    )
                    return nil
                }

                guard #available(iOS 26.0, macOS 26.0, *) else {
                    return nil
                }

                // Use a dispatch group to synchronously wait for async creation
                var serviceHandle: rac_handle_t?
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        let service = SystemFoundationModelsService()
                        try await service.initialize(modelPath: "built-in")

                        // Retain the service and hand its opaque pointer back as
                        // the handle; `generate`/`destroy` recover it via Unmanaged.
                        serviceHandle = UnsafeMutableRawPointer(Unmanaged.passRetained(service).toOpaque())
                        Platform.logger.info("Foundation Models service created")
                    } catch {
                        Platform.logger.error("Failed to create Foundation Models service: \(error)")
                        serviceHandle = nil
                    }
                    group.leave()
                }

                group.wait()
                return serviceHandle
            }

            callbacks.generate = { handle, promptPtr, _, outResponsePtr, _ -> rac_result_t in
                guard let handle = handle,
                      let promptPtr = promptPtr,
                      let outResponsePtr = outResponsePtr else {
                    return RAC_ERROR_INVALID_PARAMETER
                }

                guard #available(iOS 26.0, macOS 26.0, *) else {
                    return RAC_ERROR_NOT_SUPPORTED
                }

                let service = Unmanaged<SystemFoundationModelsService>
                    .fromOpaque(handle).takeUnretainedValue()

                let prompt = String(cString: promptPtr)

                var result: rac_result_t = RAC_ERROR_INTERNAL
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        let response = try await service.generate(
                            prompt: prompt,
                            options: RALLMGenerationOptions.defaults()
                        )
                        outResponsePtr.pointee = strdup(response)
                        result = RAC_SUCCESS
                    } catch {
                        Platform.logger.error("Foundation Models generate failed: \(error)")
                        result = RAC_ERROR_INTERNAL
                    }
                    group.leave()
                }

                group.wait()
                return result
            }

            callbacks.destroy = { handle, _ in
                guard let handle = handle else { return }
                // The handle can only have been minted by `create`, which is
                // gated to iOS/macOS 26+, so the release is too.
                guard #available(iOS 26.0, macOS 26.0, *) else { return }
                Unmanaged<SystemFoundationModelsService>.fromOpaque(handle).release()
                Platform.logger.debug("Foundation Models service destroyed")
            }

            callbacks.user_data = nil

            let result = rac_platform_llm_set_callbacks(&callbacks)
            if result == RAC_SUCCESS {
                logger.debug("LLM callbacks registered")
            } else {
                logger.error("Failed to register LLM callbacks: \(result)")
            }
        }

        // MARK: - TTS Callbacks (System TTS)

        // swiftlint:disable:next function_body_length
        private static func registerTTSCallbacks() {
            var callbacks = rac_platform_tts_callbacks_t()

            callbacks.can_handle = { voiceIdPtr, _ -> rac_bool_t in
                guard let voiceIdPtr = voiceIdPtr else {
                    // System TTS can be a fallback for nil
                    return RAC_TRUE
                }

                let voiceId = String(cString: voiceIdPtr).lowercased()

                if voiceId.contains("system-tts") ||
                   voiceId.contains("system_tts") ||
                   voiceId == "system" {
                    return RAC_TRUE
                }

                return RAC_FALSE
            }

            callbacks.create = { _, _ -> rac_handle_t? in
                var serviceHandle: rac_handle_t?

                // Use DispatchQueue.main.sync to create the MainActor-isolated service
                // This ensures proper thread safety for AVSpeechSynthesizer
                DispatchQueue.main.sync {
                    let service = SystemTTSService()

                    // Retain the service and hand its opaque pointer back as the
                    // handle; synthesize/stop/destroy recover it via Unmanaged.
                    serviceHandle = UnsafeMutableRawPointer(Unmanaged.passRetained(service).toOpaque())
                    Platform.logger.info("System TTS service created")
                }

                return serviceHandle
            }

            callbacks.synthesize = { handle, textPtr, optionsPtr, _ -> rac_result_t in
                guard let handle = handle, let textPtr = textPtr else {
                    return RAC_ERROR_INVALID_PARAMETER
                }

                let service = Unmanaged<SystemTTSService>.fromOpaque(handle).takeUnretainedValue()

                let text = String(cString: textPtr)

                // Build TTS options from C struct
                var rate: Float = 1.0
                var pitch: Float = 1.0
                var volume: Float = 1.0
                var voice = ""

                if let optionsPtr = optionsPtr {
                    rate = optionsPtr.pointee.rate
                    pitch = optionsPtr.pointee.pitch
                    volume = optionsPtr.pointee.volume
                    if let voicePtr = optionsPtr.pointee.voice_id {
                        voice = String(cString: voicePtr)
                    }
                }

                var options = RATTSOptions.defaults()
                options.voice = voice
                options.speakingRate = rate
                options.pitch = pitch
                options.volume = volume

                var result: rac_result_t = RAC_ERROR_INTERNAL
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        try await service.speak(text: text, options: options)
                        result = RAC_SUCCESS
                    } catch {
                        Platform.logger.error("System TTS speak failed: \(error)")
                        result = RAC_ERROR_INTERNAL
                    }
                    group.leave()
                }

                group.wait()
                return result
            }

            callbacks.stop = { handle, _ in
                guard let handle = handle else { return }
                let service = Unmanaged<SystemTTSService>.fromOpaque(handle).takeUnretainedValue()
                DispatchQueue.main.async {
                    service.stop()
                }
            }

            callbacks.destroy = { handle, _ in
                guard let handle = handle else { return }
                // Recover the +1 retain from `create`; stop on the main actor
                // first, then drop the final reference so the service deinits.
                let service = Unmanaged<SystemTTSService>.fromOpaque(handle).takeRetainedValue()
                DispatchQueue.main.async {
                    service.stop()
                    Platform.logger.debug("System TTS service destroyed")
                }
            }

            callbacks.user_data = nil

            let result = rac_platform_tts_set_callbacks(&callbacks)
            if result == RAC_SUCCESS {
                logger.debug("TTS callbacks registered")
            } else {
                logger.error("Failed to register TTS callbacks: \(result)")
            }
        }
    }
}
