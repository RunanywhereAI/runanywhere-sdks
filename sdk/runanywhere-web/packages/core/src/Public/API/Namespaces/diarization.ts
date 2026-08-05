/**
 * `RunAnywhere.diarization` — attribute audio spans to speakers.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { diarize } from '../../Extensions/RunAnywhere+Diarization.js';
import { audioInputToFloat32, type AudioInput } from '../Inputs.js';
import type { DiarizationOptions } from '../Options.js';
import type { DiarizationResult } from '../Results.js';
import { toDiarizationResult, toProtoDiarizationOptions } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

/** Speaker diarization against the resident diarization model. */
export const diarization = {
  /**
   * Split audio into speaker-attributed spans.
   *
   * @throws SDKException when no diarization model is loaded.
   *
   * @example
   * const { speakerCount } = await RunAnywhere.diarization.diarize(
   *   await RunAnywhere.AudioInput.file(pickedFile));
   */
  async diarize(audio: AudioInput, options?: DiarizationOptions): Promise<DiarizationResult> {
    await ensureReady();
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION);
    const samples = await audioInputToFloat32(audio);
    const protoOptions = toProtoDiarizationOptions(options);
    const result = await diarize({
      audioData: new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
      options: { ...protoOptions, sampleRate: audio.format.sampleRate, channels: audio.format.channels ?? 1 },
    });
    return toDiarizationResult(result);
  },
};
