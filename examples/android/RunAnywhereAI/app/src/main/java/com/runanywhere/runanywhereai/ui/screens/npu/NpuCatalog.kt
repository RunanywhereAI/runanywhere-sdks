package com.runanywhere.runanywhereai.ui.screens.npu

/**
 * Curated NPU (QHexRT) model catalog.
 *
 * Source of truth: the npu-tagged repo `runanywhere/genie-npu-models` on
 * Hugging Face (tags: qualcomm, genie, npu, snapdragon) — Snapdragon Hexagon
 * NPU LLM bundles (w4a16/w8a16, Snapdragon 8 Elite / 8 Elite Gen5). The NPU
 * Models screen lists exactly these, not the generic SDK registry.
 */
private const val HF = "https://huggingface.co/runanywhere/genie-npu-models/resolve/main"

data class NpuModel(
    val id: String,
    val name: String,
    /** Short spec line: params · quant · target SoC. */
    val detail: String,
    val sizeBytes: Long,
    val url: String,
)

val NPU_MODELS = listOf(
    NpuModel(
        "llama3.2-1b-instruct-genie-w4a16-8elite-gen5", "Llama 3.2 1B Instruct",
        "1B · w4a16 · 8 Elite Gen5", 1_373_507_483,
        "$HF/llama3.2-1b-instruct-genie-w4a16-8elite-gen5.tar.gz",
    ),
    NpuModel(
        "llama3.2-1b-instruct-genie-w4a16-8elite", "Llama 3.2 1B Instruct",
        "1B · w4a16 · 8 Elite", 1_369_601_674,
        "$HF/llama3.2-1b-instruct-genie-w4a16-8elite.tar.gz",
    ),
    NpuModel(
        "qwen3-4b-genie-w4a16-8elite-gen5", "Qwen3 4B",
        "4B · w4a16 · 8 Elite Gen5", 2_538_981_899,
        "$HF/qwen3-4b-genie-w4a16-8elite-gen5.tar.gz",
    ),
    NpuModel(
        "qwen2.5-7b-instruct-genie-w8a16-8elite", "Qwen2.5 7B Instruct",
        "7B · w8a16 · 8 Elite", 4_184_248_574,
        "$HF/qwen2.5-7b-instruct-genie-w8a16-8elite.tar.gz",
    ),
    NpuModel(
        "sea-lion3.5-8b-instruct-genie-w4a16-8elite-gen5", "SEA-LION 3.5 8B Instruct",
        "8B · w4a16 · 8 Elite Gen5", 4_724_747_321,
        "$HF/sea-lion3.5-8b-instruct-genie-w4a16-8elite-gen5.tar.gz",
    ),
    NpuModel(
        "sea-lion3.5-8b-instruct-genie-w4a16-8elite", "SEA-LION 3.5 8B Instruct",
        "8B · w4a16 · 8 Elite", 4_722_492_367,
        "$HF/sea-lion3.5-8b-instruct-genie-w4a16-8elite.tar.gz",
    ),
)

fun formatNpuBytes(bytes: Long): String {
    if (bytes >= 1_000_000_000) return "%.1f GB".format(bytes / 1e9)
    if (bytes >= 1_000_000) return "%.0f MB".format(bytes / 1e6)
    return "$bytes B"
}
