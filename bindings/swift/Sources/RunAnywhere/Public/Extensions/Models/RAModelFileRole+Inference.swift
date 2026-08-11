//
//  RAModelFileRole+Inference.swift
//  RunAnywhere SDK
//
//  Public filename → role inference helper. Mirrors commons
//  `model_paths.cpp::infer_file_role` so example apps composing
//  multi-file model descriptors do not need to hand-roll their own
//  mmproj / tokenizer / vocab heuristics.
//

import Foundation

public extension RunAnywhere {

    /// Infer the canonical `RAModelFileRole` for a single sidecar filename
    /// in a multi-file model. The classification matches commons
    /// `infer_file_role(path, format)` so the SDK and the C++ model-paths
    /// resolver always agree on which file is the primary model, the vision
    /// projector (`mmproj`), tokenizer, vocabulary, etc.
    ///
    /// - Parameters:
    ///   - filename: The sidecar's filename (case-insensitive matching;
    ///     directory components are ignored).
    ///   - modality: The model's `ModelCategory`. Only `.multimodal` enables
    ///     the `mmproj` / vision-projector match path; other modalities
    ///     never resolve to `.visionProjector`.
    /// - Returns: The matching `RAModelFileRole`, or `.primaryModel` when
    ///   the filename does not match any of the documented sidecar
    ///   conventions.
    static func inferModelFileRole(
        filename: String,
        modality: ModelCategory
    ) -> RAModelFileRole {
        CppBridge.ModelPaths.inferFileRole(filename: filename, modality: modality)
    }
}
