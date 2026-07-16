// bridge.ts — loads the native N-API addon and adapts its callback-based
// streaming into an AsyncIterable. The addon is resolved from (in order): the
// RUNANYWHERE_NATIVE_PATH env var, the local dev build output, or the packaged
// location. Sidecar DLLs (onnxruntime, sherpa) must sit next to the .node.
import * as fs from 'fs';
import * as path from 'path';

/** Raw surface exported by runanywhere_native.node. */
export interface NativeAddon {
  readonly version: string;
  initialize(secureDir: string, baseDir?: string): void;
  loadModel(modelPath: string, id?: string, name?: string): number;
  generate(handle: number, prompt: string, onToken: (t: string) => void): Promise<void>;
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

/**
 * Adapt an addon streaming call — `start(onToken) -> Promise<void>` — into a
 * lazily-consumed AsyncIterable of tokens. Tokens buffer as they arrive; the
 * iterator ends when the promise resolves and rejects if it rejects.
 */
export function toAsyncIterable(
  start: (onToken: (t: string) => void) => Promise<void>
): AsyncIterableIterator<string> {
  const queue: string[] = [];
  let done = false;
  let err: unknown = null;
  let wake: (() => void) | null = null;
  const signal = () => {
    const w = wake;
    wake = null;
    if (w) w();
  };

  start((t) => {
    queue.push(t);
    signal();
  }).then(
    () => {
      done = true;
      signal();
    },
    (e) => {
      err = e;
      done = true;
      signal();
    }
  );

  return {
    [Symbol.asyncIterator]() {
      return this;
    },
    async next(): Promise<IteratorResult<string>> {
      for (;;) {
        if (queue.length) return { value: queue.shift() as string, done: false };
        if (err) throw err;
        if (done) return { value: undefined as unknown as string, done: true };
        await new Promise<void>((r) => {
          wake = r;
        });
      }
    },
  };
}
