/**
 * `RunAnywhere.diarization` — who spoke when.
 */

import {
  DiarizationRequest,
  DiarizationResult as DiarizationResultMessage,
} from '@runanywhere/proto-ts/diarization';

import { decode, encode, preflight } from './Bridge';
import { toAudioBytes, toDiarizationEncoding } from './Inputs';
import { toDiarizationOptions } from './Options';
import { toDiarizationResult } from './Results';
import type {
  AudioInput,
  DiarizationOptions,
  DiarizationResult,
} from './Types';

/** Speaker diarization over a complete recording. */
export const diarization = {
  /**
   * Split a recording into speaker turns.
   *
   * @example
   * const result = await RunAnywhere.diarization.diarize(AudioInputs.pcm16(bytes));
   * console.log(result.speakerCount);
   *
   * @throws SDKException when no diarization model is loaded or the run fails.
   */
  async diarize(
    audio: AudioInput,
    options?: DiarizationOptions
  ): Promise<DiarizationResult> {
    const native = await preflight();
    const protoOptions = toDiarizationOptions(options);
    protoOptions.encoding = toDiarizationEncoding(audio);
    protoOptions.sampleRate = audio.sampleRate;
    protoOptions.channels = audio.channels;
    const request = DiarizationRequest.fromPartial({
      audioData: toAudioBytes(audio, 'diarization.diarize'),
      options: protoOptions,
    });
    const resultBytes = await native.diarizationDiarizeLifecycleProto(
      encode(request, DiarizationRequest)
    );
    return toDiarizationResult(
      decode(resultBytes, DiarizationResultMessage, 'diarizationDiarize')
    );
  },
};
