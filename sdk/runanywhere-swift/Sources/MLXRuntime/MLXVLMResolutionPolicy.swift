import Foundation

/// Minimal reader for the `config.json` fields the MLX runtime needs outside of
/// mlx-swift-lm's own model loading. Decoded with explicit `Decodable` structs
/// (no `[String: Any]`) per repo conventions.
private struct MLXModelConfigDocument: Decodable {
    struct TextConfig: Decodable {
        let maxPositionEmbeddings: Int?
        enum CodingKeys: String, CodingKey {
            case maxPositionEmbeddings = "max_position_embeddings"
        }
    }

    let maxPositionEmbeddings: Int?
    let textConfig: TextConfig?

    enum CodingKeys: String, CodingKey {
        case maxPositionEmbeddings = "max_position_embeddings"
        case textConfig = "text_config"
    }
}

/// Reads model metadata the runtime needs from a model directory's `config.json`.
enum MLXModelConfig {
    /// The model's maximum context length from `config.json`
    /// (`text_config.max_position_embeddings`, falling back to the top-level
    /// field). Returns `0` when unavailable. Qwen3.5-VL / Fara nest it under
    /// `text_config`; single-tower models put it at the top level.
    static func contextLength(inDirectory directory: URL) -> Int {
        let url = directory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(MLXModelConfigDocument.self, from: data) else {
            return 0
        }
        return document.textConfig?.maxPositionEmbeddings
            ?? document.maxPositionEmbeddings
            ?? 0
    }
}

/// Model-aware image-resolution policy for MLX VLM inference.
///
/// The MLX VLM path previously forced every image into a fixed 512×512 square,
/// which both distorts the aspect ratio and destroys the fine detail that
/// screen / document / computer-use-agent (CUA) models must read (Fara then
/// hallucinates from training priors). Conversely, letting a full-resolution
/// image through is not viable: mlx-swift-lm's Qwen3.5-VL vision tower runs
/// non-windowed attention (O(patches²)), so a full 3024×1964 screenshot
/// (~23 000 patches) tries to allocate ~34 GB for a single attention buffer and
/// crashes. (`UserInput.Processing.maxPixels` does NOT help here: the Qwen3.5-VL
/// processor recomputes its own target from `config.size.maxPixels` and ignores
/// the per-request `maxPixels`. Only `resize` — applied before patchification —
/// actually bounds the patch count.)
///
/// This tiers an aspect-preserving `resize` budget by the model's maximum
/// context length — a structured proxy for large-context / CUA VLMs (e.g. Fara
/// at 256K) that are purpose-built to read dense UIs — keeping enough detail to
/// read on-screen text while bounding the patch count (and thus vision-attention
/// memory) for every model.
enum MLXVLMResolutionPolicy {
    /// Total-pixel budget for a VLM image, selected from the model's maximum
    /// context length. Applied via an aspect-preserving `resize` (see
    /// `targetSize(forContextLength:native:)`).
    static func maxPixels(forContextLength contextLength: Int) -> Int {
        switch contextLength {
        case 131_072...:
            // CUA / very-large-context VLMs (e.g. Fara at 256K): ~1.4 MP
            // (≈1468×953 for a 16:10 screen; ~5 500 patches, ~2 GB attention) —
            // enough to read on-screen text and UI affordances.
            return 1_400_000
        case 40_960...:
            // Large-context VLMs: ~1.0 MP (≈1240×806).
            return 1_000_000
        default:
            // Standard VLMs: ~0.7 MP (≈1038×674 / 836² square).
            return 700_000
        }
    }

    /// Aspect-preserving target size for `UserInput.Processing.resize`, bounded
    /// so total pixels ≤ the model's budget. Never upscales. This is the knob
    /// the Qwen3.5-VL processor honors, applied before patchification, so it
    /// deterministically caps the vision-patch count.
    static func targetSize(forContextLength contextLength: Int, native: CGSize) -> CGSize {
        let budget = Double(maxPixels(forContextLength: contextLength))
        let nativeWidth = max(1.0, Double(native.width))
        let nativeHeight = max(1.0, Double(native.height))
        let nativePixels = nativeWidth * nativeHeight
        guard nativePixels > budget else {
            return CGSize(width: nativeWidth, height: nativeHeight)
        }
        let scale = (budget / nativePixels).squareRoot()
        return CGSize(
            width: (nativeWidth * scale).rounded(),
            height: (nativeHeight * scale).rounded()
        )
    }
}
