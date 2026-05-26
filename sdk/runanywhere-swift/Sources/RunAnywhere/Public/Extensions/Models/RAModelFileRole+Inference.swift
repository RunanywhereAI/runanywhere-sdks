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
        let lower = (filename as NSString).lastPathComponent.lowercased()

        if modality == .multimodal,
           lower.hasSuffix(".gguf"),
           lower.contains("mmproj")
             || lower.contains("mm-proj")
             || lower.contains("vision-projector")
             || lower.contains("vision_projector")
             || lower.contains("multimodal_projector")
             || lower.contains("multi-modal-projector") {
            return .visionProjector
        }

        switch lower {
        case "tokenizer.json", "tokenizer.model", "tokenizer_config.json",
             "special_tokens_map.json", "added_tokens.json", "tokens.txt",
             "sentencepiece.bpe.model", "spm.model":
            return .tokenizer
        case "vocab.txt", "vocab.json":
            return .vocabulary
        case "merges.txt":
            return .merges
        case "config.json", "generation_config.json", "preprocessor_config.json",
             "processor_config.json", "image_processor_config.json",
             "model_config.json":
            return .config
        default:
            return .primaryModel
        }
    }
}
