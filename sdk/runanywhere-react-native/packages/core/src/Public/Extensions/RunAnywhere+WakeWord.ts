/**
 * RunAnywhere+WakeWord.ts
 *
 * P2 feature B11 — Wake Word public facade for React Native.
 *
 * The native `rac_wake_word_*` C ABI exists in runanywhere-commons but
 * is currently stubbed (returns RAC_ERROR_FEATURE_NOT_AVAILABLE), and
 * the Nitro modules do NOT yet expose `loadWakeWord / detectWakeWord /
 * unloadWakeWord`. Until the bridge is wired, the exported `wakeWord`
 * namespace surfaces a clear "not available" error rather than
 * failing at link time. The signatures match every other SDK
 * (Swift / Kotlin / Flutter / Web) so the JS contract is stable.
 *
 * Matches Swift: `Public/Extensions/RunAnywhere+WakeWord.swift`.
 */
import { isNativeModuleAvailable, requireNativeModule } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('RunAnywhere.WakeWord');

/** Shape of the Nitro methods that will be wired once commons lands. */
interface WakeWordNativeModule {
  loadWakeWord?: (modelPath: string) => Promise<boolean>;
  detectWakeWord?: (audio: Uint8Array) => Promise<boolean>;
  unloadWakeWord?: () => Promise<void>;
}

function getNativeWakeWord(): WakeWordNativeModule | null {
  if (!isNativeModuleAvailable()) return null;
  return requireNativeModule() as unknown as WakeWordNativeModule;
}

// ============================================================================
// Top-level verbs (mirrors VAD / STT / TTS style in this file)
// ============================================================================

/**
 * Load a wake-word model from disk.
 *
 * Matches Swift SDK: `RunAnywhere.wakeWord.load(modelPath:)`.
 */
export async function loadWakeWord(modelPath: string): Promise<void> {
  const native = getNativeWakeWord();
  if (native && typeof native.loadWakeWord === 'function') {
    const ok = await native.loadWakeWord(modelPath);
    if (!ok) {
      throw new Error(`Failed to load wake-word model: ${modelPath}`);
    }
    return;
  }
  logger.warning(
    `loadWakeWord(${modelPath}): wake-word not wired in commons ` +
      '(rac_wake_word_* is stubbed; no Nitro bridge yet)',
  );
  throw new Error('Wake-word detection is not available yet.');
}

/**
 * Detect a wake word in a PCM buffer.
 *
 * Matches Swift SDK: `RunAnywhere.wakeWord.detect(audio:)`.
 */
export async function detectWakeWord(audio: Uint8Array): Promise<boolean> {
  const native = getNativeWakeWord();
  if (native && typeof native.detectWakeWord === 'function') {
    return native.detectWakeWord(audio);
  }
  logger.warning(
    `detectWakeWord(${audio.length} bytes): wake-word not wired in commons`,
  );
  throw new Error('Wake-word detection is not available yet.');
}

/**
 * Unload the currently loaded wake-word model.
 *
 * Matches Swift SDK: `RunAnywhere.wakeWord.unload()`. Safe to call
 * when no model is loaded.
 */
export async function unloadWakeWord(): Promise<void> {
  const native = getNativeWakeWord();
  if (native && typeof native.unloadWakeWord === 'function') {
    return native.unloadWakeWord();
  }
  logger.debug('unloadWakeWord: no-op (wake-word not wired in commons)');
}

// ============================================================================
// Namespace export — `RunAnywhere.wakeWord.*`
// ============================================================================

/**
 * Wake-word namespace mirroring Swift's `RunAnywhere.wakeWord`.
 *
 * Access either flat (`RunAnywhere.loadWakeWord(path)`) or namespaced
 * (`RunAnywhere.wakeWord.load(path)`).
 */
export const wakeWord = {
  /** Mirror of Swift `RunAnywhere.wakeWord.load(modelPath:)`. */
  load(modelPath: string): Promise<void> {
    return loadWakeWord(modelPath);
  },

  /** Mirror of Swift `RunAnywhere.wakeWord.detect(audio:)`. */
  detect(audio: Uint8Array): Promise<boolean> {
    return detectWakeWord(audio);
  },

  /** Mirror of Swift `RunAnywhere.wakeWord.unload()`. */
  unload(): Promise<void> {
    return unloadWakeWord();
  },
};
