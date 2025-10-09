import { WHISPER_WEB_CONSTANTS } from '../constants.js';

export function convertStereoToMono(audioData: AudioBuffer): Float32Array {
  if (audioData.numberOfChannels === 2) {
    const SCALING_FACTOR = Math.sqrt(2);
    const left = audioData.getChannelData(0);
    const right = audioData.getChannelData(1);

    const audio = new Float32Array(left.length);
    for (let i = 0; i < left.length; ++i) {
      audio[i] = (SCALING_FACTOR * (left[i] + right[i])) / 2;
    }
    return audio;
  } else {
    return audioData.getChannelData(0);
  }
}

export function createAudioContext(): AudioContext {
  return new AudioContext({
    sampleRate: WHISPER_WEB_CONSTANTS.SAMPLING_RATE
  });
}
