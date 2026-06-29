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
 * Sources are all header-free (no auth):
 *  - **HF public multi-file** ([hfFiles]) — the canonical host. Bundles live in
 *    the public `runanywhere/<name>_HNPU` repos under `<arch>/<files>`, pulled via
 *    `resolve/main`. The first file MUST be the QHexRT manifest (`*.json`); the
 *    rest are companions (weights, tokenizer, …).
 *  - **Archive** ([NpuModel.archiveUrl] / [NpuModel.driveId]) — a single `.zip`.
 *
 * To add a model: append an [NpuModel] with its `modality`, `arch`, and a source.
 * NOTE: embedding/encoder-only bundles (embeddinggemma, siglip2, lama_dilated)
 * are public on HF too but are intentionally NOT listed here — they have no
 * inference screen. Add them once a corresponding modality/screen exists.
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

/** One file of a multi-file NPU bundle. */
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
     * Multi-file source. When non-empty the row registers a multi-file model and
     * ignores the archive sources; the first file must be the QHexRT manifest.
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

/**
 * `resolve/main` direct-download URLs for files of a public HuggingFace subfolder.
 *
 * Appends the repo-root `config.json` as a trailing companion. That file is the
 * Hub's default "query file" for download counting — fetching it once per model
 * download is what increments the repo's public **downloads** metric. It stays a
 * companion (the arch manifest at index 0 remains the primary model file).
 */
private fun hfFiles(repo: String, arch: String, vararg names: String): List<NpuFile> {
    val base = "https://huggingface.co/$repo/resolve/main"
    return names.map { NpuFile(it, "$base/$arch/$it") } +
        NpuFile("config.json", "$base/config.json")
}

/** The six files that make up the public LFM2.5 230M QHexRT bundle (512-ctx). */
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
    // ---- Public HuggingFace bundle (512-ctx) ----
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

    // ---- Public HuggingFace HNPU bundles ----
    NpuModel(
        id = "lfm2_5_350m_v79",
        name = "LFM2.5 350M (HNPU)",
        detail = "LLM · 350M · Hexagon v79",
        modality = NpuModality.LLM,
        arch = "v79",
        files = hfFiles(
            "runanywhere/lfm2_5_350m_HNPU", "v79",
            "lfm2-5-350m-2048.json",
            "lfm2-5-350m-4k.json",
            "lfm2-5-350m-512s.json",
            "lfm_2048_shared.bin",
            "lfm_512_4k_shared.bin",
            "lfm_embed_f16.bin",
            "lfm_lmh.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "lfm2_5_350m_v81",
        name = "LFM2.5 350M (HNPU)",
        detail = "LLM · 350M · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/lfm2_5_350m_HNPU", "v81",
            "lfm2-5-350m-2048.json",
            "lfm_dec_f16.bin",
            "lfm_embed_f16.bin",
            "lfm_lmh_f16.bin",
            "lfm_pf_f16.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "gemma4_e2b_v79",
        name = "Gemma 4 E2B (HNPU)",
        detail = "LLM · E2B · Hexagon v79",
        modality = NpuModality.LLM,
        arch = "v79",
        files = hfFiles(
            "runanywhere/gemma4_e2b_HNPU", "v79",
            "gemma4-e2b.json",
            "g4v_patch_embed_f32.bin",
            "g4v_pos_table_f32.bin",
            "g4v_proj_w_f32.bin",
            "g4v_rope_inv.bin",
            "gemma4-e2b-vlm.json",
            "gemma4_dec_wqo_o3.bin",
            "gemma4_embed_f16.bin",
            "gemma4_fnorm.bin",
            "gemma4_lmhead_f16_o3.bin",
            "gemma4_ple_norm_f16.bin",
            "gemma4_ple_projw_f16.bin",
            "gemma4_ple_table_f16.bin",
            "gemma4_rope_inv_f.bin",
            "gemma4_rope_inv_s.bin",
            "gemma4_vis_16blk_r2_o3.bin",
            "gemma4_vlayer0_i8.bin",
            "gemma4_vlayer10_i8.bin",
            "gemma4_vlayer11_i8.bin",
            "gemma4_vlayer12_i8.bin",
            "gemma4_vlayer13_i8.bin",
            "gemma4_vlayer14_i8.bin",
            "gemma4_vlayer15_i8.bin",
            "gemma4_vlayer16_i8.bin",
            "gemma4_vlayer17_i8.bin",
            "gemma4_vlayer18_i8.bin",
            "gemma4_vlayer19_i8.bin",
            "gemma4_vlayer1_i8.bin",
            "gemma4_vlayer20_i8.bin",
            "gemma4_vlayer21_i8.bin",
            "gemma4_vlayer22_i8.bin",
            "gemma4_vlayer23_i8.bin",
            "gemma4_vlayer24_i8.bin",
            "gemma4_vlayer25_i8.bin",
            "gemma4_vlayer26_i8.bin",
            "gemma4_vlayer27_i8.bin",
            "gemma4_vlayer28_i8.bin",
            "gemma4_vlayer29_i8.bin",
            "gemma4_vlayer2_i8.bin",
            "gemma4_vlayer30_i8.bin",
            "gemma4_vlayer31_i8.bin",
            "gemma4_vlayer32_i8.bin",
            "gemma4_vlayer33_i8.bin",
            "gemma4_vlayer34_i8.bin",
            "gemma4_vlayer3_i8.bin",
            "gemma4_vlayer4_i8.bin",
            "gemma4_vlayer5_i8.bin",
            "gemma4_vlayer6_i8.bin",
            "gemma4_vlayer7_i8.bin",
            "gemma4_vlayer8_i8.bin",
            "gemma4_vlayer9_i8.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "gemma4_e2b_v81",
        name = "Gemma 4 E2B (HNPU)",
        detail = "LLM · E2B · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/gemma4_e2b_HNPU", "v81",
            "gemma4-e2b.json",
            "audio_fix/M.bin",
            "audio_fix/enc_feat.bin",
            "audio_fix/ridx.bin",
            "audio_host/embed_audio_proj.bin",
            "audio_host/mel_filters.bin",
            "audio_host/sub_input_proj_linear_weight.bin",
            "audio_host/sub_layer0_conv_weight.bin",
            "audio_host/sub_layer0_norm_weight.bin",
            "audio_host/sub_layer1_conv_weight.bin",
            "audio_host/sub_layer1_norm_weight.bin",
            "g4v_patch_embed_f32.bin",
            "g4v_pos_table_f32.bin",
            "g4v_proj_w_f32.bin",
            "g4v_rope_inv.bin",
            "gemma4-e2b-audio-hostlm.json",
            "gemma4-e2b-audio.json",
            "gemma4-e2b-vlm.json",
            "gemma4_audio_enc_f16.bin",
            "gemma4_dec_i8.bin",
            "gemma4_embed_f16.bin",
            "gemma4_lmhead_f16.bin",
            "gemma4_ple_norm_f16.bin",
            "gemma4_ple_projw_f16.bin",
            "gemma4_ple_table_f16.bin",
            "gemma4_rope_inv_f.bin",
            "gemma4_rope_inv_s.bin",
            "gemma4_vis_16blk_r2_f16.bin",
            "test.jpg",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "phi_tiny_moe_v79",
        name = "Phi Tiny MoE (HNPU)",
        detail = "LLM · MoE · Hexagon v79",
        modality = NpuModality.LLM,
        arch = "v79",
        files = hfFiles(
            "runanywhere/phi_tiny_moe_HNPU", "v79",
            "phimoe.json",
            "a_hi.bin",
            "a_lo.bin",
            "embed_f16.bin",
            "experts_i8.bin",
            "experts_scale.f32",
            "ffn2.bin",
            "ffn_pf.bin",
            "lmhead_ar1.bin",
            "pf_hi.bin",
            "pf_lo.bin",
            "special_tokens_map.json",
            "tokenizer.json",
            "tokenizer_config.json",
        ),
    ),
    NpuModel(
        id = "phi_tiny_moe_v81",
        name = "Phi Tiny MoE (HNPU)",
        detail = "LLM · MoE · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/phi_tiny_moe_HNPU", "v81",
            "phimoe.json",
            "a_hi.bin",
            "a_lo.bin",
            "embed_f16.bin",
            "experts_i8.bin",
            "experts_scale.f32",
            "ffn2.bin",
            "lmhead_ar1.bin",
            "special_tokens_map.json",
            "tokenizer.json",
            "tokenizer_config.json",
        ),
    ),
    NpuModel(
        id = "qwen3_5_0_8b_v81",
        name = "Qwen3.5 0.8B (HNPU)",
        detail = "LLM · 0.8B · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/qwen3_5_0_8b_HNPU", "v81",
            "qwen3.5-0.8b-1024.json",
            "qwen3508b_decode_f16.bin",
            "qwen3508b_embed_f16.bin",
            "qwen3508b_lmhead_f16.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "qwen3_5_2b_v81",
        name = "Qwen3.5 2B (HNPU)",
        detail = "LLM · 2B · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/qwen3_5_2b_HNPU", "v81",
            "qwen3.5-2b-1024.json",
            "qwen352b_decode_f16.bin",
            "qwen352b_embed_f16.bin",
            "qwen352b_lmhead_f16.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "qwen3_5_4b_v81",
        name = "Qwen3.5 4B (HNPU)",
        detail = "LLM · 4B · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/qwen3_5_4b_HNPU", "v81",
            "qwen3.5-4b-1024.json",
            "qwen354b_decode_s0_w8.bin",
            "qwen354b_decode_s1_w8.bin",
            "qwen354b_embed_f16.bin",
            "qwen354b_lmhead_f16.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "deepseek_r1_distill_qwen_1_5b_v81",
        name = "DeepSeek R1 Distill Qwen 1.5B (HNPU)",
        detail = "LLM · 1.5B · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/deepseek_r1_distill_qwen_1_5b_HNPU", "v81",
            "DeepSeek-R1-Distill-Qwen-1.5B.json",
            "deepseekr1distillqwen15b_decode_f16.bin",
            "deepseekr1distillqwen15b_embed_f16.bin",
            "deepseekr1distillqwen15b_lmhead_f16.bin",
            "deepseekr1distillqwen15b_prefill_f16.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "deepseek_r1_distill_qwen_7b_v81",
        name = "DeepSeek R1 Distill Qwen 7B (HNPU)",
        detail = "LLM · 7B · Hexagon v81",
        modality = NpuModality.LLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/deepseek_r1_distill_qwen_7b_HNPU", "v81",
            "DeepSeek-R1-Distill-Qwen-7B.json",
            "deepseekr1distillqwen7b_decode_p0_w8.bin",
            "deepseekr1distillqwen7b_decode_p1_w8.bin",
            "deepseekr1distillqwen7b_decode_p2_w8.bin",
            "deepseekr1distillqwen7b_decode_p3_w8.bin",
            "deepseekr1distillqwen7b_decode_p4_w8.bin",
            "deepseekr1distillqwen7b_embed_f16.bin",
            "deepseekr1distillqwen7b_lmhead_w8.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "qwen3_vl_v79",
        name = "Qwen3-VL 2B (HNPU)",
        detail = "VLM · 2B · Hexagon v79",
        modality = NpuModality.VLM,
        arch = "v79",
        files = hfFiles(
            "runanywhere/qwen3_vl_HNPU", "v79",
            "qwen3vl-2b-vlm-512.json",
            "embed_f16.bin",
            "llm_shared_512.bin",
            "lmhead_wqo.bin",
            "qwen3vl-2b-text-512.json",
            "tokenizer.json",
            "vis_native_512.bin",
            "vis_patch_embed_bias_f32.bin",
            "vis_patch_embed_f32.bin",
            "vis_pos_embed_f32.bin",
        ),
    ),
    NpuModel(
        id = "internvl3_5_1b_v79",
        name = "InternVL3.5 1B (HNPU)",
        detail = "VLM · 1B · Hexagon v79",
        modality = NpuModality.VLM,
        arch = "v79",
        files = hfFiles(
            "runanywhere/internvl3_5_1b_HNPU", "v79",
            "internvl3_5-1b-512.json",
            "ivl_dec_w4.bin",
            "ivl_embed_f16.bin",
            "ivl_enc2.bin",
            "ivl_lmh_q.bin",
            "ivl_pf_512.bin",
            "tokenizer.json",
            "vlm/pe_b.bin",
            "vlm/pe_cls.bin",
            "vlm/pe_pos.bin",
            "vlm/pe_w.bin",
            "vlm/proj_b1.bin",
            "vlm/proj_b2.bin",
            "vlm/proj_lnb.bin",
            "vlm/proj_lnw.bin",
            "vlm/proj_w1.bin",
            "vlm/proj_w2.bin",
            "vlm/prompt_post.txt",
            "vlm/prompt_pre.txt",
        ),
    ),
    NpuModel(
        id = "internvl3_5_1b_v81",
        name = "InternVL3.5 1B (HNPU)",
        detail = "VLM · 1B · Hexagon v81",
        modality = NpuModality.VLM,
        arch = "v81",
        files = hfFiles(
            "runanywhere/internvl3_5_1b_HNPU", "v81",
            "internvl3_5-1b.json",
            "ivl_dec_f16.bin",
            "ivl_embed_f16.bin",
            "ivl_enc_f16.bin",
            "ivl_lmh_f16.bin",
            "ivl_pf_f16.bin",
            "tokenizer.json",
            "vlm/pe_b.bin",
            "vlm/pe_cls.bin",
            "vlm/pe_pos.bin",
            "vlm/pe_w.bin",
            "vlm/proj_b1.bin",
            "vlm/proj_b2.bin",
            "vlm/proj_lnb.bin",
            "vlm/proj_lnw.bin",
            "vlm/proj_w1.bin",
            "vlm/proj_w2.bin",
            "vlm/prompt_post.txt",
            "vlm/prompt_pre.txt",
        ),
    ),
    NpuModel(
        id = "whisper_base_v79",
        name = "Whisper Base (HNPU)",
        detail = "STT · Base · Hexagon v79",
        modality = NpuModality.STT,
        arch = "v79",
        files = hfFiles(
            "runanywhere/whisper_base_HNPU", "v79",
            "whisper-base.json",
            "decoder.bin",
            "encoder.bin",
            "tokenizer.json",
            "whisper_base_mel_filters.bin",
        ),
    ),
    NpuModel(
        id = "whisper_small_v79",
        name = "Whisper Small (HNPU)",
        detail = "STT · Small · Hexagon v79",
        modality = NpuModality.STT,
        arch = "v79",
        files = hfFiles(
            "runanywhere/whisper_small_HNPU", "v79",
            "whisper-small.json",
            "decoder.bin",
            "encoder.bin",
            "tokenizer.json",
            "whisper_mel_filters.bin",
        ),
    ),
    NpuModel(
        id = "moonshine_tiny_v81",
        name = "Moonshine Tiny (HNPU)",
        detail = "STT · Tiny · Hexagon v81",
        modality = NpuModality.STT,
        arch = "v81",
        files = hfFiles(
            "runanywhere/moonshine_tiny_HNPU", "v81",
            "moonshine-tiny.json",
            "moonshine_conv_stem.bin",
            "moonshinetiny_dec_f16.bin",
            "moonshinetiny_enc_f16.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "moonshine_base_v81",
        name = "Moonshine Base (HNPU)",
        detail = "STT · Base · Hexagon v81",
        modality = NpuModality.STT,
        arch = "v81",
        files = hfFiles(
            "runanywhere/moonshine_base_HNPU", "v81",
            "moonshine-base.json",
            "moonshine_conv_stem.bin",
            "moonshinebase_dec_f16.bin",
            "moonshinebase_enc_f16.bin",
            "tokenizer.json",
        ),
    ),
    NpuModel(
        id = "melotts_en_v79",
        name = "MeloTTS EN (HNPU)",
        detail = "TTS · EN · Hexagon v79",
        modality = NpuModality.TTS,
        arch = "v79",
        files = hfFiles(
            "runanywhere/melotts_en_HNPU", "v79",
            "melotts-en.json",
            "melo_decoder.bin",
            "melo_encoder.bin",
            "melo_flow.bin",
            "melo_lexicon.txt",
            "melo_tokens.txt",
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
