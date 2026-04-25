/**
 * RunAnywhere+Solutions.ts
 *
 * Public API for L5 solutions runtime (T4.7 / T4.8). A "solution" is a
 * prepackaged pipeline config — a typed `SolutionConfig` proto, raw
 * proto bytes, or YAML sugar — that the C++ core compiles into a
 * GraphScheduler DAG and runs through the `rac_solution_*` C ABI.
 *
 * Surface mirrors Swift / Kotlin / Flutter / Web:
 *
 *   const handle = await RunAnywhere.solutions.run({ config })
 *   await handle.start()
 *   await handle.feed('hello')
 *   await handle.closeInput()
 *   await handle.destroy()
 *
 * Reference: sdk/runanywhere-swift/.../Public/Extensions/Solutions/
 */
import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SolutionConfig } from '@runanywhere/proto-ts/solutions';

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  return requireNativeModule();
}

function toBase64(bytes: Uint8Array): string {
  if (typeof globalThis.btoa === 'function') {
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]!);
    }
    return globalThis.btoa(binary);
  }
  const g = globalThis as { Buffer?: { from(b: Uint8Array): { toString(enc: string): string } } };
  if (g.Buffer) {
    return g.Buffer.from(bytes).toString('base64');
  }
  throw new Error('No base64 encoder available in this runtime');
}

/**
 * Lifecycle handle for a started solution.
 *
 * Wraps the C `rac_solution_handle_t` (round-tripped as a JS number).
 * Every verb is async because the native implementation uses Nitro
 * Promises — callers should `await` each call. `destroy()` is
 * idempotent; the handle is inert once destroyed.
 */
export class SolutionHandle {
  private handle: number;
  private alive = true;

  /** @internal */ constructor(handle: number) {
    if (!handle) {
      throw new Error('Cannot construct SolutionHandle from null native handle');
    }
    this.handle = handle;
  }

  /** True until [destroy] clears the underlying native handle. */
  get isAlive(): boolean {
    return this.alive;
  }

  /** Start the underlying scheduler. Non-blocking. */
  async start(): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionStart(this.handle);
    if (!ok) throw new Error('rac_solution_start failed');
  }

  /** Request a graceful shutdown. Non-blocking. */
  async stop(): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionStop(this.handle);
    if (!ok) throw new Error('rac_solution_stop failed');
  }

  /** Force-cancel the graph; returns once workers observe cancellation. */
  async cancel(): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionCancel(this.handle);
    if (!ok) throw new Error('rac_solution_cancel failed');
  }

  /** Feed one UTF-8 item into the root input edge. */
  async feed(item: string): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionFeed(this.handle, item);
    if (!ok) throw new Error('rac_solution_feed failed');
  }

  /** Signal end-of-stream on the root input edge. */
  async closeInput(): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionCloseInput(this.handle);
    if (!ok) throw new Error('rac_solution_close_input failed');
  }

  /** Cancel, join, and release native resources. Idempotent. */
  async destroy(): Promise<void> {
    if (!this.alive) return;
    this.alive = false;
    await ensureNative().solutionDestroy(this.handle);
    this.handle = 0;
  }

  private requireAlive(): void {
    if (!this.alive) {
      throw new Error('SolutionHandle has already been destroyed');
    }
  }
}

/** Arguments to [solutions.run]. Exactly one of the three must be set. */
export interface SolutionRunArgs {
  /** Typed `SolutionConfig` proto — encoded by the SDK before dispatch. */
  config?: SolutionConfig;
  /** Raw SolutionConfig / PipelineSpec proto bytes. */
  configBytes?: Uint8Array;
  /** YAML sugar (SolutionConfig-shape or PipelineSpec-shape). */
  yaml?: string;
}

/**
 * Construct and return a (created, not yet started) solution. Callers
 * own the returned [SolutionHandle] — invoke `.destroy()` when finished.
 */
async function run(args: SolutionRunArgs): Promise<SolutionHandle> {
  const supplied = [args.config, args.configBytes, args.yaml].filter(
    (v) => v !== undefined
  ).length;
  if (supplied !== 1) {
    throw new Error(
      `RunAnywhere.solutions.run requires exactly one of config / configBytes / yaml (got ${supplied})`
    );
  }

  const native = ensureNative();

  if (args.yaml !== undefined) {
    const h = await native.solutionCreateFromYaml(args.yaml);
    if (!h) throw new Error('rac_solution_create_from_yaml failed');
    return new SolutionHandle(h);
  }

  const bytes =
    args.configBytes ?? SolutionConfig.encode(args.config!).finish();
  if (bytes.length === 0) {
    throw new Error(
      'Solution config bytes are empty — refusing to call rac_solution_create_from_proto'
    );
  }

  const base64 = toBase64(bytes);
  const h = await native.solutionCreateFromProto(base64);
  if (!h) throw new Error('rac_solution_create_from_proto failed');
  return new SolutionHandle(h);
}

/**
 * `RunAnywhere.solutions` capability accessor.
 *
 * Stateless — every call to `run(...)` allocates a fresh
 * `rac_solution_handle_t`; callers own the returned [SolutionHandle].
 */
export const solutions = {
  run,
};
