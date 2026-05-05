//
//  CppBridge+Diffusion.swift
//  RunAnywhere SDK
//
//  Diffusion component bridge - manages C++ Diffusion component lifecycle.
//  Uses canonical generated proto types directly; no hand-written DTOs.
//

import CRACommons
import Foundation

// MARK: - Diffusion Component Bridge

extension CppBridge {

    actor Diffusion {

        public static let shared = Diffusion()

        private var handle: rac_handle_t?
        private var loadedModelId: String?
        private var currentConfig: RADiffusionConfiguration?
        private let logger = SDKLogger(category: "CppBridge.Diffusion")

        private init() {}

        // MARK: - Handle Management

        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }

            var newHandle: rac_handle_t?
            let result = rac_diffusion_component_create(&newHandle)
            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKException.diffusion(.notInitialized, "Failed to create Diffusion component: \(result)")
            }

            self.handle = handle
            logger.debug("Diffusion component created")
            return handle
        }

        // MARK: - Configuration

        /// Configure the component from the generated proto configuration.
        public func configure(_ config: RADiffusionConfiguration) throws {
            let handle = try getHandle()

            var cConfig = rac_diffusion_config_t()
            cConfig.model_variant = config.modelVariant.cValue
            cConfig.enable_safety_checker = config.enableSafetyChecker ? RAC_TRUE : RAC_FALSE
            cConfig.reduce_memory = RAC_FALSE
            if config.hasPreferredFramework {
                cConfig.preferred_framework = Int32(bitPattern: config.preferredFramework.toC().rawValue)
            } else {
                cConfig.preferred_framework = Int32(bitPattern: RAC_FRAMEWORK_UNKNOWN.rawValue)
            }

            let tokenizerSource = config.effectiveTokenizerSource
            cConfig.tokenizer.source = tokenizerSource.cValue
            cConfig.tokenizer.auto_download = RAC_TRUE

            let configureBlock: () throws -> Void = {
                if let customURL = tokenizerSource.customURL {
                    let result = customURL.withCString { urlPtr in
                        cConfig.tokenizer.custom_base_url = urlPtr
                        return rac_diffusion_component_configure(handle, &cConfig)
                    }
                    guard result == RAC_SUCCESS else {
                        throw SDKException.diffusion(.invalidConfiguration, "Failed to configure Diffusion component: \(result)")
                    }
                } else {
                    cConfig.tokenizer.custom_base_url = nil
                    let result = rac_diffusion_component_configure(handle, &cConfig)
                    guard result == RAC_SUCCESS else {
                        throw SDKException.diffusion(.invalidConfiguration, "Failed to configure Diffusion component: \(result)")
                    }
                }
            }

            if config.hasModelID && !config.modelID.isEmpty {
                try config.modelID.withCString { idPtr in
                    cConfig.model_id = idPtr
                    try configureBlock()
                }
            } else {
                cConfig.model_id = nil
                try configureBlock()
            }

            currentConfig = config
            logger.info("Diffusion component configured with model variant: \(config.modelVariant), tokenizer: \(tokenizerSource.displayName)")
        }

        // MARK: - State

        public var isLoaded: Bool {
            guard let handle = handle else { return false }
            return rac_diffusion_component_is_loaded(handle) == RAC_TRUE
        }

        public var currentModelId: String? { loadedModelId }

        public var configuration: RADiffusionConfiguration? { currentConfig }

        // MARK: - Model Lifecycle

        public func loadModel(_ modelPath: String, modelId: String, modelName: String) throws {
            let handle = try getHandle()
            let result = modelPath.withCString { pathPtr in
                modelId.withCString { idPtr in
                    modelName.withCString { namePtr in
                        rac_diffusion_component_load_model(handle, pathPtr, idPtr, namePtr)
                    }
                }
            }
            guard result == RAC_SUCCESS else {
                throw SDKException.diffusion(.modelLoadFailed, "Failed to load diffusion model: \(result)")
            }
            loadedModelId = modelId
            logger.info("Diffusion model loaded: \(modelId)")
        }

        public func unload() {
            guard let handle = handle else { return }
            rac_diffusion_component_cleanup(handle)
            loadedModelId = nil
            logger.info("Diffusion model unloaded")
        }

        // MARK: - Generation
        //
        // The proto-based generate/generateWithProgress methods are defined in
        // CppBridge+ModalityProtoABI.swift and forward through the canonical
        // proto-byte ABI. This actor only owns the component lifecycle.

        public func cancel() {
            guard let handle = handle else { return }
            rac_diffusion_component_cancel(handle)
            logger.info("Diffusion generation cancelled")
        }

        public func destroy() {
            if let handle = handle {
                rac_diffusion_component_destroy(handle)
                self.handle = nil
                loadedModelId = nil
                currentConfig = nil
                logger.debug("Diffusion component destroyed")
            }
        }

        // MARK: - Capabilities

        public func getCapabilities() -> RADiffusionCapabilities {
            guard let handle = handle else {
                return RADiffusionCapabilities()
            }
            let caps = rac_diffusion_component_get_capabilities(handle)
            return RADiffusionCapabilities(rawCapabilities: caps)
        }
    }
}

// MARK: - Helpers

private extension RADiffusionCapabilities {
    init(rawCapabilities: UInt32) {
        self.init()

        func has(_ flag: UInt32) -> Bool {
            (rawCapabilities & flag) != 0
        }

        if has(UInt32(RAC_DIFFUSION_CAP_TEXT_TO_IMAGE)) {
            supportedModes.append(.textToImage)
        }
        if has(UInt32(RAC_DIFFUSION_CAP_IMAGE_TO_IMAGE)) {
            supportedModes.append(.imageToImage)
        }
        if has(UInt32(RAC_DIFFUSION_CAP_INPAINTING)) {
            supportedModes.append(.inpainting)
        }

        supportsIntermediateImages = has(UInt32(RAC_DIFFUSION_CAP_INTERMEDIATE_IMAGES))
        supportsSafetyChecker = has(UInt32(RAC_DIFFUSION_CAP_SAFETY_CHECKER))
    }
}
