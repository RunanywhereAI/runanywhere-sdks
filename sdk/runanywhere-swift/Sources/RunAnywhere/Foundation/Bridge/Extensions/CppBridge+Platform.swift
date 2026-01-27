//
//  CppBridge+Platform.swift
//  RunAnywhere SDK
//
//  Bridge extension for Platform backend (Apple Foundation Models + System TTS + CoreML Diffusion).
//  This file registers Swift callbacks with the C++ platform backend.
//

import CRACommons
import Foundation
import StableDiffusion

// MARK: - Platform Bridge

extension CppBridge {

    // swiftlint:disable type_body_length

    /// Bridge for platform-native services (Foundation Models, System TTS, CoreML Diffusion)
    ///
    /// This bridge connects the C++ platform backend to Swift implementations.
    /// The C++ side handles registration with the service registry, while Swift
    /// provides the actual implementation through callbacks.
    public enum Platform {

        private static let logger = SDKLogger(category: "CppBridge.Platform")
        private static var isInitialized = false

        // MARK: - Service Instances

        /// Cached Foundation Models service (type-erased for iOS 26+ availability)
        private static var foundationModelsService: (any Sendable)?

        /// Cached System TTS service instance
        private static var systemTTSService: SystemTTSService?

        /// Cached CoreML Diffusion service (type-erased for availability)
        private static var diffusionService: (any Sendable)?

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

            // Register Swift callbacks for Diffusion (CoreML)
            registerDiffusionCallbacks()

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
            diffusionService = nil
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
                var serviceHandle: rac_handle_t?
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        let service = SystemFoundationModelsService()
                        try await service.initialize(modelPath: "built-in")
                        Platform.foundationModelsService = service

                        // Return a marker handle - actual service is managed by Swift
                        serviceHandle = UnsafeMutableRawPointer(bitPattern: 0xF00DADE1)
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

                var result: rac_result_t = RAC_ERROR_INTERNAL
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        let response = try await service.generate(
                            prompt: prompt,
                            options: LLMGenerationOptions()
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

                var result: rac_result_t = RAC_ERROR_INTERNAL
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        _ = try await service.synthesize(text: text, options: options)
                        result = RAC_SUCCESS
                    } catch {
                        Platform.logger.error("System TTS synthesize failed: \(error)")
                        result = RAC_ERROR_INTERNAL
                    }
                    group.leave()
                }

                group.wait()
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

        // MARK: - Diffusion Callbacks (CoreML Stable Diffusion)

        // swiftlint:disable:next function_body_length cyclomatic_complexity
        private static func registerDiffusionCallbacks() {
            var callbacks = rac_platform_diffusion_callbacks_t()

            callbacks.can_handle = { modelIdPtr, _ -> rac_bool_t in
                let modelId = modelIdPtr.map { String(cString: $0) }

                // Check if CoreML diffusion can handle this model
                guard #available(iOS 16.2, macOS 13.1, *) else {
                    return RAC_FALSE
                }

                guard let modelId = modelId, !modelId.isEmpty else {
                    // Accept nil for default diffusion model
                    return RAC_TRUE
                }

                let lowercased = modelId.lowercased()
                if lowercased.contains("coreml") ||
                   lowercased.contains("stable-diffusion") ||
                   lowercased.contains("diffusion") ||
                   lowercased.contains("sd-") ||
                   lowercased.contains("sdxl") {
                    return RAC_TRUE
                }

                return RAC_FALSE
            }

            callbacks.create = { modelPathPtr, configPtr, _ -> rac_handle_t? in
                guard #available(iOS 16.2, macOS 13.1, *) else {
                    Platform.logger.error("CoreML Diffusion requires iOS 16.2+ or macOS 13.1+")
                    return nil
                }

                guard let modelPathPtr = modelPathPtr else {
                    Platform.logger.error("Model path is required for diffusion")
                    return nil
                }

                let modelPath = String(cString: modelPathPtr)

                // Parse config
                var reduceMemory = true
                var disableSafety = false
                var modelVariant: DiffusionModelVariant = .sd15

                if let configPtr = configPtr {
                    reduceMemory = configPtr.pointee.reduce_memory == RAC_TRUE
                    disableSafety = configPtr.pointee.enable_safety_checker == RAC_FALSE
                    modelVariant = DiffusionModelVariant(cValue: configPtr.pointee.model_variant)
                }

                // Determine tokenizer source from model variant
                let tokenizerSource = modelVariant.defaultTokenizerSource

                // Create service asynchronously but wait for completion
                // NOTE: First-time model loading can take 5-15 minutes as Core ML compiles for the device
                var serviceHandle: rac_handle_t?
                let group = DispatchGroup()
                group.enter()

                Platform.logger.info("Starting async diffusion service creation...")
                Platform.logger.info("⏳ First-time Core ML compilation may take 5-15 minutes. Please wait...")

                Task {
                    do {
                        let service = DiffusionPlatformService()
                        try await service.initialize(
                            modelPath: modelPath,
                            reduceMemory: reduceMemory,
                            disableSafetyChecker: disableSafety,
                            tokenizerSource: tokenizerSource
                        )
                        Platform.diffusionService = service

                        // Return a marker handle
                        serviceHandle = UnsafeMutableRawPointer(bitPattern: 0xD1FF0510)
                        Platform.logger.info("✅ CoreML Diffusion service created successfully")
                    } catch {
                        Platform.logger.error("❌ Failed to create diffusion service: \(error)")
                        serviceHandle = nil
                    }
                    group.leave()
                }

                group.wait()
                return serviceHandle
            }

            callbacks.generate = { _, optionsPtr, outResultPtr, _ -> rac_result_t in
                guard #available(iOS 16.2, macOS 13.1, *) else {
                    return RAC_ERROR_NOT_SUPPORTED
                }

                guard let optionsPtr = optionsPtr, let outResultPtr = outResultPtr else {
                    return RAC_ERROR_INVALID_PARAMETER
                }

                guard let service = Platform.diffusionService as? DiffusionPlatformService else {
                    return RAC_ERROR_NOT_INITIALIZED
                }

                // Extract options
                let prompt = optionsPtr.pointee.prompt.map { String(cString: $0) } ?? ""
                let negativePrompt = optionsPtr.pointee.negative_prompt.map { String(cString: $0) } ?? ""
                let width = Int(optionsPtr.pointee.width)
                let height = Int(optionsPtr.pointee.height)
                let steps = Int(optionsPtr.pointee.steps)
                let guidanceScale = optionsPtr.pointee.guidance_scale
                let seed = optionsPtr.pointee.seed

                var result: rac_result_t = RAC_ERROR_INTERNAL
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        let genResult = try await service.generate(
                            prompt: prompt,
                            negativePrompt: negativePrompt,
                            width: width,
                            height: height,
                            stepCount: steps,
                            guidanceScale: guidanceScale,
                            seed: seed >= 0 ? UInt32(seed) : nil
                        )

                        // Copy result to output
                        outResultPtr.pointee.width = Int32(genResult.width)
                        outResultPtr.pointee.height = Int32(genResult.height)
                        outResultPtr.pointee.seed_used = genResult.seedUsed
                        outResultPtr.pointee.safety_triggered = genResult.safetyTriggered ? RAC_TRUE : RAC_FALSE

                        if let imageData = genResult.imageData {
                            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: imageData.count)
                            imageData.copyBytes(to: buffer, count: imageData.count)
                            outResultPtr.pointee.image_data = buffer
                            outResultPtr.pointee.image_size = imageData.count
                        }

                        result = RAC_SUCCESS
                    } catch {
                        Platform.logger.error("Diffusion generate failed: \(error)")
                        result = RAC_ERROR_INTERNAL
                    }
                    group.leave()
                }

                group.wait()
                return result
            }

            callbacks.generate_with_progress = { _, optionsPtr, progressCallback, progressUserData, outResultPtr, _ -> rac_result_t in
                guard #available(iOS 16.2, macOS 13.1, *) else {
                    return RAC_ERROR_NOT_SUPPORTED
                }

                guard let optionsPtr = optionsPtr, let outResultPtr = outResultPtr else {
                    return RAC_ERROR_INVALID_PARAMETER
                }

                guard let service = Platform.diffusionService as? DiffusionPlatformService else {
                    return RAC_ERROR_NOT_INITIALIZED
                }

                // Extract options
                let prompt = optionsPtr.pointee.prompt.map { String(cString: $0) } ?? ""
                let negativePrompt = optionsPtr.pointee.negative_prompt.map { String(cString: $0) } ?? ""
                let width = Int(optionsPtr.pointee.width)
                let height = Int(optionsPtr.pointee.height)
                let steps = Int(optionsPtr.pointee.steps)
                let guidanceScale = optionsPtr.pointee.guidance_scale
                let seed = optionsPtr.pointee.seed

                var result: rac_result_t = RAC_ERROR_INTERNAL
                let group = DispatchGroup()
                group.enter()

                Task {
                    do {
                        let genResult = try await service.generate(
                            prompt: prompt,
                            negativePrompt: negativePrompt,
                            width: width,
                            height: height,
                            stepCount: steps,
                            guidanceScale: guidanceScale,
                            seed: seed >= 0 ? UInt32(seed) : nil,
                            progressHandler: { progressInfo in
                                // Call C++ progress callback if provided
                                if let callback = progressCallback {
                                    let shouldContinue = callback(
                                        progressInfo.progress,
                                        Int32(progressInfo.step),
                                        Int32(progressInfo.totalSteps),
                                        progressUserData
                                    )
                                    return shouldContinue == RAC_TRUE
                                }
                                return true
                            }
                        )

                        // Copy result to output
                        outResultPtr.pointee.width = Int32(genResult.width)
                        outResultPtr.pointee.height = Int32(genResult.height)
                        outResultPtr.pointee.seed_used = genResult.seedUsed
                        outResultPtr.pointee.safety_triggered = genResult.safetyTriggered ? RAC_TRUE : RAC_FALSE

                        if let imageData = genResult.imageData {
                            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: imageData.count)
                            imageData.copyBytes(to: buffer, count: imageData.count)
                            outResultPtr.pointee.image_data = buffer
                            outResultPtr.pointee.image_size = imageData.count
                        }

                        result = RAC_SUCCESS
                    } catch {
                        Platform.logger.error("Diffusion generate_with_progress failed: \(error)")
                        result = RAC_ERROR_INTERNAL
                    }
                    group.leave()
                }

                group.wait()
                return result
            }

            callbacks.cancel = { _, _ -> rac_result_t in
                guard #available(iOS 16.2, macOS 13.1, *) else {
                    return RAC_SUCCESS
                }

                if let service = Platform.diffusionService as? DiffusionPlatformService {
                    Task {
                        await service.cancel()
                    }
                }
                return RAC_SUCCESS
            }

            callbacks.destroy = { _, _ in
                guard #available(iOS 16.2, macOS 13.1, *) else {
                    return
                }

                if let service = Platform.diffusionService as? DiffusionPlatformService {
                    Task {
                        await service.unload()
                    }
                }
                Platform.diffusionService = nil
                Platform.logger.debug("CoreML Diffusion service destroyed")
            }

            callbacks.user_data = nil

            let result = rac_platform_diffusion_set_callbacks(&callbacks)
            if result == RAC_SUCCESS {
                logger.debug("Diffusion callbacks registered")
            } else {
                logger.error("Failed to register Diffusion callbacks: \(result)")
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

        /// Get the cached Diffusion service (if created)
        @available(iOS 16.2, macOS 13.1, *)
        public static func getDiffusionService() -> DiffusionPlatformService? {
            return diffusionService as? DiffusionPlatformService
        }

        /// Check if CoreML Diffusion is available on this platform
        public static var isDiffusionAvailable: Bool {
            if #available(iOS 16.2, macOS 13.1, *) {
                return true
            }
            return false
        }
    }

    // swiftlint:enable type_body_length
}
