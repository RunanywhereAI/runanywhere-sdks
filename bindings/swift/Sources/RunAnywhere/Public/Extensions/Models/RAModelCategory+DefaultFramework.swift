//
//  RAModelCategory+DefaultFramework.swift
//  RunAnywhere SDK
//
//  SDK-owned default-framework lookup per `RAModelCategory`. Example apps
//  previously hand-rolled this fallback (LLM/VLM → llamaCpp; STT/TTS/VAD/
//  embedding → onnx) because the SDK did not surface the implicit assignment
//  the C++ backends already encode. The mapping is owned by commons
//  (`rac_model_category_default_framework`) so every SDK shares one source of
//  truth and example view-models stay free of modality→framework fallbacks.
//

import CRACommons
import Foundation

public extension RAModelCategory {

    /// The framework the SDK falls back to when a category has no explicit
    /// `RAModelInfo.framework` resolved (e.g. a pending UI selection that has
    /// not yet matched a catalogued model). Delegates to
    /// `rac_model_category_default_framework`.
    var defaultFramework: InferenceFramework {
        RAInferenceFramework.fromCFramework(rac_model_category_default_framework(self.toC()))
    }
}
