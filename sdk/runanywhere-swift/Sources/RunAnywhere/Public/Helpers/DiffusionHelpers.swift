//
//  DiffusionHelpers.swift
//  RunAnywhere SDK
//
//  SDK-unique helper types for Diffusion that are NOT covered by any proto
//  schema in `idl/diffusion_options.proto`. Per CANONICAL_API §8 / §15:
//    - Proto-overlapping types (DiffusionConfig/Options/Result/Progress/
//      Scheduler/Mode) live in `Generated/diffusion_options.pb.swift` as
//      `RADiffusionConfiguration`, `RADiffusionGenerationOptions`,
//      `RADiffusionResult`, `RADiffusionProgress`, `RADiffusionScheduler`,
//      `RADiffusionMode`.
//    - Pre-IDL fields the proto deliberately drops (input_image,
//      mask_image, denoise_strength, report_intermediate_images,
//      progress_stride, reduce_memory) and Apple-specific helpers
//      (toAppleScheduler, defaultResolution/defaultSteps/etc.) live HERE
//      so the public surface stays proto-anchored where possible.
//
//  The hand-rolled wrappers in `DiffusionTypes.swift` are held in place
//  during the v2 cross-SDK parity migration because they expose
//  `toCOptions()` / `init(from cResult:)` C bridge methods consumed by
//  `CppBridge.Diffusion`. Once the bridge is rewritten against the proto
//  types directly, the proto-overlap part of `DiffusionTypes.swift` will
//  be deleted and the helpers below will move into the public root.
//

import Foundation
