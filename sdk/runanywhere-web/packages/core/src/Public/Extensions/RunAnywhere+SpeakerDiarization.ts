/**
 * RunAnywhere+SpeakerDiarization.ts
 *
 * Speaker Diarization (B12, §8) namespace — mirrors Swift's
 * `RunAnywhere+SpeakerDiarization.swift`, Kotlin's
 * `RunAnywhere+SpeakerDiarization.kt`, and Flutter's
 * `RunAnywhereSpeakerDiarization` capability.
 *
 * The C ABI for speaker diarization (`rac_speaker_diarization_init /
 * _process / _destroy`) exists in runanywhere-commons but is currently a
 * stub returning `RAC_ERROR_FEATURE_NOT_AVAILABLE`. There is no WASM
 * export wired through `racommons.js` yet either, so this facade:
 *   - `loadModel` throws `SDKException.backendNotAvailable`
 *   - `diarize` logs a warning and returns an empty array
 *   - `unloadModel` is a no-op
 *
 * TODO(diarization): when commons replaces the stub with a real
 * implementation, also export the three functions from the Emscripten
 * build and call them here via `Module.ccall(...)`. The public shape
 * below stays the same.
 */

import { SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';

const logger = new SDKLogger('SpeakerDiarization');

/**
 * One speaker segment returned by `RunAnywhere.speakerDiarization.diarize(...)`.
 */
export interface SpeakerSegment {
  /** Zero-based speaker index. Stable within a single session. */
  speaker: number;

  /** Segment start time in milliseconds from the start of the audio. */
  startMs: number;

  /** Segment end time in milliseconds from the start of the audio. */
  endMs: number;
}

// Internal mutable state for the stub.
let _loaded = false;

/**
 * Public namespace mirroring Swift's `RunAnywhere.diarize(audio:)` and the
 * Kotlin / Flutter / RN shapes.
 *
 * Apps use it as:
 *   ```ts
 *   const segments = await RunAnywhere.speakerDiarization.diarize(pcm);
 *   ```
 */
export const SpeakerDiarization = {
  /** Whether a diarization model is currently loaded. */
  get isLoaded(): boolean {
    return _loaded;
  },

  /**
   * Load the speaker-diarization model at `modelPath`.
   *
   * Throws `SDKException.backendNotAvailable` while the WASM export / C++
   * implementation is not yet available.
   */
  async loadModel(modelPath: string): Promise<void> {
    logger.warning(
      `loadModel: feature not yet available in commons (stub). modelPath=${modelPath}`,
    );
    throw SDKException.backendNotAvailable(
      'speakerDiarization.loadModel',
      'Speaker diarization is not yet integrated in runanywhere-commons.',
    );
  },

  /**
   * Release the diarization session. No-op while the feature is stubbed.
   */
  async unloadModel(): Promise<void> {
    _loaded = false;
  },

  /**
   * Run speaker diarization on a PCM float32 buffer (16 kHz mono,
   * little-endian, 4 bytes per sample).
   *
   * Returns segments ordered by `startMs`. Returns `[]` while the native
   * feature is stubbed; a warning is logged so the gap is diagnosable.
   */
  async diarize(audio: Uint8Array): Promise<SpeakerSegment[]> {
    logger.warning(
      `diarize: feature not yet available in commons (stub). Returning []. audioBytes=${audio.length}`,
    );
    return [];
  },
};
