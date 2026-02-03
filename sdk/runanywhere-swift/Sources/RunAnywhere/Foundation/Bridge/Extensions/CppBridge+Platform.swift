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

        // MARK: - Service Instances

        // Cached Foundation Models service (type-erased for iOS 26+ availability)
        // swiftlint:disable:next avoid_any_type
        private static var foundationModelsService: Any?

        /// Last error message from Foundation Models generate (used when C++ reports "Streaming generation failed")
        static var lastFoundationModelsErrorMessage: String?

        /// Maps generic Foundation Models error descriptions to user-friendly messages.
        private static func friendlyFoundationModelsMessage(_ raw: String) -> String {
            if raw.contains("FoundationModels.LanguageModelSession.GenerationError") ||
               raw.contains("error -1") ||
               raw.contains("The operation couldn't be completed") {
                return "Apple Intelligence is not available on this device or simulator. Try a physical device with Apple Intelligence enabled in Settings, or use a downloaded LLM from the Models tab."
            }
            return raw
        }

        /// Cached System TTS service instance
        private static var systemTTSService: SystemTTSService?

        // MARK: - Initialization

        /// Register the platform backend with C++.
        /// This must be called during SDK initialization.
        @MainActor
        public static func register() {
            guard !isInitialized else {
                logger.debug("Platform backend already registered")
                return
            }

            logger.info("Registering platform backend...")

            // Register Swift callbacks for LLM (Foundation Models)
            registerLLMCallbacks()

            // Register Swift callbacks for TTS (System TTS)
            registerTTSCallbacks()

            // Register the backend module and service providers
            let result = rac_backend_platform_register()
            if result == RAC_SUCCESS || result == RAC_ERROR_MODULE_ALREADY_REGISTERED {
                isInitialized = true
                logger.info("✅ Platform backend registered successfully")
            } else {
                logger.error("❌ Failed to register platform backend: \(result)")
            }
        }

        /// Unregister the platform backend.
        public static func unregister() {
            guard isInitialized else { return }

            _ = rac_backend_platform_unregister()
            foundationModelsService = nil
            systemTTSService = nil
            isInitialized = false
            logger.info("Platform backend unregistered")
        }

        // MARK: - LLM Callbacks (Foundation Models)

        // swiftlint:disable:next function_body_length
        private static func registerLLMCallbacks() {
            var callbacks = rac_platform_llm_callbacks_t()

            callbacks.can_handle = { modelIdPtr, _ -> rac_bool_t in
                let modelId = modelIdPtr.map { String(cString: $0) }

                // Check if Foundation Models can handle this model
                guard #available(iOS 26.0, macOS 26.0, *) else {
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
                guard #available(iOS 26.0, macOS 26.0, *) else {
                    return nil
                }

                // Use a dispatch group to synchronously wait for async creation
                let handlePtr = UnsafeMutablePointer<rac_handle_t?>.allocate(capacity: 1)
                handlePtr.initialize(to: nil)
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        let service = SystemFoundationModelsService()
                        try await service.initialize(modelPath: "built-in")
                        Platform.foundationModelsService = service

                        // Return a marker handle - actual service is managed by Swift
                        handlePtr.pointee = UnsafeMutableRawPointer(bitPattern: 0xF00DADE1)
                        Platform.logger.info("Foundation Models service created")
                    } catch {
                        Platform.logger.error("Failed to create Foundation Models service: \(error)")
                        handlePtr.pointee = nil
                    }
                    group.leave()
                }

                group.wait()
                let handle = handlePtr.move()
                handlePtr.deallocate()
                return handle
            }

            callbacks.generate = { _, promptPtr, _, outResponsePtr, _ -> rac_result_t in
                guard let promptPtr = promptPtr,
                      let outResponsePtr = outResponsePtr else {
                    return RAC_ERROR_INVALID_PARAMETER
                }

                guard #available(iOS 26.0, macOS 26.0, *) else {
                    return RAC_ERROR_NOT_SUPPORTED
                }

                guard let service = Platform.foundationModelsService as? SystemFoundationModelsService else {
                    return RAC_ERROR_NOT_INITIALIZED
                }

                let prompt = String(cString: promptPtr)

                let resultPtr = UnsafeMutablePointer<rac_result_t>.allocate(capacity: 1)
                resultPtr.initialize(to: RAC_ERROR_INTERNAL)
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        let response = try await service.generate(
                            prompt: prompt,
                            options: LLMGenerationOptions()
                        )
                        outResponsePtr.pointee = strdup(response)
                        resultPtr.pointee = RAC_SUCCESS
                    } catch {
                        Platform.logger.error("Foundation Models generate failed: \(error)")
                        let raw = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                        Platform.lastFoundationModelsErrorMessage = Platform.friendlyFoundationModelsMessage(raw)
                        result = RAC_ERROR_INTERNAL
                    }
                    group.leave()
                }

                group.wait()
                let result = resultPtr.move()
                resultPtr.deallocate()
                return result
            }

            callbacks.destroy = { _, _ in
                Platform.foundationModelsService = nil
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
                    Platform.systemTTSService = service

                    // Return a marker handle
                    serviceHandle = UnsafeMutableRawPointer(bitPattern: 0x5157E775)
                    Platform.logger.info("System TTS service created")
                }

                return serviceHandle
            }

            callbacks.synthesize = { _, textPtr, optionsPtr, _ -> rac_result_t in
                guard let textPtr = textPtr else {
                    return RAC_ERROR_INVALID_PARAMETER
                }

                guard let service = Platform.systemTTSService else {
                    return RAC_ERROR_NOT_INITIALIZED
                }

                let text = String(cString: textPtr)

                // Build TTS options from C struct
                var rate: Float = 1.0
                var pitch: Float = 1.0
                var volume: Float = 1.0
                var voice: String?

                if let optionsPtr = optionsPtr {
                    rate = optionsPtr.pointee.rate
                    pitch = optionsPtr.pointee.pitch
                    volume = optionsPtr.pointee.volume
                    if let voicePtr = optionsPtr.pointee.voice_id {
                        voice = String(cString: voicePtr)
                    }
                }

                let options = TTSOptions(
                    voice: voice,
                    rate: rate,
                    pitch: pitch,
                    volume: volume
                )

                let resultPtr = UnsafeMutablePointer<rac_result_t>.allocate(capacity: 1)
                resultPtr.initialize(to: RAC_ERROR_INTERNAL)
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        _ = try await service.synthesize(text: text, options: options)
                        resultPtr.pointee = RAC_SUCCESS
                    } catch {
                        Platform.logger.error("System TTS synthesize failed: \(error)")
                        resultPtr.pointee = RAC_ERROR_INTERNAL
                    }
                    group.leave()
                }

                group.wait()
                let result = resultPtr.move()
                resultPtr.deallocate()
                return result
            }

            callbacks.stop = { _, _ in
                DispatchQueue.main.async {
                    Platform.systemTTSService?.stop()
                }
            }

            callbacks.destroy = { _, _ in
                DispatchQueue.main.async {
                    Platform.systemTTSService?.stop()
                    Platform.systemTTSService = nil
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

        // MARK: - Service Access

        /// Get the cached Foundation Models service (if created)
        @available(iOS 26.0, macOS 26.0, *)
        public static func getFoundationModelsService() -> SystemFoundationModelsService? {
            return foundationModelsService as? SystemFoundationModelsService
        }

        /// Get the cached System TTS service (if created)
        public static func getSystemTTSService() -> SystemTTSService? {
            return systemTTSService
        }
    }
}
