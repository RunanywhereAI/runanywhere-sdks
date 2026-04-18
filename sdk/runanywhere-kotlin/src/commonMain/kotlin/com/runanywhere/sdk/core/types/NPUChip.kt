package com.runanywhere.sdk.core.types

/**
 * Supported NPU chipsets for on-device Genie model inference.
 *
 * Each chip has an [identifier] used in model IDs and an [npuSuffix] used
 * to construct download URLs from the HuggingFace model repository.
 *
 * Example URL construction:
 * ```
 * val chip = RunAnywhere.getChip()
 * val url = chip.downloadUrl("qwen3-4b")
 * // → "https://huggingface.co/runanywhere/genie-npu-models/resolve/main/qwen3-4b-genie-w4a16-8elite-gen5.tar.gz"
 * ```
 */
enum class NPUChip(
    val identifier: String,
    val displayName: String,
    val socModel: String,
    val npuSuffix: String,
) {
    SNAPDRAGON_8_ELITE("8elite", "Snapdragon 8 Elite", "SM8750", "8elite"),
    SNAPDRAGON_8_ELITE_GEN5("8elite-gen5", "Snapdragon 8 Elite Gen 5", "SM8850", "8elite-gen5"),
    ;

    /**
     * Build a HuggingFace download URL for this chip.
     * @param modelSlug Model slug (e.g. "qwen3-4b") → produces
     *   "qwen3-4b-genie-w4a16-8elite-gen5.tar.gz"
     * @param quant Quantization format (e.g. "w4a16", "w8a16"). Defaults to "w4a16".
     */
    fun downloadUrl(modelSlug: String, quant: String = "w4a16"): String =
        "${BASE_URL}$modelSlug-genie-$quant-$npuSuffix.tar.gz"

    companion object {
        /** Base URL for NPU model downloads on HuggingFace. */
        const val BASE_URL = "https://huggingface.co/runanywhere/genie-npu-models/resolve/main/"

        /**
         * Match an NPU chip from a SoC model string (e.g. "SM8750").
         * Returns null if the SoC is not a supported NPU chipset.
         */
        fun fromSocModel(socModel: String): NPUChip? {
            val upper = socModel.uppercase()
            return entries.firstOrNull { upper.contains(it.socModel) }
        }
    }
}
