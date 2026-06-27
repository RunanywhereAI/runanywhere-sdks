package com.runanywhere.runanywhereai.ui.screens.npu

/**
 * NPU (QHexRT) model catalog — Google-Drive-hosted ZIP bundles.
 *
 * Each model is a .zip archive on Google Drive. The Models screen registers it
 * as a ZIP archive (DIRECTORY_BASED) and the SDK downloads + extracts it into
 * the standard model dir, then loads it like any other model.
 *
 * To wire a model: paste its Google Drive FILE ID into [NpuModel.driveId] (the
 * long id from the share link `https://drive.google.com/file/d/<FILE_ID>/view`).
 * An empty driveId renders the row as "Link pending" with Download disabled.
 */
enum class NpuModality { LLM, VLM }

/** One file of a multi-file (e.g. HuggingFace-hosted) NPU bundle. */
data class NpuFile(val filename: String, val url: String)

data class NpuModel(
    val id: String,
    val name: String,
    /** Short spec line: modality · params · target arch. */
    val detail: String,
    val modality: NpuModality,
    /** Google Drive file id of the .zip bundle; "" until the link is provided. */
    val driveId: String = "",
    /**
     * Multi-file source (e.g. a HuggingFace bundle of individual `.json`/`.bin`
     * files). When non-empty the row registers a multi-file model and ignores
     * [driveId]; the first file must be the QHexRT manifest (`*.json`).
     */
    val files: List<NpuFile> = emptyList(),
    val sizeBytes: Long = 0L,
)

/** `resolve/main` direct-download URLs for the files of a HuggingFace repo subfolder. */
private fun hfFiles(repo: String, arch: String, vararg names: String): List<NpuFile> =
    names.map { NpuFile(it, "https://huggingface.co/$repo/resolve/main/$arch/$it") }

val NPU_MODELS = listOf(
    NpuModel(
        id = "llama3_2_1b_v79",
        name = "Llama 3.2 1B (HNPU)",
        detail = "LLM · 1B · Hexagon v79",
        modality = NpuModality.LLM,
        driveId = "1UeEE08KpZU-rFSwf_FRnu1z2KRwImdX5",
    ),
    NpuModel(
        id = "llama3_2_1b_v81",
        name = "Llama 3.2 1B (HNPU)",
        detail = "LLM · 1B · Hexagon v81",
        modality = NpuModality.LLM,
        driveId = "1mbshG-jO684dCEUjKKcJ7AUJYRU7_oWX",
    ),
    NpuModel(
        id = "qwen3_vl_v79",
        name = "Qwen3-VL (HNPU)",
        detail = "VLM · Hexagon v79",
        modality = NpuModality.VLM,
        driveId = "1Uj1yLliJCJVYuJV0gF_i4Sc_XhBMx1bA",
    ),
    // HuggingFace-hosted multi-file bundle (no archive) — used to sanity-check
    // that gibberish output is model-specific, not an integration bug. Manifest
    // (`lfm2-5-230m.json`) must come first so it registers as the primary file.
    NpuModel(
        id = "lfm2_5_230m_v81",
        name = "LFM2.5 230M (HNPU)",
        detail = "LLM · 230M · Hexagon v81",
        modality = NpuModality.LLM,
        files = hfFiles(
            "runanywhere/lfm2_5_230m_HNPU", "v81",
            "lfm2-5-230m.json",
            "lfm230_pf_512_w8.bin",
            "lfm230_dec_512_w8.bin",
            "lfm230_lmh_w8.bin",
            "lfm_embed_f16.bin",
            "tokenizer.json",
        ),
    ),
)

/**
 * Direct-download URL for a Google Drive file id. Uses the usercontent host
 * with `confirm=t` so large files skip the virus-scan HTML interstitial and
 * stream the bytes.
 */
fun driveZipUrl(driveId: String): String =
    "https://drive.usercontent.google.com/download?id=$driveId&export=download&confirm=t"

fun formatNpuBytes(bytes: Long): String {
    if (bytes >= 1_000_000_000) return "%.1f GB".format(bytes / 1e9)
    if (bytes >= 1_000_000) return "%.0f MB".format(bytes / 1e6)
    return "$bytes B"
}
