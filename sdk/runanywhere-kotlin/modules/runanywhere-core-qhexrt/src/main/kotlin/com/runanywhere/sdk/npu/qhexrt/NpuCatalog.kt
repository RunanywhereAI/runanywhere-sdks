package com.runanywhere.sdk.npu.qhexrt

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.registerModel
import kotlinx.coroutines.cancellation.CancellationException

/**
 * One NPU (QHexRT) bundle = one manifest-pinned hf.co folder ref
 * (`https://huggingface.co/<repo>/<arch>/<manifest>.json`). Public so
 * androidTest instrumentation (NpuModelE2ETest) can look up bundles by id.
 * Apps should use [QHexRT.seedCatalog] rather than constructing entries.
 */
data class NpuBundle(
    val id: String,
    val name: String,
    val category: ModelCategory,
    val arch: String,
    val url: String,
)

/**
 * The 17-bundle NPU (QHexRT) catalog — one manifest-pinned hf.co folder ref
 * per bundle. Commons + the engine-registered QHexRT bundle policy resolve
 * the full file set (sizes, checksums, nested paths, and the repo-root
 * `config.json` when present) from the Hub tree at registration — no file
 * lists in the SDK. Context binaries are arch-exact ([arch] is the Hexagon
 * architecture they were compiled for: v75+), so registration filters to
 * the arch probed on the running device.
 *
 * Kept in lockstep with the Flutter (`runanywhere_qhexrt`) and React Native
 * (`@runanywhere/qhexrt`) packages.
 */
val qhexrtBundles: List<NpuBundle> = listOf(
    NpuBundle("lfm2_5_230m_v79", "LFM2.5 230M (HNPU)", ModelCategory.MODEL_CATEGORY_LANGUAGE, "v79",
        "https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/v79/lfm2-5-230m.json"),
    NpuBundle("lfm2_5_230m_v81", "LFM2.5 230M (HNPU)", ModelCategory.MODEL_CATEGORY_LANGUAGE, "v81",
        "https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/v81/lfm2-5-230m.json"),
    NpuBundle("lfm2_5_350m_v79", "LFM2.5 350M (HNPU)", ModelCategory.MODEL_CATEGORY_LANGUAGE, "v79",
        "https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/v79/lfm2-5-350m-2048.json"),
    NpuBundle("lfm2_5_350m_v81", "LFM2.5 350M (HNPU)", ModelCategory.MODEL_CATEGORY_LANGUAGE, "v81",
        "https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/v81/lfm2-5-350m-2048.json"),
    NpuBundle("qwen3_5_0_8b_v81", "Qwen3.5 0.8B (HNPU)", ModelCategory.MODEL_CATEGORY_LANGUAGE, "v81",
        "https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/v81/qwen3.5-0.8b-1024.json"),
    NpuBundle("qwen3_vl_v79", "Qwen3-VL 2B (HNPU)", ModelCategory.MODEL_CATEGORY_MULTIMODAL, "v79",
        "https://huggingface.co/runanywhere/qwen3_vl_HNPU/v79/qwen3vl-2b-vlm-512.json"),
    NpuBundle("internvl3_5_1b_v79", "InternVL3.5 1B (HNPU)", ModelCategory.MODEL_CATEGORY_MULTIMODAL, "v79",
        "https://huggingface.co/runanywhere/internvl3_5_1b_HNPU/v79/internvl3_5-1b-512.json"),
    NpuBundle("internvl3_5_1b_v81", "InternVL3.5 1B (HNPU)", ModelCategory.MODEL_CATEGORY_MULTIMODAL, "v81",
        "https://huggingface.co/runanywhere/internvl3_5_1b_HNPU/v81/internvl3_5-1b.json"),
    NpuBundle("whisper_base_v79", "Whisper Base (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, "v79",
        "https://huggingface.co/runanywhere/whisper_base_HNPU/v79/whisper-base.json"),
    NpuBundle("whisper_small_v79", "Whisper Small (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, "v79",
        "https://huggingface.co/runanywhere/whisper_small_HNPU/v79/whisper-small.json"),
    NpuBundle("moonshine_tiny_v81", "Moonshine Tiny (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, "v81",
        "https://huggingface.co/runanywhere/moonshine_tiny_HNPU/v81/moonshine-tiny.json"),
    NpuBundle("moonshine_base_v81", "Moonshine Base (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, "v81",
        "https://huggingface.co/runanywhere/moonshine_base_HNPU/v81/moonshine-base.json"),
    NpuBundle("melotts_en_v79", "MeloTTS EN (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, "v79",
        "https://huggingface.co/runanywhere/melotts_en_HNPU/v79/melotts-en.json"),
    NpuBundle("melotts_en_v81", "MeloTTS EN (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, "v81",
        "https://huggingface.co/runanywhere/melotts_en_HNPU/v81/melotts-en.json"),
    NpuBundle("kokoro_en_v81", "Kokoro-82M EN (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, "v81",
        "https://huggingface.co/runanywhere/kokoro_en_HNPU/v81/kokoro-en.json"),
    NpuBundle("kitten_nano_0_8_v81", "Kitten-nano-0.8-fp32 (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, "v81",
        "https://huggingface.co/runanywhere/kitten_nano_0_8_HNPU/v81/kitten_nano08_v81.json"),
    NpuBundle("kitten_mini_0_1_v81", "Kitten-mini-0.1 (HNPU)", ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, "v81",
        "https://huggingface.co/runanywhere/kitten_mini_0_1_HNPU/v81/kitten_mini01_v81.json"),
)

private val logger = SDKLogger("QHexRT")

/**
 * Seed the QHexRT NPU catalog: probe the device NPU, register arch-matching
 * bundles via the SDK's canonical from-url path, then refresh the model
 * registry. Safe to re-run on every cold launch — commons merges runtime
 * fields on re-registration.
 *
 * Does NOT call [QHexRT.register] — the caller must register the backend
 * separately (before or after catalog seeding) so the two concerns stay
 * decoupled: "enable the engine" vs "populate the catalog."
 *
 * On unsupported devices this is a no-op (no bundles match) and returns 0.
 *
 * @return The number of NPU bundles successfully registered.
 */
suspend fun QHexRT.seedCatalog(): Int {
    val npuArch = runCatching {
        probeNpu().takeIf { it.qhexrt_supported }?.arch_name
    }.getOrNull()

    if (npuArch == null) {
        logger.info("QHexRT NPU not supported on this device; skipping NPU catalog seed")
        return 0
    }

    val bundles = qhexrtBundles.filter { it.arch == npuArch }
    var ok = 0
    var fail = 0
    for (bundle in bundles) {
        try {
            RunAnywhere.registerModel(
                id = bundle.id,
                name = bundle.name,
                url = bundle.url,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                modality = bundle.category,
                memoryRequirement = 0L,
            )
            ok++
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            fail++
            logger.error("Failed to register NPU bundle ${bundle.id}: ${e.message}", throwable = e)
        }
    }

    logger.info("QHexRT NPU catalog seeded for arch $npuArch: ok=$ok failed=$fail")
    return ok
}