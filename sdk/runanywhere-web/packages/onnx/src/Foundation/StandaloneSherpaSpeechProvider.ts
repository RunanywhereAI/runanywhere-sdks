/**
 * StandaloneSherpaSpeechProvider — implementation of the V2 core
 * `SpeechProvider` interface that dispatches STT / TTS / VAD through
 * the standalone Sherpa Emscripten module.
 *
 * Lifecycle:
 *   - `loadVAD({ id, path })` stages the silero_vad.onnx file from the
 *     RACommons MEMFS into the Sherpa MEMFS at the same path, then calls
 *     `_SherpaOnnxCreateVoiceActivityDetector`.
 *   - `loadTTS({ id, path })` mirrors the entire VITS-Piper directory
 *     tree (model.onnx + tokens.txt + espeak-ng-data/) into Sherpa MEMFS
 *     and constructs the `_SherpaOnnxCreateOfflineTts` handle.
 *   - `loadSTT({ id, path })` walks a Whisper directory (encoder.onnx,
 *     decoder.onnx, tokens.txt) and constructs
 *     `_SherpaOnnxCreateOfflineRecognizer` via the upstream init helper.
 *
 * The `path` argument is the local on-device path the V2 SDK download
 * orchestrator produced. Inside the unified RACommons MEMFS this is
 * typically `/opfs/RunAnywhere/Models/Sherpa/<id>/<id>` for tarball
 * extracts, or `/opfs/RunAnywhere/Models/Sherpa/<id>/silero_vad.onnx`
 * for single-file VAD models.
 */

import {
  AudioFormat,
} from '@runanywhere/proto-ts/model_types';
import { STTLanguage } from '@runanywhere/proto-ts/stt_options';
import {
  SDKLogger,
  setSpeechProvider,
  tryRunanywhereModule,
  type EmscriptenRunanywhereModule,
  type SpeechProvider,
  type SpeechProviderDetectVoiceInput,
  type SpeechProviderModelHandle,
  type SpeechProviderSTTLoadRequest,
  type SpeechProviderSynthesizeInput,
  type SpeechProviderTTSLoadRequest,
  type SpeechProviderTranscribeInput,
  type SpeechProviderVADLoadRequest,
} from '@runanywhere/web/internal';
import type { STTOutput } from '@runanywhere/proto-ts/stt_options';
import type { TTSOutput } from '@runanywhere/proto-ts/tts_options';
import type { VADResult } from '@runanywhere/proto-ts/vad_options';

import {
  getStandaloneSherpaModule,
  type StandaloneSherpaModule,
} from './StandaloneSherpaModule';
import {
  ensureEspeakVoiceFiles,
  ensureParentDirs,
  stageBytes,
  stageFromCommonsFs,
} from './SherpaFsStaging';
import { StandaloneSherpaVad } from './StandaloneSherpaVad';
import {
  StandaloneSherpaTts,
  type StandaloneSherpaTtsVitsConfig,
} from './StandaloneSherpaTts';
import { StandaloneSherpaStt } from './StandaloneSherpaStt';

const logger = new SDKLogger('StandaloneSherpaSpeechProvider');

interface CommonsFsModule extends EmscriptenRunanywhereModule {
  FS?: {
    readFile(path: string): Uint8Array;
    readdir(path: string): string[];
    stat(path: string): { mode: number; size?: number };
    isDir(mode: number): boolean;
  };
}

class StandaloneSherpaSpeechProvider implements SpeechProvider {
  readonly id = 'standalone-sherpa-onnx';
  readonly supportsSTT = true;
  readonly supportsTTS = true;
  readonly supportsVAD = true;

  private module: StandaloneSherpaModule | null = null;
  private vad: StandaloneSherpaVad | null = null;
  private vadModelId: string | null = null;
  private tts: StandaloneSherpaTts | null = null;
  private ttsModelId: string | null = null;
  private stt: StandaloneSherpaStt | null = null;
  private sttModelId: string | null = null;

  private async ensureModule(): Promise<StandaloneSherpaModule> {
    if (!this.module) {
      this.module = await getStandaloneSherpaModule();
    }
    return this.module;
  }

  /**
   * Release all backend handles. Called by the core SDK shutdown/reset path
   * via `disposeSpeechProvider()`. Safe to invoke multiple times.
   */
  async dispose(): Promise<void> {
    await Promise.allSettled([
      this.unloadVAD(),
      this.unloadTTS(),
      this.unloadSTT(),
    ]);
    this.module = null;
  }

  // -------------------------------------------------------------------------
  // VAD
  // -------------------------------------------------------------------------

  isVADLoaded(): boolean {
    return this.vad?.isLoaded() ?? false;
  }

  async unloadVAD(): Promise<void> {
    this.vad?.destroy();
    this.vad = null;
    this.vadModelId = null;
  }

  async loadVAD(request: SpeechProviderVADLoadRequest): Promise<void> {
    if (this.vad?.isLoaded() && this.vadModelId === request.id) return;
    const module = await this.ensureModule();

    if (this.vad?.isLoaded()) {
      this.vad.destroy();
    }

    const stagedPath = await stageModelInputBytes(module, request);
    const vad = new StandaloneSherpaVad(module);
    await vad.load({
      modelPath: stagedPath,
      sampleRate: 16000,
      windowSize: 512,
    });
    this.vad = vad;
    this.vadModelId = request.id;
    logger.info(`Standalone Sherpa VAD ready for "${request.id}" (${stagedPath})`);
  }

  async detectVoiceActivity(input: SpeechProviderDetectVoiceInput): Promise<VADResult> {
    if (!this.vad?.isLoaded()) {
      throw new Error('StandaloneSherpaSpeechProvider: VAD not loaded. Call loadVAD() first.');
    }
    // pass3-syn-061: Silero VAD is a recurrent NN. The SpeechProvider
    // `detectVoiceActivity` verb is documented as a one-shot, stateless
    // operation per call — so reset the recurrent (h/c) hidden state
    // before feeding new audio. Without this, the n-th call's first
    // chunk inherits hidden state from the (n-1)-th call's tail, which
    // contaminates the detection result and is a public-API correctness
    // violation. `reset()` also clears the upstream segment queue per
    // sherpa-onnx semantics.
    this.vad.reset();
    const sampleRate = input.sampleRate ?? input.config?.sampleRate ?? 16000;
    const window = 512;
    let isSpeech = false;
    for (let i = 0; i < input.audio.length; i += window) {
      const chunk = input.audio.subarray(i, Math.min(i + window, input.audio.length));
      if (chunk.length < window) {
        const padded = new Float32Array(window);
        padded.set(chunk, 0);
        if (this.vad.acceptWaveform(padded)) isSpeech = true;
      } else if (this.vad.acceptWaveform(chunk)) {
        isSpeech = true;
      }
    }
    if (!isSpeech) {
      isSpeech = this.vad.isDetected();
    }
    const durationMs = (input.audio.length / sampleRate) * 1000;
    const result: VADResult = {
      isSpeech,
      confidence: isSpeech ? 1 : 0,
      energy: 0,
      durationMs,
      timestampMs: Date.now(),
      startTimeMs: 0,
      endTimeMs: isSpeech ? durationMs : 0,
    } as unknown as VADResult;
    return result;
  }

  // -------------------------------------------------------------------------
  // TTS
  // -------------------------------------------------------------------------

  isTTSLoaded(): boolean {
    return this.tts?.isLoaded() ?? false;
  }

  async unloadTTS(): Promise<void> {
    this.tts?.destroy();
    this.tts = null;
    this.ttsModelId = null;
  }

  async loadTTS(request: SpeechProviderTTSLoadRequest): Promise<void> {
    if (this.tts?.isLoaded() && this.ttsModelId === request.id) return;
    const module = await this.ensureModule();

    if (this.tts?.isLoaded()) {
      this.tts.destroy();
    }

    const stagedDir = await stageDirectoryFromCommons(module, request.path);
    const vits = await resolveVitsConfig(module, stagedDir, request);
    logger.debug(
      `Standalone Sherpa TTS resolved layout: model=${vits.modelPath} tokens=${vits.tokensPath} dataDir=${vits.dataDir ?? '<none>'}`,
    );

    // Piper VITS bundles ship lang/<family>/<voice> but only voices/!v/, so
    // espeak-ng's runtime fails to resolve voice IDs like `en-us`. Mirror
    // every lang/ voice descriptor flat under voices/<voice> before
    // constructing the TTS handle. Mirrors the C++
    // `ensure_espeak_voice_files` shim from
    // `engines/sherpa/sherpa_backend.cpp`.
    if (vits.dataDir) {
      try {
        const result = ensureEspeakVoiceFiles(module, vits.dataDir);
        logger.info(
          `Standalone Sherpa TTS ensure_espeak_voice_files: copied=${result.copied} skipped=${result.skipped} errors=${result.errors} (${result.voices.length} voices total)`,
        );
      } catch (err) {
        logger.warning(
          `ensure_espeak_voice_files failed (continuing — TTS may still construct): ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
    }

    const tts = new StandaloneSherpaTts(module);
    await tts.load({ vits, numThreads: 1, provider: 'cpu' });
    this.tts = tts;
    this.ttsModelId = request.id;
    logger.info(`Standalone Sherpa TTS ready for "${request.id}" (${stagedDir})`);
  }

  async synthesize(input: SpeechProviderSynthesizeInput): Promise<TTSOutput> {
    if (!this.tts?.isLoaded()) {
      throw new Error('StandaloneSherpaSpeechProvider: TTS not loaded. Call loadTTS() first.');
    }
    const speakerId = (input.speakerId ?? 0) | 0;
    const speakingRate = input.options?.speakingRate ?? 1.0;
    const result = this.tts.generate(input.text, speakerId, speakingRate);
    const pcm16 = floatToPcm16Bytes(result.samples);
    const sampleRate = result.sampleRate;
    const out: TTSOutput = {
      audioData: pcm16,
      audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
      sampleRate,
      durationMs: Math.round((result.samples.length / sampleRate) * 1000),
      phonemeTimestamps: [],
      timestampMs: Date.now(),
      chunkIndex: 0,
      isFinal: true,
      audioSizeBytes: pcm16.byteLength,
      errorCode: 0,
    };
    return out;
  }

  // -------------------------------------------------------------------------
  // STT
  // -------------------------------------------------------------------------

  isSTTLoaded(): boolean {
    return this.stt?.isLoaded() ?? false;
  }

  async unloadSTT(): Promise<void> {
    this.stt?.destroy();
    this.stt = null;
    this.sttModelId = null;
  }

  async loadSTT(request: SpeechProviderSTTLoadRequest): Promise<void> {
    if (this.stt?.isLoaded() && this.sttModelId === request.id) return;
    const module = await this.ensureModule();
    if (this.stt?.isLoaded()) this.stt.destroy();

    const stagedDir = await stageDirectoryFromCommons(module, request.path);
    const whisperFiles = await discoverWhisperFiles(module, stagedDir);
    const stt = new StandaloneSherpaStt(module);
    await stt.load({
      whisper: {
        encoderPath: whisperFiles.encoder,
        decoderPath: whisperFiles.decoder,
        tokensPath: whisperFiles.tokens,
        language: request.language ?? 'en',
        task: 'transcribe',
      },
      numThreads: 1,
      provider: 'cpu',
    });
    this.stt = stt;
    this.sttModelId = request.id;
    logger.info(`Standalone Sherpa STT ready for "${request.id}" (${stagedDir})`);
  }

  async transcribe(input: SpeechProviderTranscribeInput): Promise<STTOutput> {
    if (!this.stt?.isLoaded()) {
      throw new Error('StandaloneSherpaSpeechProvider: STT not loaded. Call loadSTT() first.');
    }
    const sampleRate = input.sampleRate ?? 16000;
    const result = this.stt.transcribe(input.audio, sampleRate);
    const durationMs = Math.round((input.audio.length / sampleRate) * 1000);
    const out: STTOutput = {
      text: result.text,
      language: STTLanguage.STT_LANGUAGE_AUTO,
      confidence: 0,
      words: [],
      alternatives: [],
      timestampMs: Date.now(),
      durationMs,
      speakerIds: [],
      errorCode: 0,
    } as unknown as STTOutput;
    return out;
  }
}

// ---------------------------------------------------------------------------
// File-staging helpers
// ---------------------------------------------------------------------------

async function stageModelInputBytes(
  module: StandaloneSherpaModule,
  request: SpeechProviderModelHandle,
): Promise<string> {
  const commons = tryRunanywhereModule() as CommonsFsModule | null;
  if (commons?.FS && safeStat(commons, request.path)) {
    return stageFromCommonsFs(module, request.path);
  }
  // The path does not exist in the commons MEMFS — assume it's a fetchable
  // URL or already a Sherpa MEMFS path. If it looks like a URL, fetch and
  // stage it; otherwise trust the caller.
  if (/^(https?:|blob:|\/@fs\/|\/)/.test(request.path)) {
    const response = await fetch(request.path);
    if (!response.ok) {
      throw new Error(`Failed to fetch model "${request.path}": ${response.status}`);
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    const slash = request.path.lastIndexOf('/');
    const name = slash >= 0 ? request.path.slice(slash + 1) : request.path;
    const dest = `/${name}`;
    stageBytes(module, '/', name, bytes);
    return dest;
  }
  return request.path;
}

/**
 * Stage a model path (either a directory subtree or a single file) from the
 * RACommons MEMFS into the Sherpa module's MEMFS. The function name predates
 * pass3-syn-063 — both file and directory inputs are now supported.
 *
 * pass3-syn-062: This staging path hard-requires the RACommons FS bridge
 * which is installed by `@runanywhere/web-llamacpp`'s WASM module. The
 * speech-only install path advertised in `packages/onnx/README.md` has no
 * commons FS available, so we throw a precise, actionable error here — and
 * make the dependency explicit at the install boundary (see
 * `installStandaloneSherpaSpeechProvider`).
 *
 * pass3-syn-063: Earlier versions called `ensureParentDirs(module, path)`
 * unconditionally, which treats every path segment as a directory. For a
 * single-file model (e.g. single-file Whisper tiny, single-file Piper voice),
 * this creates a phantom directory at the filename and then
 * `stageFromCommonsFs` tries to write a regular file at the same path,
 * causing a silent MEMFS collision. We now stat the path first and call
 * `ensureParentDirs` on the directory itself (when input is a directory) or
 * on the file's parent (when input is a file).
 */
async function stageDirectoryFromCommons(
  module: StandaloneSherpaModule,
  path: string,
): Promise<string> {
  const commons = tryRunanywhereModule() as CommonsFsModule | null;
  if (!commons?.FS) {
    // pass3-syn-062: clearer, actionable error. Speech model staging is
    // gated on the commons FS bridge installed by `@runanywhere/web-llamacpp`.
    throw new Error(
      'StandaloneSherpaSpeechProvider: cannot stage speech model — the RACommons MEMFS bridge is not installed. ' +
      'Install `@runanywhere/web-llamacpp` and call `LlamaCPP.register()` before `ONNX.register()` so the unified ' +
      'RACommons WASM module is available for speech model staging. ' +
      'Alternatively, await `installStandaloneSherpaSpeechProvider()` only after the commons module is online.',
    );
  }
  // pass3-syn-063: stat the path before treating it as a directory.
  const stat = safeFsStat(commons, path);
  if (!stat) {
    throw new Error(
      `StandaloneSherpaSpeechProvider: model path "${path}" does not exist in the RACommons MEMFS.`,
    );
  }
  if (isCommonsDir(commons, path, stat.mode)) {
    // Directory layout (tarball-extracted bundle) — preserve every segment.
    ensureParentDirs(module, path);
  } else {
    // File layout (single-blob STT/TTS model) — only create the parent tree;
    // the file itself will be written by `stageFromCommonsFs` via stageBytes.
    const slash = path.lastIndexOf('/');
    const parent = slash > 0 ? path.slice(0, slash) : '/';
    ensureParentDirs(module, parent);
  }
  return stageFromCommonsFs(module, path);
}

/**
 * Local stat helper that mirrors `safeStat` in SherpaFsStaging. Returns the
 * Emscripten stat record (with `mode`) or `null` when the path is not present.
 */
function safeFsStat(commons: CommonsFsModule, path: string): { mode: number } | null {
  if (!commons.FS) return null;
  try {
    return commons.FS.stat(path);
  } catch {
    return null;
  }
}

/**
 * Local directory-detection helper that mirrors the logic in
 * `SherpaFsStaging.isDirectoryPath` but only uses the narrow `CommonsFsModule`
 * FS surface defined in this file.
 */
function isCommonsDir(commons: CommonsFsModule, path: string, mode: number): boolean {
  if (!commons.FS) return false;
  if (typeof commons.FS.isDir === 'function') {
    return commons.FS.isDir(mode);
  }
  try {
    commons.FS.readdir(path);
    return true;
  } catch {
    return false;
  }
}

function safeStat(commons: CommonsFsModule, path: string): boolean {
  if (!commons.FS) return false;
  try {
    commons.FS.stat(path);
    return true;
  } catch {
    return false;
  }
}

interface VitsModelLayout {
  modelPath: string;
  tokensPath: string;
  dataDir?: string;
}

async function resolveVitsConfig(
  module: StandaloneSherpaModule,
  stagedDir: string,
  request: SpeechProviderTTSLoadRequest,
): Promise<StandaloneSherpaTtsVitsConfig> {
  void module; // Sherpa MEMFS lookups happen via libc fopen at C++ level.
  const layout = await locateVitsLayout(stagedDir, request);
  return {
    modelPath: layout.modelPath,
    tokensPath: layout.tokensPath,
    dataDir: request.espeakDataDir ?? layout.dataDir,
  };
}

async function locateVitsLayout(
  stagedDir: string,
  request: SpeechProviderTTSLoadRequest,
): Promise<VitsModelLayout> {
  const commons = tryRunanywhereModule() as CommonsFsModule | null;
  if (!commons?.FS) {
    throw new Error('StandaloneSherpaSpeechProvider.locateVitsLayout: commons FS not available.');
  }
  const candidates = readChildren(commons, stagedDir);
  const onnx = candidates.find((n) => n.endsWith('.onnx'));
  const tokens = candidates.find((n) => n === 'tokens.txt' || n.endsWith('-tokens.txt'));
  const espeak = candidates.find((n) => n === 'espeak-ng-data');
  if (!onnx) {
    throw new Error(`No .onnx model file found under "${stagedDir}". Files: ${candidates.join(', ')}`);
  }
  if (!tokens) {
    throw new Error(`No tokens.txt found under "${stagedDir}". Files: ${candidates.join(', ')}`);
  }
  return {
    modelPath: `${stagedDir}/${onnx}`,
    tokensPath: request.tokensPath ?? `${stagedDir}/${tokens}`,
    dataDir: espeak ? `${stagedDir}/${espeak}` : undefined,
  };
}

interface WhisperFiles {
  encoder: string;
  decoder: string;
  tokens: string;
}

async function discoverWhisperFiles(
  module: StandaloneSherpaModule,
  stagedDir: string,
): Promise<WhisperFiles> {
  void module;
  const commons = tryRunanywhereModule() as CommonsFsModule | null;
  if (!commons?.FS) {
    throw new Error('StandaloneSherpaSpeechProvider.discoverWhisperFiles: commons FS not available.');
  }
  const children = readChildren(commons, stagedDir);
  const isOnnx = (n: string): boolean => n.endsWith('.onnx');
  const isInt8 = (n: string): boolean => n.includes('.int8.onnx');
  const encoderInt8 = children.find((n) => isOnnx(n) && n.includes('encoder') && isInt8(n));
  const encoderFp32 = children.find((n) => isOnnx(n) && n.includes('encoder') && !isInt8(n));
  const decoderInt8 = children.find((n) => isOnnx(n) && n.includes('decoder') && isInt8(n));
  const decoderFp32 = children.find((n) => isOnnx(n) && n.includes('decoder') && !isInt8(n));
  const tokens = children.find((n) => n === 'tokens.txt' || n.endsWith('tokens.txt'));

  const encoder = encoderInt8 && decoderInt8 ? encoderInt8 : (encoderFp32 ?? encoderInt8);
  const decoder = encoderInt8 && decoderInt8 ? decoderInt8 : (decoderFp32 ?? decoderInt8);
  if (!encoder || !decoder) {
    throw new Error(`No Whisper encoder/decoder pair found under "${stagedDir}". Files: ${children.join(', ')}`);
  }
  if (!tokens) {
    throw new Error(`No tokens.txt found under "${stagedDir}". Files: ${children.join(', ')}`);
  }
  return {
    encoder: `${stagedDir}/${encoder}`,
    decoder: `${stagedDir}/${decoder}`,
    tokens: `${stagedDir}/${tokens}`,
  };
}

function readChildren(commons: CommonsFsModule, path: string): string[] {
  if (!commons.FS) return [];
  try {
    return commons.FS.readdir(path).filter((n) => n !== '.' && n !== '..');
  } catch {
    return [];
  }
}

function floatToPcm16Bytes(samples: Float32Array): Uint8Array {
  const out = new Uint8Array(samples.length * 2);
  const view = new DataView(out.buffer);
  for (let i = 0; i < samples.length; i += 1) {
    let s = Math.max(-1, Math.min(1, samples[i]));
    s = s < 0 ? Math.round(s * 0x8000) : Math.round(s * 0x7fff);
    view.setInt16(i * 2, s, true);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Public install / uninstall
// ---------------------------------------------------------------------------

let _activeProvider: StandaloneSherpaSpeechProvider | null = null;

/**
 * Install the standalone Sherpa speech provider on the V2 facade. Idempotent.
 * Does NOT eagerly load the WASM module — that happens lazily on the first
 * `loadVAD` / `loadTTS` / `loadSTT` call.
 *
 * pass3-syn-062: model-file staging (`stageDirectoryFromCommons`) requires
 * the RACommons MEMFS bridge installed by `@runanywhere/web-llamacpp`. We
 * log a clear warning here when the commons module is not yet online so
 * speech-only install paths surface the dependency at install time rather
 * than as an opaque "RACommons module FS bridge is not installed" error on
 * the first `transcribe()` call.
 */
export function installStandaloneSherpaSpeechProvider(): SpeechProvider {
  if (!_activeProvider) {
    _activeProvider = new StandaloneSherpaSpeechProvider();
  }
  setSpeechProvider(_activeProvider);
  const commons = tryRunanywhereModule() as CommonsFsModule | null;
  if (!commons?.FS) {
    logger.warning(
      'Standalone Sherpa speech provider installed without an active RACommons MEMFS bridge. ' +
      'STT/TTS model staging will fail until `@runanywhere/web-llamacpp` is installed and ' +
      '`LlamaCPP.register()` has completed. VAD loadVAD() can still accept http/blob/absolute paths.',
    );
  }
  return _activeProvider;
}

/**
 * Tear down the active standalone Sherpa speech provider.
 *
 * pass3-syn-159: Previously this scheduled `unloadVAD/TTS/STT` via
 * `void provider.unloadX()` and nulled `_activeProvider` synchronously,
 * so destruction work — including async config-buffer frees inside
 * StandaloneSherpaStt/Tts — could race a subsequent `installStandaloneSherpaSpeechProvider()`
 * call. The function is now async and awaits every unload before clearing
 * the active-provider reference so consumers get a deterministic
 * `uninstall(); install()` cycle.
 */
export async function uninstallStandaloneSherpaSpeechProvider(): Promise<void> {
  const provider = _activeProvider;
  if (provider) {
    await Promise.allSettled([
      provider.unloadVAD(),
      provider.unloadTTS(),
      provider.unloadSTT(),
    ]);
  }
  _activeProvider = null;
  setSpeechProvider(null);
}

export function getInstalledStandaloneSherpaSpeechProvider(): SpeechProvider | null {
  return _activeProvider;
}
