/**
 * HybridModel.ts
 *
 * Public model / backend identity + transcribe-result types for the STT hybrid
 * router. Mirrors the Kotlin RACModel / Backend / TranscribeResult shapes and
 * the Swift HybridModel, all keyed off the wire enums in
 * `@runanywhere/proto-ts/hybrid_router`.
 *
 * Provider is data: a cloud candidate carries its concrete HTTP provider (e.g.
 * "sarvam") in the descriptor's `provider` field — there is no provider-specific
 * backend kind.
 */

import {
  HybridBackendKind,
  HybridModelType,
  type HybridRoutedMetadata,
  type HybridSttTranscribeOptions,
} from '@runanywhere/proto-ts/hybrid_router';

export { HybridBackendKind, HybridModelType };
export type { HybridRoutedMetadata };

/** Default cloud STT provider when a caller omits one. */
export const DEFAULT_CLOUD_PROVIDER = 'sarvam';

/**
 * One side of the hybrid pair. `id` is the resolution key:
 *   - offline (`sherpa`): the model id the C model registry resolves so the
 *     engine can load the model files.
 *   - online (`cloud`): the registry id registered via `CloudSTT.register(...)`,
 *     which supplies the provider, model string + credentials.
 */
export interface HybridModel {
  readonly id: string;
  readonly modelType: HybridModelType;
  readonly backend: HybridBackendKind;
  /**
   * Concrete cloud provider when `backend === HYBRID_BACKEND_CLOUD` (e.g.
   * "sarvam"). Empty for non-cloud backends; marshalled into the descriptor's
   * `provider` field (proto tag 4) so the cloud engine selects the HTTP
   * backend.
   */
  readonly provider: string;
}

/** Convenience for an on-device sherpa model (offline side). */
export function offlineSherpa(id: string): HybridModel {
  return {
    id,
    modelType: HybridModelType.HYBRID_MODEL_TYPE_OFFLINE,
    backend: HybridBackendKind.HYBRID_BACKEND_SHERPA,
    provider: '',
  };
}

/**
 * Convenience for a cloud model (registered via `CloudSTT.register`). `provider`
 * defaults to "sarvam" and is carried in the descriptor so the cloud engine
 * picks the HTTP backend.
 */
export function onlineCloud(
  id: string,
  provider: string = DEFAULT_CLOUD_PROVIDER
): HybridModel {
  return {
    id,
    modelType: HybridModelType.HYBRID_MODEL_TYPE_ONLINE,
    backend: HybridBackendKind.HYBRID_BACKEND_CLOUD,
    provider,
  };
}

/** Map a backend kind to the plugin name `rac_plugin_route` pins on. */
export function pinnedEngineName(backend: HybridBackendKind): string {
  switch (backend) {
    case HybridBackendKind.HYBRID_BACKEND_SHERPA:
      return 'sherpa';
    case HybridBackendKind.HYBRID_BACKEND_CLOUD:
      return 'cloud';
    case HybridBackendKind.HYBRID_BACKEND_LLAMACPP:
      return 'llamacpp';
    case HybridBackendKind.HYBRID_BACKEND_OPENROUTER:
      return 'openrouter';
    default:
      return '';
  }
}

/**
 * STT options carried through the router (mirror of the C `rac_stt_options_t`
 * knobs the router forwards). Ergonomic partial of the generated
 * `HybridSttTranscribeOptions`: all fields optional with backend-default
 * behaviour; the router fills the proto defaults (`''`/`0`) for omitted knobs.
 *
 * Fields: `language` (BCP-47 hint; empty = auto-detect), `sampleRate` (PCM
 * sample-rate hint; 0 = engine default 16000), `audioFormat`
 * (`rac_audio_format_enum_t`: 0=PCM, 1=WAV, 2=MP3, 3=OPUS, 4=AAC, 5=FLAC).
 */
export type HybridTranscribeOptions = Partial<HybridSttTranscribeOptions>;

/** One transcribe call's outcome through the hybrid STT router. */
export interface HybridTranscribeResult {
  /** Transcript text from the chosen backend. */
  readonly text: string;
  /** BCP-47 language code reported by the backend (empty when none surfaced). */
  readonly detectedLanguage: string;
  /** Which side ran, whether it was a fallback, and why the primary failed. */
  readonly routing: HybridRoutedMetadata;
}
