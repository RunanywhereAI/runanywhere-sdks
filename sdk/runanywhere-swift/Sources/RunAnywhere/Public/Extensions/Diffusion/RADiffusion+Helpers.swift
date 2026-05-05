//
//  RADiffusion+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical Diffusion proto types.
//

import CRACommons
import Foundation

// MARK: - RADiffusionTokenizerSource

extension RADiffusionTokenizerSource {
    public enum Case: Sendable, Equatable {
        case unspecified
        case bundledSd15
        case bundledSd2
        case bundledSdxl
        case custom(path: String)
    }

    public var asCase: Case {
        switch kind {
        case .unspecified, .UNRECOGNIZED: return .unspecified
        case .bundledSd15:                return .bundledSd15
        case .bundledSd2:                 return .bundledSd2
        case .bundledSdxl:                return .bundledSdxl
        case .custom:                     return .custom(path: customPath)
        }
    }

    public static func from(_ kase: Case) -> RADiffusionTokenizerSource {
        var s = RADiffusionTokenizerSource()
        switch kase {
        case .unspecified:       s.kind = .unspecified
        case .bundledSd15:       s.kind = .bundledSd15
        case .bundledSd2:        s.kind = .bundledSd2
        case .bundledSdxl:       s.kind = .bundledSdxl
        case .custom(let path):
            s.kind = .custom
            s.customPath = path
        }
        return s
    }

    var cValue: rac_diffusion_tokenizer_source_t {
        switch kind {
        case .bundledSd15:
            return RAC_DIFFUSION_TOKENIZER_SD_1_5
        case .bundledSd2:
            return RAC_DIFFUSION_TOKENIZER_SD_2_X
        case .bundledSdxl:
            return RAC_DIFFUSION_TOKENIZER_SDXL
        case .custom:
            return RAC_DIFFUSION_TOKENIZER_CUSTOM
        default:
            return RAC_DIFFUSION_TOKENIZER_SD_1_5
        }
    }

    var customURL: String? {
        kind == .custom ? customPath : nil
    }

    var displayName: String {
        switch kind {
        case .bundledSd15:
            return "Stable Diffusion 1.5 (CLIP)"
        case .bundledSd2:
            return "Stable Diffusion 2.x (OpenCLIP)"
        case .bundledSdxl:
            return "Stable Diffusion XL"
        case .custom:
            return "Custom (\(customPath))"
        default:
            return "Stable Diffusion 1.5 (CLIP)"
        }
    }

    /// Base URL for downloading tokenizer files for this source. Custom sources
    /// return the user-supplied path; bundled sources return the canonical
    /// HuggingFace tokenizer location.
    var tokenizerBaseURL: String {
        switch kind {
        case .bundledSd15:
            return "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer"
        case .bundledSd2:
            return "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer"
        case .bundledSdxl:
            return "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer"
        case .custom:
            return customPath
        default:
            return "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer"
        }
    }
}

// MARK: - RADiffusionConfiguration

extension RADiffusionConfiguration {
    /// Default configuration: SD 1.5 with bundled tokenizer, safety on.
    public static func defaults() -> RADiffusionConfiguration {
        var c = RADiffusionConfiguration()
        c.modelVariant = .sd15
        var ts = RADiffusionTokenizerSource()
        ts.kind = .bundledSd15
        c.tokenizerSource = ts
        c.enableSafetyChecker = true
        return c
    }

    var effectiveTokenizerSource: RADiffusionTokenizerSource {
        hasTokenizerSource ? tokenizerSource : modelVariant.defaultTokenizerSource
    }
}

// MARK: - RADiffusionGenerationOptions

extension RADiffusionGenerationOptions {
    /// Default options: 512x512 text-to-image at 20 steps with DPM++ 2M Karras.
    public static func defaults(prompt: String = "") -> RADiffusionGenerationOptions {
        var o = RADiffusionGenerationOptions()
        o.prompt = prompt
        o.width = 512
        o.height = 512
        o.numInferenceSteps = 20
        o.guidanceScale = 7.5
        o.scheduler = .dpmpp2MKarras
        o.mode = .textToImage
        return o
    }
}

// MARK: - RADiffusionResult

extension RADiffusionResult {
    /// Generation time as a `TimeInterval` (seconds).
    public var generationTime: TimeInterval { TimeInterval(totalTimeMs) / 1000.0 }
}

extension RADiffusionModelVariant {
    var defaultTokenizerSource: RADiffusionTokenizerSource {
        switch self {
        case .sd21:
            return .from(.bundledSd2)
        case .sdxl, .sdxlTurbo:
            return .from(.bundledSdxl)
        default:
            return .from(.bundledSd15)
        }
    }

    var cValue: rac_diffusion_model_variant_t {
        switch self {
        case .sd15:
            return RAC_DIFFUSION_MODEL_SD_1_5
        case .sd21:
            return RAC_DIFFUSION_MODEL_SD_2_1
        case .sdxl:
            return RAC_DIFFUSION_MODEL_SDXL
        case .sdxlTurbo:
            return RAC_DIFFUSION_MODEL_SDXL_TURBO
        case .sdxs:
            return RAC_DIFFUSION_MODEL_SDXS
        case .lcm:
            return RAC_DIFFUSION_MODEL_LCM
        default:
            return RAC_DIFFUSION_MODEL_SD_1_5
        }
    }

    public init(cValue: rac_diffusion_model_variant_t) {
        switch cValue {
        case RAC_DIFFUSION_MODEL_SD_1_5:
            self = .sd15
        case RAC_DIFFUSION_MODEL_SD_2_1:
            self = .sd21
        case RAC_DIFFUSION_MODEL_SDXL:
            self = .sdxl
        case RAC_DIFFUSION_MODEL_SDXL_TURBO:
            self = .sdxlTurbo
        case RAC_DIFFUSION_MODEL_SDXS:
            self = .sdxs
        case RAC_DIFFUSION_MODEL_LCM:
            self = .lcm
        default:
            self = .sd15
        }
    }
}

extension RADiffusionScheduler {
    var cValue: rac_diffusion_scheduler_t {
        switch self {
        case .dpmpp2MKarras:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS
        case .dpmpp2M:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M
        case .ddim:
            return RAC_DIFFUSION_SCHEDULER_DDIM
        case .euler:
            return RAC_DIFFUSION_SCHEDULER_EULER
        case .eulerA:
            return RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL
        case .pndm:
            return RAC_DIFFUSION_SCHEDULER_PNDM
        case .lms:
            return RAC_DIFFUSION_SCHEDULER_LMS
        default:
            return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS
        }
    }
}

extension RADiffusionMode {
    var cValue: rac_diffusion_mode_t {
        switch self {
        case .imageToImage:
            return RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE
        case .inpainting:
            return RAC_DIFFUSION_MODE_INPAINTING
        default:
            return RAC_DIFFUSION_MODE_TEXT_TO_IMAGE
        }
    }
}
