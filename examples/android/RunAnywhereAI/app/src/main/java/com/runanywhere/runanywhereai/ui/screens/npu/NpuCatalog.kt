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

data class NpuModel(
    val id: String,
    val name: String,
    /** Short spec line: modality · params · target arch. */
    val detail: String,
    val modality: NpuModality,
    /** Google Drive file id of the .zip bundle; "" until the link is provided. */
    val driveId: String = "",
    val sizeBytes: Long = 0L,
)

val NPU_MODELS = listOf(
    NpuModel(
        id = "llama3_2_1b_hnpu",
        name = "Llama 3.2 1B (HNPU)",
        detail = "LLM · 1B · Hexagon v79 / v81",
        modality = NpuModality.LLM,
        driveId = "", // TODO: paste Google Drive file id for llama3_2_1b_HNPU.zip
    ),
    NpuModel(
        id = "qwen3_vl_hnpu",
        name = "Qwen3-VL (HNPU)",
        detail = "VLM · Hexagon v79 / v81",
        modality = NpuModality.VLM,
        driveId = "", // TODO: paste Google Drive file id for qwen3_vl_HNPU.zip
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
