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
import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SolutionConfig } from '@runanywhere/proto-ts/solutions';
import { bytesToArrayBuffer } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { requireInitialized } from '../../../Foundation/Initialization/InitializedGuard';

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
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
      throw SDKException.invalidInput(
        'Cannot construct SolutionHandle from null native handle'
      );
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
    // Swift parity: lifecycle-verb failures throw .processingFailed
    // (RunAnywhere+Solutions.swift:108-117).
    if (!ok) throw SDKException.processingFailed('rac_solution_start failed');
  }

  /** Request a graceful shutdown. Non-blocking. */
  async stop(): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionStop(this.handle);
    if (!ok) throw SDKException.processingFailed('rac_solution_stop failed');
  }

  /** Force-cancel the graph; returns once workers observe cancellation. */
  async cancel(): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionCancel(this.handle);
    if (!ok) throw SDKException.processingFailed('rac_solution_cancel failed');
  }

  /** Feed one UTF-8 item into the root input edge. */
  async feed(item: string): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionFeed(this.handle, item);
    if (!ok) throw SDKException.processingFailed('rac_solution_feed failed');
  }

  /** Signal end-of-stream on the root input edge. */
  async closeInput(): Promise<void> {
    this.requireAlive();
    const ok = await ensureNative().solutionCloseInput(this.handle);
    if (!ok) throw SDKException.processingFailed('rac_solution_close_input failed');
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
      // Swift parity: using a destroyed handle throws .invalidState
      // (RunAnywhere+Solutions.swift:99-104).
      throw SDKException.invalidState(
        'Solution handle has already been destroyed'
      );
    }
  }
}

/**
 * Discriminated-union argument for [solutions.run].
 *
 * Exactly one input kind is accepted at compile time — the TypeScript
 * compiler rejects call sites that supply more than one of {config,
 * configBytes, yaml}, mirroring the three overloads on Swift/Kotlin.
 */
export type SolutionRunArgs =
  | {
      /** Typed `SolutionConfig` proto — encoded by the SDK before dispatch. */
      config: SolutionConfig;
      configBytes?: never;
      yaml?: never;
    }
  | {
      config?: never;
      /** Raw SolutionConfig / PipelineSpec proto bytes. */
      configBytes: Uint8Array;
      yaml?: never;
    }
  | {
      config?: never;
      configBytes?: never;
      /** YAML sugar (SolutionConfig-shape or PipelineSpec-shape). */
      yaml: string;
    };

/**
 * Construct and return a (created, not yet started) solution. Callers
 * own the returned [SolutionHandle] — invoke `.destroy()` when finished.
 */
async function run(args: SolutionRunArgs): Promise<SolutionHandle> {
  // Swift parity: ensureReady() guards isInitialized
  // (RunAnywhere+Solutions.swift:225-227).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+Solutions.swift:228 gates on ensureServicesReady.
  await ensureServicesReady();

  if (args.yaml !== undefined) {
    const h = await native.solutionCreateFromYaml(args.yaml);
    if (!h) {
      // Swift parity: create failures throw .invalidConfiguration
      // (RunAnywhere+Solutions.swift:210-219).
      throw SDKException.invalidConfiguration(
        'rac_solution_create_from_yaml failed'
      );
    }
    return new SolutionHandle(h);
  }

  const configBuffer = args.configBytes
    ? bytesToArrayBuffer(args.configBytes)
    : args.config
      ? encodeProtoMessage(args.config, SolutionConfig)
      : new ArrayBuffer(0);
  if (configBuffer.byteLength === 0) {
    throw SDKException.invalidInput(
      'Solution config bytes are empty — refusing to call rac_solution_create_from_proto'
    );
  }

  const h = await native.solutionCreateFromProto(configBuffer);
  if (!h) {
    // Swift parity: create failures throw .invalidConfiguration
    // (RunAnywhere+Solutions.swift:178-187).
    throw SDKException.invalidConfiguration(
      'rac_solution_create_from_proto failed'
    );
  }
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
