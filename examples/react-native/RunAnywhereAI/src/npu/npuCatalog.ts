/**
 * NPU (QHexRT) model catalog — public HuggingFace multi-file bundles.
 *
 * Ported from the Android Kotlin source of truth (NpuCatalog.kt). Every entry
 * is tagged with both a {@link NpuModality} (which inference screen it belongs
 * to) and an `arch` (the Hexagon architecture its context binaries were
 * compiled for — "v75" / "v79" / "v81"). The NPU section filters this list to
 * the modality of the open screen *and* the architecture probed on the running
 * device, so a v81 phone only ever sees v81 bundles. QHexRT context binaries
 * are arch-exact, so loading a mismatched bundle would fail.
 *
 * Sources are header-free public HuggingFace repos: bundles live in the
 * `runanywhere/<name>_HNPU` repos under `<arch>/<files>`, pulled via
 * `resolve/main`. The first file MUST be the QHexRT manifest (`*.json`); the
 * rest are companions (weights, tokenizer, …). The repo-root `config.json` is
 * appended as a trailing companion (the Hub's default download-count query
 * file).
 */
import { ModelCategory } from '@runanywhere/proto-ts/model_types';

export type NpuModality = 'llm' | 'vlm' | 'stt' | 'tts';

/** Proto model category backing a given NPU modality. */
export function modalityCategory(modality: NpuModality): ModelCategory {
  switch (modality) {
    case 'vlm':
      return ModelCategory.MODEL_CATEGORY_MULTIMODAL;
    case 'stt':
      return ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;
    case 'tts':
      return ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;
    case 'llm':
    default:
      return ModelCategory.MODEL_CATEGORY_LANGUAGE;
  }
}

/** Human-readable section title for a modality. */
export function modalityLabel(modality: NpuModality): string {
  switch (modality) {
    case 'llm':
      return 'Chat';
    case 'vlm':
      return 'Vision';
    case 'stt':
      return 'Speech to Text';
    case 'tts':
      return 'Text to Speech';
  }
}

/** One file of a multi-file NPU bundle. */
export interface NpuFile {
  filename: string;
  url: string;
}

export interface NpuModel {
  id: string;
  name: string;
  /** Short spec line: modality · params · target arch. */
  detail: string;
  modality: NpuModality;
  /** Hexagon architecture this bundle is compiled for: "v75" / "v79" / "v81". */
  arch: string;
  /** Multi-file source; the first file must be the QHexRT manifest. */
  files: NpuFile[];
}

/**
 * `resolve/main` direct-download URLs for files of a public HuggingFace
 * subfolder. Appends the repo-root `config.json` as a trailing companion (the
 * Hub's default download-count query file).
 */
function hfFiles(repo: string, arch: string, ...names: string[]): NpuFile[] {
  const base = `https://huggingface.co/${repo}/resolve/main`;
  return [
    ...names.map((n) => ({ filename: n, url: `${base}/${arch}/${n}` })),
    { filename: 'config.json', url: `${base}/config.json` },
  ];
}

/** The six files that make up the public LFM2.5 230M QHexRT bundle (512-ctx). */
const lfm2_5_230mFiles = (arch: string): NpuFile[] =>
  hfFiles(
    'runanywhere/lfm2_5_230m_HNPU',
    arch,
    'lfm2-5-230m.json',
    'lfm230_pf_512_w8.bin',
    'lfm230_dec_512_w8.bin',
    'lfm230_lmh_w8.bin',
    'lfm_embed_f16.bin',
    'tokenizer.json'
  );

export const NPU_MODELS: NpuModel[] = [
  // ---- Public HuggingFace bundle (512-ctx) ----
  {
    id: 'lfm2_5_230m_v79',
    name: 'LFM2.5 230M (HNPU)',
    detail: 'LLM · 230M · Hexagon v79',
    modality: 'llm',
    arch: 'v79',
    files: lfm2_5_230mFiles('v79'),
  },
  {
    id: 'lfm2_5_230m_v81',
    name: 'LFM2.5 230M (HNPU)',
    detail: 'LLM · 230M · Hexagon v81',
    modality: 'llm',
    arch: 'v81',
    files: lfm2_5_230mFiles('v81'),
  },

  // ---- Public HuggingFace HNPU bundles ----
  {
    id: 'lfm2_5_350m_v79',
    name: 'LFM2.5 350M (HNPU)',
    detail: 'LLM · 350M · Hexagon v79',
    modality: 'llm',
    arch: 'v79',
    files: hfFiles(
      'runanywhere/lfm2_5_350m_HNPU',
      'v79',
      'lfm2-5-350m-2048.json',
      'lfm2-5-350m-4k.json',
      'lfm2-5-350m-512s.json',
      'lfm_2048_shared.bin',
      'lfm_512_4k_shared.bin',
      'lfm_embed_f16.bin',
      'lfm_lmh.bin',
      'tokenizer.json'
    ),
  },
  {
    id: 'lfm2_5_350m_v81',
    name: 'LFM2.5 350M (HNPU)',
    detail: 'LLM · 350M · Hexagon v81',
    modality: 'llm',
    arch: 'v81',
    files: hfFiles(
      'runanywhere/lfm2_5_350m_HNPU',
      'v81',
      'lfm2-5-350m-2048.json',
      'lfm_dec_f16.bin',
      'lfm_embed_f16.bin',
      'lfm_lmh_f16.bin',
      'lfm_pf_f16.bin',
      'tokenizer.json'
    ),
  },
  {
    id: 'qwen3_5_0_8b_v81',
    name: 'Qwen3.5 0.8B (HNPU)',
    detail: 'LLM · 0.8B · Hexagon v81',
    modality: 'llm',
    arch: 'v81',
    files: hfFiles(
      'runanywhere/qwen3_5_0_8b_HNPU',
      'v81',
      'qwen3.5-0.8b-1024.json',
      'qwen3508b_decode_f16.bin',
      'qwen3508b_embed_f16.bin',
      'qwen3508b_lmhead_f16.bin',
      'tokenizer.json'
    ),
  },
  {
    id: 'qwen3_vl_v79',
    name: 'Qwen3-VL 2B (HNPU)',
    detail: 'VLM · 2B · Hexagon v79',
    modality: 'vlm',
    arch: 'v79',
    files: hfFiles(
      'runanywhere/qwen3_vl_HNPU',
      'v79',
      'qwen3vl-2b-vlm-512.json',
      'embed_f16.bin',
      'llm_shared_512.bin',
      'lmhead_wqo.bin',
      'qwen3vl-2b-text-512.json',
      'tokenizer.json',
      'vis_native_512.bin',
      'vis_patch_embed_bias_f32.bin',
      'vis_patch_embed_f32.bin',
      'vis_pos_embed_f32.bin'
    ),
  },
  {
    id: 'internvl3_5_1b_v79',
    name: 'InternVL3.5 1B (HNPU)',
    detail: 'VLM · 1B · Hexagon v79',
    modality: 'vlm',
    arch: 'v79',
    files: hfFiles(
      'runanywhere/internvl3_5_1b_HNPU',
      'v79',
      'internvl3_5-1b-512.json',
      'ivl_dec_w4.bin',
      'ivl_embed_f16.bin',
      'ivl_enc2.bin',
      'ivl_lmh_q.bin',
      'ivl_pf_512.bin',
      'tokenizer.json',
      'vlm/pe_b.bin',
      'vlm/pe_cls.bin',
      'vlm/pe_pos.bin',
      'vlm/pe_w.bin',
      'vlm/proj_b1.bin',
      'vlm/proj_b2.bin',
      'vlm/proj_lnb.bin',
      'vlm/proj_lnw.bin',
      'vlm/proj_w1.bin',
      'vlm/proj_w2.bin',
      'vlm/prompt_post.txt',
      'vlm/prompt_pre.txt'
    ),
  },
  {
    id: 'internvl3_5_1b_v81',
    name: 'InternVL3.5 1B (HNPU)',
    detail: 'VLM · 1B · Hexagon v81',
    modality: 'vlm',
    arch: 'v81',
    files: hfFiles(
      'runanywhere/internvl3_5_1b_HNPU',
      'v81',
      'internvl3_5-1b.json',
      'ivl_dec_f16.bin',
      'ivl_embed_f16.bin',
      'ivl_enc_f16.bin',
      'ivl_lmh_f16.bin',
      'ivl_pf_f16.bin',
      'tokenizer.json',
      'vlm/pe_b.bin',
      'vlm/pe_cls.bin',
      'vlm/pe_pos.bin',
      'vlm/pe_w.bin',
      'vlm/proj_b1.bin',
      'vlm/proj_b2.bin',
      'vlm/proj_lnb.bin',
      'vlm/proj_lnw.bin',
      'vlm/proj_w1.bin',
      'vlm/proj_w2.bin',
      'vlm/prompt_post.txt',
      'vlm/prompt_pre.txt'
    ),
  },
  {
    id: 'whisper_base_v79',
    name: 'Whisper Base (HNPU)',
    detail: 'STT · Base · Hexagon v79',
    modality: 'stt',
    arch: 'v79',
    files: hfFiles(
      'runanywhere/whisper_base_HNPU',
      'v79',
      'whisper-base.json',
      'decoder.bin',
      'encoder.bin',
      'tokenizer.json',
      'whisper_base_mel_filters.bin'
    ),
  },
  {
    id: 'whisper_small_v79',
    name: 'Whisper Small (HNPU)',
    detail: 'STT · Small · Hexagon v79',
    modality: 'stt',
    arch: 'v79',
    files: hfFiles(
      'runanywhere/whisper_small_HNPU',
      'v79',
      'whisper-small.json',
      'decoder.bin',
      'encoder.bin',
      'tokenizer.json',
      'whisper_mel_filters.bin'
    ),
  },
  {
    id: 'moonshine_tiny_v81',
    name: 'Moonshine Tiny (HNPU)',
    detail: 'STT · Tiny · Hexagon v81',
    modality: 'stt',
    arch: 'v81',
    files: hfFiles(
      'runanywhere/moonshine_tiny_HNPU',
      'v81',
      'moonshine-tiny.json',
      'moonshine_conv_stem.bin',
      'moonshinetiny_dec_f16.bin',
      'moonshinetiny_enc_f16.bin',
      'tokenizer.json'
    ),
  },
  {
    id: 'moonshine_base_v81',
    name: 'Moonshine Base (HNPU)',
    detail: 'STT · Base · Hexagon v81',
    modality: 'stt',
    arch: 'v81',
    files: hfFiles(
      'runanywhere/moonshine_base_HNPU',
      'v81',
      'moonshine-base.json',
      'moonshine_conv_stem.bin',
      'moonshinebase_dec_f16.bin',
      'moonshinebase_enc_f16.bin',
      'tokenizer.json'
    ),
  },
  {
    id: 'melotts_en_v79',
    name: 'MeloTTS EN (HNPU)',
    detail: 'TTS · EN · Hexagon v79',
    modality: 'tts',
    arch: 'v79',
    files: hfFiles(
      'runanywhere/melotts_en_HNPU',
      'v79',
      'melotts-en.json',
      'melo_decoder.bin',
      'melo_encoder.bin',
      'melo_flow.bin',
      'melo_lexicon.txt',
      'melo_tokens.txt'
    ),
  },
];

/** Human-readable size, e.g. "1.4 GB". */
export function formatBytes(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
  return `${bytes} B`;
}
