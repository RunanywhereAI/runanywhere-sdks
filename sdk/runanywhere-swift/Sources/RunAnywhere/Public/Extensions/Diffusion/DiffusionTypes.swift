//
//  DiffusionTypes.swift
//  RunAnywhere SDK
//
//  Public types for diffusion image generation.
//  These are thin wrappers over C++ types in rac_diffusion_types.h
//

import CRACommons
import Foundation

// MARK: - Diffusion Tokenizer Source

/// Tokenizer source for Stable Diffusion models.
/// Apple's compiled CoreML models don't include tokenizer files, so they must be downloaded separately.
/// This specifies which HuggingFace repository to download them from.
public enum DiffusionTokenizerSource: Sendable, Equatable {
    /// Stable Diffusion 1.x tokenizer (CLIP ViT-L/14)
    /// Source: runwayml/stable-diffusion-v1-5
    case sd15

    /// Stable Diffusion 2.x tokenizer (OpenCLIP ViT-H/14)
    /// Source: stabilityai/stable-diffusion-2-1
    case sd2

    /// Stable Diffusion XL tokenizer (dual tokenizers)
    /// Source: stabilityai/stable-diffusion-xl-base-1.0
    case sdxl

    /// Custom tokenizer from a specified base URL
    /// The URL should be a directory containing merges.txt and vocab.json
    /// Example: "https://huggingface.co/my-org/my-model/resolve/main/tokenizer"
    case custom(baseURL: String)

    /// The base URL for downloading tokenizer files
    public var baseURL: String {
        switch self {
        case .sd15:
            return "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer"
        case .sd2:
            return "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer"
        case .sdxl:
            return "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer"
        case .custom(let url):
            return url
        }
    }

    /// Human-readable description
    public var description: String {
        switch self {
        case .sd15: return "Stable Diffusion 1.5 (CLIP)"
        case .sd2: return "Stable Diffusion 2.x (OpenCLIP)"
        case .sdxl: return "Stable Diffusion XL"
        case .custom(let url): return "Custom (\(url))"
        }
    }

    /// C++ enum value for bridging to rac_diffusion_tokenizer_source_t
    public var cValue: rac_diffusion_tokenizer_source_t {
        switch self {
        case .sd15: return RAC_DIFFUSION_TOKENIZER_SD_1_5
        case .sd2: return RAC_DIFFUSION_TOKENIZER_SD_2_X
        case .sdxl: return RAC_DIFFUSION_TOKENIZER_SDXL
        case .custom: return RAC_DIFFUSION_TOKENIZER_CUSTOM
        }
    }

    /// Custom URL (only for .custom case)
    public var customURL: String? {
        switch self {
        case .custom(let url): return url
        default: return nil
        }
    }
}

// MARK: - Diffusion Model Variant

/// Stable Diffusion model variants
///
/// Hardware Acceleration:
/// - iOS/macOS: Uses CoreML Execution Provider (ANE → GPU → CPU automatic fallback)
/// - Android: Uses NNAPI Execution Provider (NPU → DSP → GPU → CPU automatic fallback)
/// - Desktop: Uses optimized CPU with SIMD
///
/// Fast Models (no CFG needed, 2x faster):
/// - `sdxs`: Ultra-fast 1-step model (~10 sec on mobile)
/// - `sdxlTurbo`: Fast 4-step model
/// - `lcm`: Latent Consistency Model, 4 steps
public enum DiffusionModelVariant: String, Sendable, CaseIterable {
    /// Stable Diffusion 1.5 (512x512 default)
    case sd15 = "sd15"

    /// Stable Diffusion 2.1 (768x768 default)
    case sd21 = "sd21"

    /// SDXL (1024x1024 default, requires 8GB+ RAM)
    case sdxl = "sdxl"

    /// SDXL Turbo - Fast 4-step, no CFG needed
    case sdxlTurbo = "sdxl_turbo"
    
    /// SDXS - Ultra-fast 1-step, no CFG needed
    /// Generates 512x512 images in ~10 seconds on mobile CPU, ~2 seconds with ANE
    case sdxs = "sdxs"
    
    /// LCM (Latent Consistency Model) - Fast 4-step with low CFG
    case lcm = "lcm"

    /// Default resolution for this variant
    public var defaultResolution: (width: Int, height: Int) {
        switch self {
        case .sd15, .sdxs, .lcm: return (512, 512)
        case .sd21: return (768, 768)
        case .sdxl, .sdxlTurbo: return (1024, 1024)
        }
    }
    
    /// Default number of inference steps
    public var defaultSteps: Int {
        switch self {
        case .sdxs: return 1              // Ultra-fast 1-step
        case .sdxlTurbo, .lcm: return 4   // Fast 4-step
        case .sd15, .sd21, .sdxl: return 20
        }
    }
    
    /// Default guidance scale
    public var defaultGuidanceScale: Float {
        switch self {
        case .sdxs, .sdxlTurbo: return 0.0  // No CFG needed
        case .lcm: return 1.5                // Low CFG
        case .sd15, .sd21, .sdxl: return 7.5
        }
    }
    
    /// Whether this model requires classifier-free guidance (CFG)
    /// CFG-free models run 2x faster as they skip the unconditional pass
    public var requiresCFG: Bool {
        switch self {
        case .sdxs, .sdxlTurbo: return false
        case .sd15, .sd21, .sdxl, .lcm: return true
        }
    }

    /// Default tokenizer source for this model variant
    public var defaultTokenizerSource: DiffusionTokenizerSource {
        switch self {
        case .sd15, .sdxs, .lcm: return .sd15
        case .sd21: return .sd2
        case .sdxl, .sdxlTurbo: return .sdxl
        }
    }

    var cValue: rac_diffusion_model_variant_t {
        switch self {
        case .sd15: return RAC_DIFFUSION_MODEL_SD_1_5
        case .sd21: return RAC_DIFFUSION_MODEL_SD_2_1
        case .sdxl: return RAC_DIFFUSION_MODEL_SDXL
        case .sdxlTurbo: return RAC_DIFFUSION_MODEL_SDXL_TURBO
        case .sdxs: return RAC_DIFFUSION_MODEL_SDXS
        case .lcm: return RAC_DIFFUSION_MODEL_LCM
        }
    }

    init(cValue: rac_diffusion_model_variant_t) {
        switch cValue {
        case RAC_DIFFUSION_MODEL_SD_1_5: self = .sd15
        case RAC_DIFFUSION_MODEL_SD_2_1: self = .sd21
        case RAC_DIFFUSION_MODEL_SDXL: self = .sdxl
        case RAC_DIFFUSION_MODEL_SDXL_TURBO: self = .sdxlTurbo
        case RAC_DIFFUSION_MODEL_SDXS: self = .sdxs
        case RAC_DIFFUSION_MODEL_LCM: self = .lcm
        default: self = .sd15
        }
    }
}

// MARK: - Diffusion Scheduler

/// Diffusion scheduler/sampler types for the denoising process
public enum DiffusionScheduler: String, Sendable, CaseIterable {
    /// DPM++ 2M Karras - Recommended for best quality/speed tradeoff
    case dpmPP2MKarras = "dpm++_2m_karras"

    /// DPM++ 2M
    case dpmPP2M = "dpm++_2m"

    /// DPM++ 2M SDE
    case dpmPP2MSDE = "dpm++_2m_sde"

    /// DDIM
    case ddim = "ddim"

    /// Euler
    case euler = "euler"

    /// Euler Ancestral
    case eulerAncestral = "euler_a"

    /// PNDM
    case pndm = "pndm"

    /// LMS
    case lms = "lms"

    var cValue: rac_diffusion_scheduler_t {
        switch self {
        case .dpmPP2MKarras: return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS
        case .dpmPP2M: return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M
        case .dpmPP2MSDE: return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_SDE
        case .ddim: return RAC_DIFFUSION_SCHEDULER_DDIM
        case .euler: return RAC_DIFFUSION_SCHEDULER_EULER
        case .eulerAncestral: return RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL
        case .pndm: return RAC_DIFFUSION_SCHEDULER_PNDM
        case .lms: return RAC_DIFFUSION_SCHEDULER_LMS
        }
    }

    init(cValue: rac_diffusion_scheduler_t) {
        switch cValue {
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS: self = .dpmPP2MKarras
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M: self = .dpmPP2M
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_SDE: self = .dpmPP2MSDE
        case RAC_DIFFUSION_SCHEDULER_DDIM: self = .ddim
        case RAC_DIFFUSION_SCHEDULER_EULER: self = .euler
        case RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL: self = .eulerAncestral
        case RAC_DIFFUSION_SCHEDULER_PNDM: self = .pndm
        case RAC_DIFFUSION_SCHEDULER_LMS: self = .lms
        default: self = .dpmPP2MKarras
        }
    }
}

// MARK: - Diffusion Mode

/// Generation mode for diffusion
public enum DiffusionMode: String, Sendable {
    /// Generate image from text prompt
    case textToImage = "txt2img"

    /// Transform input image with prompt
    case imageToImage = "img2img"

    /// Edit specific regions with mask
    case inpainting = "inpainting"

    var cValue: rac_diffusion_mode_t {
        switch self {
        case .textToImage: return RAC_DIFFUSION_MODE_TEXT_TO_IMAGE
        case .imageToImage: return RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE
        case .inpainting: return RAC_DIFFUSION_MODE_INPAINTING
        }
    }
}

// MARK: - Diffusion Configuration

/// Configuration for the diffusion component
public struct DiffusionConfiguration: ComponentConfiguration, Sendable {

    // MARK: - ComponentConfiguration

    /// Component type
    public var componentType: SDKComponent { .diffusion }

    /// Model ID (optional - uses default if not specified)
    public let modelId: String?

    /// Preferred framework for generation
    public let preferredFramework: InferenceFramework?

    // MARK: - Model Configuration

    /// Model variant (SD 1.5, SD 2.1, SDXL, etc.)
    public let modelVariant: DiffusionModelVariant

    /// Enable safety checker for NSFW content filtering
    public let enableSafetyChecker: Bool

    /// Reduce memory footprint (may reduce quality)
    public let reduceMemory: Bool

    /// Tokenizer source for downloading missing tokenizer files
    /// Apple's compiled CoreML models don't include tokenizer files (merges.txt, vocab.json).
    /// If nil, defaults to the tokenizer matching the model variant.
    public let tokenizerSource: DiffusionTokenizerSource?

    // MARK: - Initialization

    public init(
        modelId: String? = nil,
        modelVariant: DiffusionModelVariant = .sd15,
        enableSafetyChecker: Bool = true,
        reduceMemory: Bool = false,
        preferredFramework: InferenceFramework? = nil,
        tokenizerSource: DiffusionTokenizerSource? = nil
    ) {
        self.modelId = modelId
        self.modelVariant = modelVariant
        self.enableSafetyChecker = enableSafetyChecker
        self.reduceMemory = reduceMemory
        self.preferredFramework = preferredFramework
        self.tokenizerSource = tokenizerSource
    }

    /// The effective tokenizer source (uses model variant default if not specified)
    public var effectiveTokenizerSource: DiffusionTokenizerSource {
        tokenizerSource ?? modelVariant.defaultTokenizerSource
    }

    // MARK: - Validation

    public func validate() throws {
        // Configuration is always valid - defaults are used
    }
}

// MARK: - Diffusion Generation Options

/// Options for image generation
public struct DiffusionGenerationOptions: Sendable {

    /// Text prompt describing the desired image
    public let prompt: String

    /// Negative prompt - things to avoid in the image
    public let negativePrompt: String

    /// Output image width in pixels
    public let width: Int

    /// Output image height in pixels
    public let height: Int

    /// Number of denoising steps (10-50, default: 28)
    public let steps: Int

    /// Classifier-free guidance scale (1.0-20.0, default: 7.5)
    public let guidanceScale: Float

    /// Random seed for reproducibility (-1 for random)
    public let seed: Int64

    /// Scheduler/sampler algorithm
    public let scheduler: DiffusionScheduler

    /// Generation mode
    public let mode: DiffusionMode

    /// Input image data for img2img/inpainting (PNG/JPEG data)
    public let inputImage: Data?

    /// Mask image data for inpainting (grayscale PNG data)
    public let maskImage: Data?

    /// Denoising strength for img2img (0.0-1.0)
    public let denoiseStrength: Float

    /// Report intermediate images during generation
    public let reportIntermediateImages: Bool

    /// Report progress every N steps
    public let progressStride: Int

    // MARK: - Initialization

    public init(
        prompt: String,
        negativePrompt: String = "",
        width: Int = 512,
        height: Int = 512,
        steps: Int = 28,
        guidanceScale: Float = 7.5,
        seed: Int64 = -1,
        scheduler: DiffusionScheduler = .dpmPP2MKarras,
        mode: DiffusionMode = .textToImage,
        inputImage: Data? = nil,
        maskImage: Data? = nil,
        denoiseStrength: Float = 0.75,
        reportIntermediateImages: Bool = false,
        progressStride: Int = 1
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.width = width
        self.height = height
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.scheduler = scheduler
        self.mode = mode
        self.inputImage = inputImage
        self.maskImage = maskImage
        self.denoiseStrength = denoiseStrength
        self.reportIntermediateImages = reportIntermediateImages
        self.progressStride = progressStride
    }

    /// Create options for text-to-image generation
    public static func textToImage(
        prompt: String,
        negativePrompt: String = "",
        width: Int = 512,
        height: Int = 512,
        steps: Int = 28,
        guidanceScale: Float = 7.5,
        seed: Int64 = -1,
        scheduler: DiffusionScheduler = .dpmPP2MKarras
    ) -> DiffusionGenerationOptions {
        DiffusionGenerationOptions(
            prompt: prompt,
            negativePrompt: negativePrompt,
            width: width,
            height: height,
            steps: steps,
            guidanceScale: guidanceScale,
            seed: seed,
            scheduler: scheduler,
            mode: .textToImage
        )
    }

    /// Create options for image-to-image transformation
    public static func imageToImage(
        prompt: String,
        inputImage: Data,
        negativePrompt: String = "",
        denoiseStrength: Float = 0.75,
        steps: Int = 28,
        guidanceScale: Float = 7.5,
        seed: Int64 = -1,
        scheduler: DiffusionScheduler = .dpmPP2MKarras
    ) -> DiffusionGenerationOptions {
        DiffusionGenerationOptions(
            prompt: prompt,
            negativePrompt: negativePrompt,
            steps: steps,
            guidanceScale: guidanceScale,
            seed: seed,
            scheduler: scheduler,
            mode: .imageToImage,
            inputImage: inputImage,
            denoiseStrength: denoiseStrength
        )
    }

    /// Create options for inpainting
    public static func inpainting(
        prompt: String,
        inputImage: Data,
        maskImage: Data,
        negativePrompt: String = "",
        steps: Int = 28,
        guidanceScale: Float = 7.5,
        seed: Int64 = -1,
        scheduler: DiffusionScheduler = .dpmPP2MKarras
    ) -> DiffusionGenerationOptions {
        DiffusionGenerationOptions(
            prompt: prompt,
            negativePrompt: negativePrompt,
            steps: steps,
            guidanceScale: guidanceScale,
            seed: seed,
            scheduler: scheduler,
            mode: .inpainting,
            inputImage: inputImage,
            maskImage: maskImage
        )
    }
}

// MARK: - Diffusion Progress

/// Progress update during image generation
public struct DiffusionProgress: Sendable {

    /// Progress percentage (0.0 - 1.0)
    public let progress: Float

    /// Current step number (1-based)
    public let currentStep: Int

    /// Total number of steps
    public let totalSteps: Int

    /// Current stage description
    public let stage: String

    /// Intermediate image data (PNG, available if requested)
    public let intermediateImage: Data?

    public init(
        progress: Float,
        currentStep: Int,
        totalSteps: Int,
        stage: String,
        intermediateImage: Data? = nil
    ) {
        self.progress = progress
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.stage = stage
        self.intermediateImage = intermediateImage
    }

    /// Initialize from C++ rac_diffusion_progress_t
    init(from cProgress: rac_diffusion_progress_t) {
        self.progress = cProgress.progress
        self.currentStep = Int(cProgress.current_step)
        self.totalSteps = Int(cProgress.total_steps)
        self.stage = cProgress.stage.map { String(cString: $0) } ?? "Processing"

        if let imageData = cProgress.intermediate_image_data, cProgress.intermediate_image_size > 0 {
            self.intermediateImage = Data(bytes: imageData, count: Int(cProgress.intermediate_image_size))
        } else {
            self.intermediateImage = nil
        }
    }
}

// MARK: - Diffusion Result

/// Result of image generation
public struct DiffusionResult: Sendable {

    /// Generated image data (PNG format)
    public let imageData: Data

    /// Image width in pixels
    public let width: Int

    /// Image height in pixels
    public let height: Int

    /// Seed used for generation (for reproducibility)
    public let seedUsed: Int64

    /// Total generation time in milliseconds
    public let generationTimeMs: Int64

    /// Whether the image was flagged by safety checker
    public let safetyFlagged: Bool

    public init(
        imageData: Data,
        width: Int,
        height: Int,
        seedUsed: Int64,
        generationTimeMs: Int64,
        safetyFlagged: Bool = false
    ) {
        self.imageData = imageData
        self.width = width
        self.height = height
        self.seedUsed = seedUsed
        self.generationTimeMs = generationTimeMs
        self.safetyFlagged = safetyFlagged
    }

    /// Initialize from C++ rac_diffusion_result_t
    init(from cResult: rac_diffusion_result_t) {
        if let imageData = cResult.image_data, cResult.image_size > 0 {
            self.imageData = Data(bytes: imageData, count: Int(cResult.image_size))
        } else {
            self.imageData = Data()
        }
        self.width = Int(cResult.width)
        self.height = Int(cResult.height)
        self.seedUsed = cResult.seed_used
        self.generationTimeMs = cResult.generation_time_ms
        self.safetyFlagged = cResult.safety_flagged == RAC_TRUE
    }
}

// MARK: - SDKError Extension for Diffusion

public extension SDKError {

    /// Diffusion error codes
    enum DiffusionErrorCode: String, Sendable {
        case notInitialized = "diffusion_not_initialized"
        case modelNotFound = "diffusion_model_not_found"
        case modelLoadFailed = "diffusion_model_load_failed"
        case initializationFailed = "diffusion_initialization_failed"
        case generationFailed = "diffusion_generation_failed"
        case cancelled = "diffusion_cancelled"
        case invalidOptions = "diffusion_invalid_options"
        case unsupportedMode = "diffusion_unsupported_mode"
        case outOfMemory = "diffusion_out_of_memory"
        case safetyCheckFailed = "diffusion_safety_check_failed"
        case configurationFailed = "diffusion_configuration_failed"
    }

    /// Create a diffusion error
    static func diffusion(_ code: DiffusionErrorCode, _ message: String) -> SDKError {
        SDKError.general(.generationFailed, "[\(code.rawValue)] \(message)")
    }
}
