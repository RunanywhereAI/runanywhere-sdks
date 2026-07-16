// bridge.ts — loads the native N-API addon and adapts its callback-based
// streaming into an AsyncIterable. The addon is resolved from (in order): the
// RUNANYWHERE_NATIVE_PATH env var, the local dev build output, or the packaged
// location. Sidecar DLLs (onnxruntime, sherpa) must sit next to the .node.
import * as fs from 'fs';
import * as path from 'path';

// Re-exported for existing importers (RunAnywhere.ts imports it from here); the
// implementation now lives in stream.ts so it stays addon-free and testable.
export { toAsyncIterable } from './stream';

/** Raw surface exported by runanywhere_native.node. */
export interface NativeAddon {
  readonly version: string;
  initialize(secureDir: string, baseDir?: string): void;
  loadModel(modelPath: string, id?: string, name?: string): number;
  // (handle, prompt, onToken) or (handle, prompt, options, onToken) — the addon
  // detects whether arg 3 is the callback or a generation-options object.
  generate(
    handle: number,
    prompt: string,
    optionsOrOnToken: object | ((t: string) => void),
    onToken?: (t: string) => void
  ): Promise<void>;
  unloadModel(handle: number): void;
  loadVlmModel(modelPath: string, mmprojPath: string, id?: string, name?: string): number;
  generateVlm(
    handle: number, imagePath: string, prompt: string, onToken: (t: string) => void
  ): Promise<void>;
  unloadVlmModel(handle: number): void;
  loadEmbeddingModel(modelPath: string, configJson?: string): number;
  embed(handle: number, text: string): Float32Array;
  unloadEmbeddingModel(handle: number): void;
  loadSttModel(modelDir: string, id?: string, name?: string): number;
  transcribe(handle: number, pcm16: Uint8Array): string;
  unloadSttModel(handle: number): void;
  loadTtsVoice(voiceDir: string, id?: string, name?: string): number;
  synthesize(handle: number, text: string): { sampleRate: number; samples: Float32Array };
  unloadTtsVoice(handle: number): void;
  shutdown(): void;
}

function resolveAddon(): NativeAddon {
  const candidates = [
    process.env.RUNANYWHERE_NATIVE_PATH,
    // Packaged prebuild bundled by scripts/bundle-native.js (dist -> pkg root).
    path.resolve(
      __dirname, '..', 'prebuilds', `${process.platform}-${process.arch}`,
      'runanywhere_native.node'
    ),
    // Local dev build (repo build dir): dist -> electron -> sdk -> repo root.
    path.resolve(
      __dirname, '..', '..', '..', 'build', 'windows-release', 'sdk',
      'runanywhere-electron', 'native', 'Release', 'runanywhere_native.node'
    ),
    // Packaged (cmake-js default output next to the native package).
    path.resolve(__dirname, '..', 'native', 'build', 'Release', 'runanywhere_native.node'),
  ].filter((p): p is string => Boolean(p));

  for (const p of candidates) {
    if (fs.existsSync(p)) {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      return require(p) as NativeAddon;
    }
  }
  throw new Error(
    'runanywhere_native.node not found. Set RUNANYWHERE_NATIVE_PATH to the built addon.\nTried:\n  ' +
      candidates.join('\n  ')
  );
}

export const addon: NativeAddon = resolveAddon();
