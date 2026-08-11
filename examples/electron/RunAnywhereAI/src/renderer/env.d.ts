/**
 * What the renderer can see.
 *
 * Both bridges are strongly typed from their real definitions, so a change in the
 * SDK or in this app's preload is a compile error here rather than a runtime
 * surprise.
 */
import type { RunAnywhereApi } from '@runanywhere/electron';

import type { AppBridge } from '../preload/bridge-types';

/**
 * The SDK surface as the preload publishes it.
 *
 * It is `RunAnywhereApi` with two adjustments, both forced by `contextBridge`:
 *  * `version` is a function, not a getter — contextBridge clones what it
 *    publishes, so a getter would be read once at expose time, before
 *    `initialize()` has anything to report.
 *  * `initialize` takes positional arguments rather than an options object.
 *  * `isReady` / `deviceId` / `environment` getters do not survive the clone.
 */
type SdkNamespaces = Omit<RunAnywhereApi, 'initialize' | 'version' | 'isReady' | 'deviceId' | 'environment'>;

export interface RunAnywhereBridge extends SdkNamespaces {
  /** Resolves once the utility host has connected and the addon is loaded. */
  ready(): Promise<void>;
  version(): Promise<string>;
  initialize(
    secureDir?: string,
    baseDir?: string,
    controlPlane?: { apiKey?: string; baseUrl?: string; environment?: string },
  ): Promise<void>;
  /**
   * This app's staged table, read back for the display metadata commons has no
   * field for — label, licence, parameter count, the "heavy" warning. Everything
   * about a model's STATE comes from `models`.
   */
  catalog(): Readonly<Record<string, import('@runanywhere/electron').CatalogEntry>>;

  // Renderer-side audio DSP (no RPC): anti-aliased rate conversion and PCM16
  // packing for the mic -> STT path.
  downsample(samples: Float32Array, inRate: number, outRate: number): Float32Array;
  pcm16Bytes(samples: Float32Array): Uint8Array;
  rms(samples: Float32Array): number;
}

declare global {
  interface Window {
    readonly runanywhere: RunAnywhereBridge;
    /** This app's own bridge: store, platform, theme, dialogs, logging. */
    readonly appStore: AppBridge;
    /** Present only under RA_SELFTEST=1. */
    readonly runanywhereTest?: {
      done(ok: boolean): void;
      log(line: string): void;
    };
  }
}

export {};
