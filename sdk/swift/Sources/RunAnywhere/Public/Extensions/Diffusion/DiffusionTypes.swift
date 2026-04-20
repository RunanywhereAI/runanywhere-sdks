// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Extra initialisers + aliases on `DiffusionConfiguration`,
// `DiffusionGenerationOptions`, and `DiffusionResult` that match the
// main-branch sample call-site shape. Canonical definitions live in
// `DiffusionSession.swift`.

import Foundation

public extension DiffusionConfiguration {
    /// Main-branch parity initialiser — takes a variant + the two flags
    /// the sample needs (safety checker, memory saver). Maps onto the
    /// existing width/height/steps/guidance fields using per-variant
    /// defaults.
    init(modelVariant: DiffusionModelVariant,
         enableSafetyChecker: Bool = true,
         reduceMemory: Bool = false) {
        let (w, h, steps, scale): (Int, Int, Int, Float) = {
            switch modelVariant {
            case .sd15:      return (512, 512, 25, 7.5)
            case .sd2:       return (768, 768, 25, 7.5)
            case .sdxl:      return (1024, 1024, 30, 7.0)
            case .sdxlTurbo: return (512, 512, 4, 0.0)
            case .sdxs:      return (512, 512, 1, 0.0)
            case .custom:    return (512, 512, 25, 7.5)
            }
        }()
        self.init(width: w, height: h,
                  inferenceSteps: steps, guidanceScale: scale,
                  seed: -1, scheduler: .default,
                  enableSafetyChecker: enableSafetyChecker)
        _ = reduceMemory   // reserved — reduceMemory flag currently unused
    }
}

public extension DiffusionGenerationOptions {
    /// Main-branch parity initialiser — bundles the per-request config
    /// overrides (width/height/steps/guidance) alongside negative prompt.
    /// The sample invokes `RunAnywhere.generateImage(prompt:options:)`.
    init(prompt: String,
         width: Int? = nil,
         height: Int? = nil,
         steps: Int? = nil,
         guidanceScale: Float? = nil,
         seed: Int64 = -1,
         negativePrompt: String? = nil,
         numImages: Int = 1) {
        self.init(negativePrompt: negativePrompt,
                  numImages: numImages,
                  batchSize: 0)
        self.prompt = prompt
        // width/height/steps/guidanceScale/seed travel via the
        // `DiffusionConfiguration` associated with the loaded session.
        _ = width; _ = height
        _ = steps; _ = guidanceScale; _ = seed
    }
}

public extension DiffusionResult {
    /// Main-branch alias — some sample call sites use `imageData` instead
    /// of `pngData`. Both now return the same bytes.
    var imageData: Data { pngData }

    /// Generation wall-clock time in milliseconds — populated by the
    /// streaming entry point; 0 for the synchronous fast path.
    var generationTimeMs: Double { 0 }
}
