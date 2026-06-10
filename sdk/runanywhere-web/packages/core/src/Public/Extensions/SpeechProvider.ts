/**
 * SpeechProvider — INTERNAL/EXPERIMENTAL pluggable speech (STT/TTS/VAD)
 * backend escape hatch. NOT a stable public API.
 *
 * @internal @experimental
 * @deprecated pass3-syn-035 — SpeechProvider duplicates the proto-byte
 *             STT/TTS/VAD path. It is retained only until the unified
 *             `racommons-llamacpp.wasm` artifact passes its STT/TTS/VAD
 *             smoke tests with ORT + Sherpa linked in (see REMOVAL
 *             CONTRACT below for the gating workstream and verification
 *             gate). Do not design new app code or backend features
 *             around the SpeechProvider routing layer — call
 *             `RunAnywhere.transcribe` / `synthesize` /
 *             `detectVoiceActivity` and route through the proto-byte
 *             adapter contract. SDK-internal references are tracked for
 *             deletion under
 *             `duplicate-abstractions-and-SOLID-001-followup-web.json`.
 *
 *             Retirement timeline:
 *               1. Land the unified WASM artifact passing
 *                  `tests/browser/facade-speech-vad.spec.ts` with
 *                  `skipProtoBytePlugins: false`.
 *               2. Flip
 *                  `RunAnywhere+STT/+TTS/+VAD` to skip the SpeechProvider
 *                  branch and go straight to the proto-byte adapter.
 *               3. Delete this file + all `setSpeechProvider /
 *                  getSpeechProvider / hasSpeechProviderSTT / disposeSpeechProvider`
 *                  call sites; remove the internal re-export from
 *                  `packages/core/src/internal.ts`.
 *               4. Drop `web-onnx`'s SpeechProvider registration path
 *                  (its STT/TTS/VAD shall route through the proto-byte
 *                  adapter exclusively).
 *
 * The V2 architecture's canonical path for STT/TTS/VAD is the proto-byte
 * RACommons C ABI (`STTProtoAdapter` / `TTSProtoAdapter` /
 * `VADProtoAdapter`) exposed by the unified `racommons-llamacpp.wasm`
 * artifact. That path still hits an Emscripten exception-trampoline
 * mismatch on the `Ort::InferenceSession::ConstructorCommon` symbol
 * (manifests at runtime as a `function signature mismatch` invoke
 * trampoline error) when the vendored ORT + Sherpa static archives are
 * linked into the unified module, so a working speech artifact is
 * currently provided by the standalone `sherpa-onnx.wasm` module that
 * `@runanywhere/web-onnx` builds via `wasm/scripts/build-sherpa-onnx.sh`.
 *
 * To keep the public Swift-shaped facade verbs
 * (`RunAnywhere.transcribe` / `synthesize` / `detectVoiceActivity`)
 * working without app-side branching during that migration, backend
 * packages register a `SpeechProvider` through this escape hatch and the
 * `RunAnywhere+STT` / `+TTS` / `+VAD` facades dispatch through the
 * registered provider before falling back to the proto-byte adapters.
 *
 * REMOVAL CONTRACT (DUPLICATE-ABSTRACTIONS-AND-SOLID-001):
 *   This module is a temporary escape hatch and MUST be removed once the
 *   unified `racommons-llamacpp.wasm` build passes its STT/TTS/VAD smoke
 *   tests with ORT + Sherpa linked in. Do NOT design new SDK features
 *   around the SpeechProvider routing layer; new speech behavior belongs
 *   in the proto-byte adapter contract.
 *
 *   Enabling work (cross-links):
 *     - `engines/sherpa/CMakeLists.txt:307-348` — Emscripten branch that
 *       already wires the vendored Sherpa-ONNX static archives into the
 *       unified WASM link, gated on
 *       `third_party/sherpa-onnx-wasm/lib/libsherpa-onnx-c-api.a`.
 *     - `comments/pr-494/addressing/REMAINING_WORK.md` section B4
 *       ("Remove SpeechProvider escape hatch when unified WASM is ready")
 *       — the tracking workstream that supersedes this escape hatch.
 *     - `comments/pr-494/addressing/comments/duplicate-abstractions-and-SOLID-001-followup-web.json`
 *       — future GH issue payload that owns the actual deletion.
 *
 *   Verification gate (DO NOT delete this file before this passes):
 *     Removal is gated on `tests/browser/facade-speech-vad.spec.ts`
 *     running with `skipProtoBytePlugins: false` against an
 *     `--all-backends` build, with no `function signature mismatch`
 *     runtime error.
 *
 * The provider operates on opaque model identifiers — the SDK already
 * downloaded and extracted the model into the local storage backend
 * (OPFS / FS Access) and passes the resolved local path. The provider
 * is responsible for staging the bytes into whatever in-process
 * filesystem its backend uses (e.g. Sherpa MEMFS via `FS_createDataFile`).
 */

import type {
  STTOptions,
  STTOutput,
  STTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import type {
  TTSOptions,
  TTSOutput,
} from '@runanywhere/proto-ts/tts_options';
import type {
  VADConfiguration,
  VADOptions,
  VADResult,
} from '@runanywhere/proto-ts/vad_options';

export interface SpeechProviderModelHandle {
  /** Stable identifier supplied by the caller (typically the model id). */
  id: string;
  /** Local on-device path the SDK download orchestrator produced. */
  path: string;
  /** Optional human-readable name for diagnostics / UI. */
  name?: string;
}

export interface SpeechProviderSTTLoadRequest extends SpeechProviderModelHandle {
  /** Optional Whisper-style language hint. */
  language?: string;
}

export interface SpeechProviderTTSLoadRequest extends SpeechProviderModelHandle {
  /** VITS-style data dir (e.g. extracted `espeak-ng-data` directory). */
  espeakDataDir?: string;
  /** Optional tokens.txt path; defaults to `<modelDir>/tokens.txt` if unset. */
  tokensPath?: string;
}

export type SpeechProviderVADLoadRequest = SpeechProviderModelHandle;

export interface SpeechProviderTranscribeInput {
  audio: Float32Array;
  sampleRate?: number;
  options?: Partial<STTOptions>;
  /** Optional partial-result callback, mirrors `STTProtoAdapter.transcribeStream`. */
  onPartial?: (partial: STTPartialResult) => void;
}

export interface SpeechProviderSynthesizeInput {
  text: string;
  options?: Partial<TTSOptions>;
  speakerId?: number;
  /** Optional progress callback for streaming TTS implementations. */
  onChunk?: (samples: Float32Array, progress: number) => void;
}

export interface SpeechProviderDetectVoiceInput {
  audio: Float32Array;
  sampleRate?: number;
  config?: Partial<VADConfiguration>;
  options?: Partial<VADOptions>;
}

/**
 * @deprecated pass3-syn-035 — use the proto-byte STT/TTS/VAD adapter contract
 *             instead. See file header REMOVAL CONTRACT for the retirement
 *             timeline and verification gate.
 */
export interface SpeechProvider {
  /** Stable identifier — used for diagnostics and idempotent registration. */
  readonly id: string;

  /**
   * Optional capability flags. The facade uses these to decide whether to
   * route a particular call through this provider. Defaults to all
   * supported.
   */
  readonly supportsSTT?: boolean;
  readonly supportsTTS?: boolean;
  readonly supportsVAD?: boolean;

  /** Load a STT model. Idempotent on `request.id`. */
  loadSTT?(request: SpeechProviderSTTLoadRequest): Promise<void>;
  /** Load a TTS voice. Idempotent on `request.id`. */
  loadTTS?(request: SpeechProviderTTSLoadRequest): Promise<void>;
  /** Load (or replace) the VAD model. Idempotent on `request.id`. */
  loadVAD?(request: SpeechProviderVADLoadRequest): Promise<void>;

  unloadSTT?(): Promise<void> | void;
  unloadTTS?(): Promise<void> | void;
  unloadVAD?(): Promise<void> | void;

  isSTTLoaded?(): boolean;
  isTTSLoaded?(): boolean;
  isVADLoaded?(): boolean;

  /** Run STT against the most recently loaded model. */
  transcribe?(input: SpeechProviderTranscribeInput): Promise<STTOutput>;
  /** Run TTS against the most recently loaded voice. */
  synthesize?(input: SpeechProviderSynthesizeInput): Promise<TTSOutput>;
  /** Run VAD against the most recently loaded model. */
  detectVoiceActivity?(input: SpeechProviderDetectVoiceInput): Promise<VADResult>;

  /**
   * Optional dispose hook. Called by `RunAnywhere.shutdown()` so the provider
   * can release any backend module/component handles it owns. Implementations
   * should be idempotent and safe to call before any load.
   */
  dispose?(): Promise<void> | void;
}

let _activeProvider: SpeechProvider | null = null;

/**
 * Install a speech provider. Pass `null` to clear.
 *
 * @deprecated pass3-syn-035 — see file header REMOVAL CONTRACT. New code
 *             should route through the proto-byte STT/TTS/VAD adapters.
 */
export function setSpeechProvider(provider: SpeechProvider | null): void {
  _activeProvider = provider;
}

/**
 * Tear down the active speech provider, invoking `dispose()` if it exists,
 * then clearing the singleton slot. Safe to call when no provider is set.
 * Any error thrown by `dispose()` is caught and surfaced to the caller via
 * the returned promise so SDK shutdown can still complete.
 *
 * @deprecated pass3-syn-035 — see file header REMOVAL CONTRACT.
 */
export async function disposeSpeechProvider(): Promise<void> {
  const provider = _activeProvider;
  _activeProvider = null;
  if (provider && typeof provider.dispose === 'function') {
    await provider.dispose();
  }
}

/** @deprecated pass3-syn-035 — see file header REMOVAL CONTRACT. */
export function getSpeechProvider(): SpeechProvider | null {
  return _activeProvider;
}

/** @deprecated pass3-syn-035 — see file header REMOVAL CONTRACT. */
export function hasSpeechProviderSTT(): boolean {
  return !!_activeProvider && _activeProvider.supportsSTT !== false
    && typeof _activeProvider.transcribe === 'function';
}

/** @deprecated pass3-syn-035 — see file header REMOVAL CONTRACT. */
export function hasSpeechProviderTTS(): boolean {
  return !!_activeProvider && _activeProvider.supportsTTS !== false
    && typeof _activeProvider.synthesize === 'function';
}

/** @deprecated pass3-syn-035 — see file header REMOVAL CONTRACT. */
export function hasSpeechProviderVAD(): boolean {
  return !!_activeProvider && _activeProvider.supportsVAD !== false
    && typeof _activeProvider.detectVoiceActivity === 'function';
}
