package com.runanywhere.sdk.core.types

/**
 * Supported NPU chipsets for on-device Genie model inference.
 *
 * Each chip has an [identifier] used to construct dynamic download URLs
 * for chipset-specific NPU model binaries.
 *
 * Example URL construction:
 * ```
 * val chip = RunAnywhere.getChip()
 * val url = "${NPUChip.BASE_URL}qwen-${chip.identifier}.zip?download=true"
 * ```
 */
enum class NPUChip(
    val identifier: String,
    val displayName: String,
    val socModel: String,
) {
    SNAPDRAGON_8_ELITE("gen1", "Snapdragon 8 Elite", "SM8750"),
    SNAPDRAGON_8_ELITE_GEN5("gen2", "Snapdragon 8 Elite Gen 5", "SM8850"),
    ;

    /**
     * Build a HuggingFace download URL for this chip.
     * @param modelName Model prefix (e.g. "qwen") → produces "qwen-gen1.zip"
     */
    fun downloadUrl(modelName: String): String =
        "${BASE_URL}${modelName}-${identifier}.zip?download=true"

    companion object {
        /** Base URL for NPU model downloads on HuggingFace. */
        const val BASE_URL = "https://huggingface.co/Void2377/npu-models/resolve/main/"

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
