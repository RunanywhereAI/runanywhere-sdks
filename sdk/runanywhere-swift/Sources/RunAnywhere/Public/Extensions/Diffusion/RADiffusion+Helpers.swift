//
//  RADiffusion+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical Diffusion proto types.
//

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
