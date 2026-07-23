/**
 * Curated QHexRT NPU catalog — one manifest-pinned hf.co folder ref per
 * bundle (`https://huggingface.co/<repo>/<arch>/<manifest>.json`). Commons
 * + the engine-registered QHexRT bundle policy resolve the full file set
 * (sizes, checksums, nested paths) from the Hub tree at registration — no
 * file lists in the SDK. Context binaries are arch-exact (`arch` is the
 * Hexagon architecture they were compiled for: v75+), so registration
 * filters to the arch probed on the running device.
 *
 * Kept in lockstep with the Kotlin (`runanywhere-core-qhexrt`) and Flutter
 * (`runanywhere_qhexrt`) SDK packages.
 */

import { RunAnywhere } from '@runanywhere/core';
import { SDKLogger } from '@runanywhere/core/internal';
import {
    ModelCategory,
    InferenceFramework,
} from '@runanywhere/proto-ts/model_types';

const logger = new SDKLogger('QHexRT');

/**
 * One QHexRT NPU bundle reference: an HF folder-bundle URL pinned to the
 * bundle's manifest (`huggingface.co/<repo>/<arch>/<manifest>.json`).
 */
type NpuRef = {
    id: string;
    name: string;
    modality: ModelCategory;
    /** Hexagon architecture the context binaries were compiled for. */
    arch: string;
    url: string;
};

const NPU_REFS: NpuRef[] = [
    {
        id: 'lfm2_5_230m_v79',
        name: 'LFM2.5 230M (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
        arch: 'v79',
        url: 'https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/v79/lfm2-5-230m.json',
    },
    {
        id: 'lfm2_5_230m_v81',
        name: 'LFM2.5 230M (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/v81/lfm2-5-230m.json',
    },
    {
        id: 'lfm2_5_350m_v79',
        name: 'LFM2.5 350M (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
        arch: 'v79',
        url: 'https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/v79/lfm2-5-350m-2048.json',
    },
    {
        id: 'lfm2_5_350m_v81',
        name: 'LFM2.5 350M (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/v81/lfm2-5-350m-2048.json',
    },
    {
        id: 'qwen3_5_0_8b_v81',
        name: 'Qwen3.5 0.8B (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/v81/qwen3.5-0.8b-1024.json',
    },
    {
        id: 'qwen3_vl_v79',
        name: 'Qwen3-VL 2B (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        arch: 'v79',
        url: 'https://huggingface.co/runanywhere/qwen3_vl_HNPU/v79/qwen3vl-2b-vlm-512.json',
    },
    {
        id: 'internvl3_5_1b_v79',
        name: 'InternVL3.5 1B (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        arch: 'v79',
        url: 'https://huggingface.co/runanywhere/internvl3_5_1b_HNPU/v79/internvl3_5-1b-512.json',
    },
    {
        id: 'internvl3_5_1b_v81',
        name: 'InternVL3.5 1B (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/internvl3_5_1b_HNPU/v81/internvl3_5-1b.json',
    },
    {
        id: 'whisper_base_v79',
        name: 'Whisper Base (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        arch: 'v79',
        url: 'https://huggingface.co/runanywhere/whisper_base_HNPU/v79/whisper-base.json',
    },
    {
        id: 'whisper_small_v79',
        name: 'Whisper Small (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        arch: 'v79',
        url: 'https://huggingface.co/runanywhere/whisper_small_HNPU/v79/whisper-small.json',
    },
    {
        id: 'moonshine_tiny_v81',
        name: 'Moonshine Tiny (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/moonshine_tiny_HNPU/v81/moonshine-tiny.json',
    },
    {
        id: 'moonshine_base_v81',
        name: 'Moonshine Base (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/moonshine_base_HNPU/v81/moonshine-base.json',
    },
    {
        id: 'melotts_en_v79',
        name: 'MeloTTS EN (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        arch: 'v79',
        url: 'https://huggingface.co/runanywhere/melotts_en_HNPU/v79/melotts-en.json',
    },
    {
        id: 'melotts_en_v81',
        name: 'MeloTTS EN (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/melotts_en_HNPU/v81/melotts-en.json',
    },
    {
        id: 'kokoro_en_v81',
        name: 'Kokoro-82M EN (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/kokoro_en_HNPU/v81/kokoro-en.json',
    },
    {
        id: 'kitten_nano_0_8_v81',
        name: 'Kitten-nano-0.8-fp32 (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/kitten_nano_0_8_HNPU/v81/kitten_nano08_v81.json',
    },
    {
        id: 'kitten_mini_0_1_v81',
        name: 'Kitten-mini-0.1 (HNPU)',
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        arch: 'v81',
        url: 'https://huggingface.co/runanywhere/kitten_mini_0_1_HNPU/v81/kitten_mini01_v81.json',
    },
];

/**
 * Seed the QHexRT NPU catalog: probe the device NPU, register arch-matching
 * bundles via the SDK's canonical from-url path, then refresh the model
 * registry. Safe to re-run on every cold launch — commons merges runtime
 * fields on re-registration.
 *
 * Does NOT call `QHexRT.register()` — the caller must register the backend
 * separately (before or after catalog seeding) so the two concerns stay
 * decoupled: "enable the engine" vs "populate the catalog."
 *
 * On unsupported devices this is a no-op (no bundles match) and returns 0.
 *
 * @param probeNpu - A function that returns the NPU capability (allows
 *   callers to cache the probe result from the app startup flow).
 * @returns The number of NPU bundles successfully registered.
 */
export async function seedNpuCatalog(
    probeNpu: () => Promise<{ archName: string; qhexrtSupported: boolean }>
): Promise<number> {
    let npu: { archName: string; qhexrtSupported: boolean };
    try {
        npu = await probeNpu();
    } catch {
        logger.debug('NPU probe failed; skipping NPU catalog seed');
        return 0;
    }

    if (!npu.qhexrtSupported) {
        logger.debug('NPU not supported on this device; skipping NPU catalog seed');
        return 0;
    }

    const arch = npu.archName;
    const refs = NPU_REFS.filter((r) => r.arch === arch);
    let count = 0;
    for (const r of refs) {
        try {
            await RunAnywhere.registerModel({
                id: r.id,
                name: r.name,
                url: r.url,
                framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                modality: r.modality,
            });
            count++;
        } catch (error) {
            logger.debug(`Failed to register NPU bundle ${r.id}: ${String(error)}`);
        }
    }

    logger.debug(`NPU bundles registered for ${arch}: ${count}`);
    return count;
}
