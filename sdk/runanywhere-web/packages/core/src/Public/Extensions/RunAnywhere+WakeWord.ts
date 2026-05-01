/**
 * RunAnywhere+WakeWord.ts
 *
 * P2 feature B11 — Wake Word public facade for the Web SDK.
 *
 * Mirrors Swift's `RunAnywhere.wakeWord` namespace. Exposes the
 * canonical `load → detect → unload` triple as a `RunAnywhere.wakeWord.*`
 * capability surface, symmetric with `RunAnywhere.vad`,
 * `RunAnywhere.storage`, etc.
 *
 * The `rac_wake_word_*` C ABI exists in runanywhere-commons but is
 * currently stubbed (returns RAC_ERROR_FEATURE_NOT_AVAILABLE) and the
 * WASM binding layer does not yet re-export it. Until an extension
 * provider registers itself via `ExtensionPoint`, the namespace
 * surfaces `SDKException.backendNotAvailable` so apps get a clear
 * signal rather than a silent no-op.
 */

import { SDKException } from '../../Foundation/SDKException';

/** Extension-point surface a wake-word provider must implement. */
export interface WakeWordProvider {
  load?(modelPath: string): Promise<void>;
  detect?(audio: Uint8Array): Promise<boolean>;
  unload?(): Promise<void>;
}

// `ProviderCapability` in `Infrastructure/ProviderTypes` only lists
// `'llm' | 'stt' | 'tts' | 'vad'` today; until wake-word is added to
// that union, store the provider in a module-level slot. Apps can wire
// a provider via `registerWakeWordProvider(provider)`.
let _wakeWordProvider: WakeWordProvider | null = null;

/** Register a wake-word provider. Replaces any previously registered one. */
export function registerWakeWordProvider(
  provider: WakeWordProvider | null,
): void {
  _wakeWordProvider = provider;
}

function getWakeWordProvider(): WakeWordProvider | null {
  return _wakeWordProvider;
}

/**
 * Wake-word capability surface.
 *
 * Access as `RunAnywhere.wakeWord.load / detect / unload` — parity
 * with `RunAnywhere.wakeWord` on Swift / Kotlin / Flutter / RN.
 */
export const WakeWord = {
  /**
   * Load a wake-word model from disk (or URL / hash — provider-dependent).
   *
   * Mirrors Swift `RunAnywhere.wakeWord.load(modelPath:)`.
   */
  async load(modelPath: string): Promise<void> {
    const provider = getWakeWordProvider();
    if (typeof provider?.load === 'function') {
      return provider.load(modelPath);
    }
    throw SDKException.backendNotAvailable(
      'wakeWord.load',
      'No wake-word provider registered. The rac_wake_word_* C ABI is ' +
        'currently stubbed in runanywhere-commons.',
    );
  },

  /**
   * Run wake-word detection over a PCM buffer.
   *
   * Mirrors Swift `RunAnywhere.wakeWord.detect(audio:)`. Accepts
   * `Uint8Array` so call sites do not need to depend on WASM memory
   * layout.
   */
  async detect(audio: Uint8Array): Promise<boolean> {
    const provider = getWakeWordProvider();
    if (typeof provider?.detect === 'function') {
      return provider.detect(audio);
    }
    throw SDKException.backendNotAvailable(
      'wakeWord.detect',
      'No wake-word provider registered. The rac_wake_word_* C ABI is ' +
        'currently stubbed in runanywhere-commons.',
    );
  },

  /**
   * Unload the currently loaded wake-word model.
   *
   * Mirrors Swift `RunAnywhere.wakeWord.unload()`. Safe to call when
   * no model is loaded — this no-ops when no provider is registered.
   */
  async unload(): Promise<void> {
    const provider = getWakeWordProvider();
    if (typeof provider?.unload === 'function') {
      return provider.unload();
    }
    // unload is idempotent — no need to throw when nothing is loaded.
  },
};
