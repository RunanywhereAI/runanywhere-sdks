//
//  CppBridge+Diffusion.swift
//  RunAnywhere SDK
//
//  Diffusion component bridge - manages C++ Diffusion component lifecycle
//

import CRACommons
import Foundation

// MARK: - Diffusion Component Bridge

extension CppBridge {

    /// Diffusion component manager
    /// Provides thread-safe access to the C++ Diffusion component
    public actor Diffusion {

        /// Shared Diffusion component instance
        public static let shared = Diffusion()

        private var handle: rac_handle_t?
        private var loadedModelId: String?
        private var currentConfig: DiffusionConfiguration?
        private let logger = SDKLogger(category: "CppBridge.Diffusion")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the Diffusion component handle
        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }

            var newHandle: rac_handle_t?
            let result = rac_diffusion_component_create(&newHandle)
            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKError.diffusion(.notInitialized, "Failed to create Diffusion component: \(result)")
            }

            self.handle = handle
            logger.debug("Diffusion component created")
            return handle
        }

        // MARK: - Configuration

        /// Configure the component
        public func configure(_ config: DiffusionConfiguration) throws {
            let handle = try getHandle()

            var cConfig = rac_diffusion_config_t()
            cConfig.model_variant = config.modelVariant.cValue
            cConfig.enable_safety_checker = config.enableSafetyChecker ? RAC_TRUE : RAC_FALSE
            cConfig.reduce_memory = config.reduceMemory ? RAC_TRUE : RAC_FALSE
            cConfig.preferred_framework = 99 // RAC_FRAMEWORK_UNKNOWN - let system choose

            // Configure tokenizer source
            let tokenizerSource = config.effectiveTokenizerSource
            cConfig.tokenizer.source = tokenizerSource.cValue
            cConfig.tokenizer.auto_download = RAC_TRUE

            // Handle custom URL if provided
            if let customURL = tokenizerSource.customURL {
                let result = customURL.withCString { urlPtr in
                    cConfig.tokenizer.custom_base_url = urlPtr
                    return rac_diffusion_component_configure(handle, &cConfig)
                }
                guard result == RAC_SUCCESS else {
                    throw SDKError.diffusion(.configurationFailed, "Failed to configure Diffusion component: \(result)")
                }
            } else {
                cConfig.tokenizer.custom_base_url = nil
                let result = rac_diffusion_component_configure(handle, &cConfig)
                guard result == RAC_SUCCESS else {
                    throw SDKError.diffusion(.configurationFailed, "Failed to configure Diffusion component: \(result)")
                }
            }

            currentConfig = config
            logger.info("Diffusion component configured with model variant: \(config.modelVariant), tokenizer: \(tokenizerSource.description)")
        }

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            guard let handle = handle else { return false }
            return rac_diffusion_component_is_loaded(handle) == RAC_TRUE
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        /// Get the current configuration
        public var configuration: DiffusionConfiguration? { currentConfig }

        // MARK: - Model Lifecycle

        /// Load a diffusion model
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
                throw SDKError.diffusion(.modelLoadFailed, "Failed to load diffusion model: \(result)")
            }
            loadedModelId = modelId
            logger.info("Diffusion model loaded: \(modelId)")
        }

        /// Unload the current model
        public func unload() {
            guard let handle = handle else { return }
            rac_diffusion_component_cleanup(handle)
            loadedModelId = nil
            logger.info("Diffusion model unloaded")
        }

        /// Cancel ongoing generation
        public func cancel() {
            guard let handle = handle else { return }
            rac_diffusion_component_cancel(handle)
            logger.info("Diffusion generation cancelled")
        }

        // MARK: - Cleanup

        /// Destroy the component
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

        /// Get supported capabilities
        public func getCapabilities() -> DiffusionCapabilities {
            guard let handle = handle else {
                return DiffusionCapabilities(rawValue: 0)
            }
            let caps = rac_diffusion_component_get_capabilities(handle)
            return DiffusionCapabilities(rawValue: caps)
        }

        /// Get service info
        public func getInfo() throws -> DiffusionInfo {
            let handle = try getHandle()
            var cInfo = rac_diffusion_info_t()
            let result = rac_diffusion_component_get_info(handle, &cInfo)
            guard result == RAC_SUCCESS else {
                throw SDKError.diffusion(.notInitialized, "Failed to get diffusion info: \(result)")
            }
            return DiffusionInfo(from: cInfo)
        }
    }
}

// MARK: - Diffusion Capabilities

/// Bitmask of supported diffusion capabilities
public struct DiffusionCapabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Supports text-to-image generation
    public static let textToImage = DiffusionCapabilities(rawValue: UInt32(RAC_DIFFUSION_CAP_TEXT_TO_IMAGE))

    /// Supports image-to-image transformation
    public static let imageToImage = DiffusionCapabilities(rawValue: UInt32(RAC_DIFFUSION_CAP_IMAGE_TO_IMAGE))

    /// Supports inpainting with mask
    public static let inpainting = DiffusionCapabilities(rawValue: UInt32(RAC_DIFFUSION_CAP_INPAINTING))

    /// Supports intermediate image reporting
    public static let intermediateImages = DiffusionCapabilities(rawValue: UInt32(RAC_DIFFUSION_CAP_INTERMEDIATE_IMAGES))

    /// Has safety checker
    public static let safetyChecker = DiffusionCapabilities(rawValue: UInt32(RAC_DIFFUSION_CAP_SAFETY_CHECKER))
}

// MARK: - Diffusion Info

/// Information about the diffusion service
public struct DiffusionInfo: Sendable {
    public let isReady: Bool
    public let currentModel: String?
    public let modelVariant: DiffusionModelVariant
    public let supportsTextToImage: Bool
    public let supportsImageToImage: Bool
    public let supportsInpainting: Bool
    public let safetyCheckerEnabled: Bool
    public let maxWidth: Int
    public let maxHeight: Int

    init(from cInfo: rac_diffusion_info_t) {
        self.isReady = cInfo.is_ready == RAC_TRUE
        self.currentModel = cInfo.current_model.map { String(cString: $0) }
        self.modelVariant = DiffusionModelVariant(cValue: cInfo.model_variant)
        self.supportsTextToImage = cInfo.supports_text_to_image == RAC_TRUE
        self.supportsImageToImage = cInfo.supports_image_to_image == RAC_TRUE
        self.supportsInpainting = cInfo.supports_inpainting == RAC_TRUE
        self.safetyCheckerEnabled = cInfo.safety_checker_enabled == RAC_TRUE
        self.maxWidth = Int(cInfo.max_width)
        self.maxHeight = Int(cInfo.max_height)
    }
}

// MARK: - Diffusion Backend Selection

/// Backend used for diffusion inference
public enum DiffusionBackend: Int32, Sendable {
    case onnx = 0       /// ONNX Runtime (cross-platform, uses CoreML EP on iOS or NNAPI EP on Android)
    case coreml = 1     /// CoreML (iOS/macOS only, uses ANE → GPU → CPU automatic fallback)
    case tflite = 2     /// TensorFlow Lite (future)
    case auto = 99      /// Auto-select best for platform
    
    /// Convert from C enum
    init(cValue: rac_diffusion_backend_t) {
        switch cValue {
        case RAC_DIFFUSION_BACKEND_ONNX: self = .onnx
        case RAC_DIFFUSION_BACKEND_COREML: self = .coreml
        case RAC_DIFFUSION_BACKEND_TFLITE: self = .tflite
        case RAC_DIFFUSION_BACKEND_AUTO: self = .auto
        default: self = .onnx
        }
    }
    
    /// Convert to C enum
    var cValue: rac_diffusion_backend_t {
        switch self {
        case .onnx: return RAC_DIFFUSION_BACKEND_ONNX
        case .coreml: return RAC_DIFFUSION_BACKEND_COREML
        case .tflite: return RAC_DIFFUSION_BACKEND_TFLITE
        case .auto: return RAC_DIFFUSION_BACKEND_AUTO
        }
    }
}

// MARK: - Diffusion Model Registry Bridge

extension CppBridge {
    
    /// Diffusion Model Registry - provides access to built-in and custom model definitions
    public enum DiffusionModelRegistry {
        
        private static let logger = SDKLogger(category: "CppBridge.DiffusionModelRegistry")
        
        /// Select the best backend for a model on the current platform
        /// 
        /// Backend selection follows this priority:
        /// - iOS/macOS: CoreML (ANE → GPU → CPU automatic fallback) if model supports it
        /// - Android: ONNX with NNAPI EP (NPU → DSP → GPU → CPU automatic fallback)
        /// - Desktop: ONNX with CPU EP
        ///
        /// - Parameter modelId: The model identifier
        /// - Returns: The best backend for this model on current platform
        public static func selectBackend(forModel modelId: String) -> DiffusionBackend {
            let backend = modelId.withCString { idPtr in
                rac_diffusion_model_registry_select_backend(idPtr)
            }
            return DiffusionBackend(cValue: backend)
        }
        
        /// Check if a model is available on the current platform
        ///
        /// - Parameter modelId: The model identifier
        /// - Returns: True if the model is available
        public static func isAvailable(modelId: String) -> Bool {
            let available = modelId.withCString { idPtr in
                rac_diffusion_model_registry_is_available(idPtr)
            }
            return available == RAC_TRUE
        }
        
        /// Check if a model variant requires classifier-free guidance (CFG)
        ///
        /// CFG-free models (SDXS, SDXL Turbo) don't need the unconditional pass,
        /// making them 2x faster during inference.
        ///
        /// - Parameter variant: The model variant
        /// - Returns: True if CFG is required
        public static func requiresCFG(variant: DiffusionModelVariant) -> Bool {
            return rac_diffusion_model_requires_cfg(variant.cValue) == RAC_TRUE
        }
        
        /// Get the current platform identifier
        public static var currentPlatform: UInt32 {
            return rac_diffusion_model_registry_get_current_platform()
        }
    }
}
