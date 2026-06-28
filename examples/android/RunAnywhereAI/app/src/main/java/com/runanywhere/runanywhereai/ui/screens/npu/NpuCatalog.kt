package com.runanywhere.runanywhereai.ui.screens.npu

import ai.runanywhere.proto.v1.ModelCategory

/**
 * NPU (QHexRT) model catalog.
 *
 * Every entry is tagged with both a [NpuModality] (which inference screen it
 * belongs to) and an [NpuModel.arch] (the Hexagon architecture its context
 * binaries were compiled for — `v75` / `v79` / `v81`). The NPU section filters
 * this list to the modality of the open screen *and* the architecture probed on
 * the running device, so a v81 phone only ever sees v81 bundles, etc. QHexRT
 * context binaries are arch-exact, so loading a mismatched bundle would fail.
 *
 * Two source shapes are supported, both header-free (no auth):
 *  - **Archive**: a single `.zip` bundle, addressed either by a direct
 *    [NpuModel.archiveUrl] (S3 / any CDN) or a Google Drive file id
 *    ([NpuModel.driveId]). The SDK downloads + extracts it.
 *  - **Multi-file**: a list of individual [NpuFile]s (e.g. a HuggingFace repo
 *    subfolder of `.json` / `.bin` files). The first file must be the QHexRT
 *    manifest (`*.json`).
 *
 * To add a model: append an [NpuModel] with its `modality`, `arch`, and one of
 * the two sources. Wiring an upcoming S3/Drive bundle is a one-liner — see the
 * placeholder block at the bottom of [NPU_MODELS].
 */
enum class NpuModality { LLM, VLM, STT, TTS }

/** Human-readable section title for a modality. */
val NpuModality.label: String
    get() = when (this) {
        NpuModality.LLM -> "Chat"
        NpuModality.VLM -> "Vision"
        NpuModality.STT -> "Speech to Text"
        NpuModality.TTS -> "Text to Speech"
    }

/** Proto model category backing a given NPU modality. */
fun NpuModality.category(): ModelCategory = when (this) {
    NpuModality.LLM -> ModelCategory.MODEL_CATEGORY_LANGUAGE
    NpuModality.VLM -> ModelCategory.MODEL_CATEGORY_MULTIMODAL
    NpuModality.STT -> ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
    NpuModality.TTS -> ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
}

/** One file of a multi-file (e.g. HuggingFace-hosted) NPU bundle. */
data class NpuFile(val filename: String, val url: String)

data class NpuModel(
    val id: String,
    val name: String,
    /** Short spec line: modality · params · target arch. */
    val detail: String,
    val modality: NpuModality,
    /** Hexagon architecture this bundle is compiled for: "v75" / "v79" / "v81". */
    val arch: String,
    /** Direct `.zip` archive URL (S3 / any CDN). Takes priority over [driveId]. */
    val archiveUrl: String = "",
    /** Google Drive file id of the `.zip` bundle; "" when no Drive source. */
    val driveId: String = "",
    /**
     * Multi-file source (e.g. a HuggingFace bundle of individual `.json`/`.bin`
     * files). When non-empty the row registers a multi-file model and ignores
     * the archive sources; the first file must be the QHexRT manifest (`*.json`).
     */
    val files: List<NpuFile> = emptyList(),
    val sizeBytes: Long = 0L,
) {
    /** True when this entry has a usable download source wired in. */
    val hasSource: Boolean
        get() = files.isNotEmpty() || archiveUrl.isNotBlank() || driveId.isNotBlank()

    /** Resolved archive URL for non-multi-file models ("" for multi-file models). */
    val resolvedArchiveUrl: String
        get() = when {
            files.isNotEmpty() -> ""
            archiveUrl.isNotBlank() -> archiveUrl
            driveId.isNotBlank() -> driveZipUrl(driveId)
            else -> ""
        }
}

/** `resolve/main` direct-download URLs for the files of a HuggingFace repo subfolder. */
private fun hfFiles(repo: String, arch: String, vararg names: String): List<NpuFile> =
    names.map { NpuFile(it, "https://huggingface.co/$repo/resolve/main/$arch/$it") }

/** The six files that make up an LFM2.5 230M QHexRT bundle (512-ctx variant). */
private fun lfm2_5_230mFiles(arch: String): List<NpuFile> = hfFiles(
    "runanywhere/lfm2_5_230m_HNPU", arch,
    "lfm2-5-230m.json",
    "lfm230_pf_512_w8.bin",
    "lfm230_dec_512_w8.bin",
    "lfm230_lmh_w8.bin",
    "lfm_embed_f16.bin",
    "tokenizer.json",
)

val NPU_MODELS = listOf(
    // ---- LLM ----
    NpuModel(
        id = "llama3_2_1b_v79",
        name = "Llama 3.2 1B (HNPU)",
        detail = "LLM · 1B · Hexagon v79",
        modality = NpuModality.LLM,
        arch = "v79",
        driveId = "1UeEE08KpZU-rFSwf_FRnu1z2KRwImdX5",
    ),
    NpuModel(
        id = "llama3_2_1b_v81",
        name = "Llama 3.2 1B (HNPU)",
        detail = "LLM · 1B · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        driveId = "1mbshG-jO684dCEUjKKcJ7AUJYRU7_oWX",
    ),
    NpuModel(
        id = "lfm2_5_230m_v79",
        name = "LFM2.5 230M (HNPU)",
        detail = "LLM · 230M · Hexagon v79",
        modality = NpuModality.LLM,
        arch = "v79",
        files = lfm2_5_230mFiles("v79"),
    ),
    NpuModel(
        id = "lfm2_5_230m_v81",
        name = "LFM2.5 230M (HNPU)",
        detail = "LLM · 230M · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = lfm2_5_230mFiles("v81"),
    ),

    // ---- VLM ----
    NpuModel(
        id = "qwen3_vl_v79",
        name = "Qwen3-VL (HNPU)",
        detail = "VLM · Hexagon v79",
        modality = NpuModality.VLM,
        arch = "v79",
        driveId = "1Uj1yLliJCJVYuJV0gF_i4Sc_XhBMx1bA",
    ),

    // ---- Upcoming S3 / Drive bundles ----
    // Wiring each is a one-liner: set `arch` to the device target and provide a
    // source (archiveUrl for S3, driveId for Drive, or files for a HF subfolder).
    // STT and TTS rows appear on their screens automatically once added, e.g.:
    //
    // NpuModel(
    //     id = "whisper_base_v81", name = "Whisper Base (HNPU)",
    //     detail = "STT · Hexagon v81", modality = NpuModality.STT, arch = "v81",
    //     archiveUrl = "https://<your-bucket>.s3.amazonaws.com/whisper_base_v81.zip",
    // ),
    // NpuModel(
    //     id = "melotts_v81", name = "MeloTTS (HNPU)",
    //     detail = "TTS · Hexagon v81", modality = NpuModality.TTS, arch = "v81",
    //     archiveUrl = "https://<your-bucket>.s3.amazonaws.com/melotts_v81.zip",
    // ),
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
