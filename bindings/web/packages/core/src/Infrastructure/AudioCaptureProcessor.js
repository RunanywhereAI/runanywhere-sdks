/**
 * Audio render-thread processor for AudioCapture.
 *
 * This file is intentionally JavaScript: AudioWorklet loads it directly in a
 * separate global scope, both from the published package and through browser
 * bundlers. Keeping it as executable JavaScript prevents a bundler from
 * treating uncompiled TypeScript as a static asset.
 */

/* global AudioWorkletProcessor, registerProcessor */

const AUDIO_CAPTURE_PROCESSOR_NAME = 'runanywhere-audio-capture';

/**
 * @typedef {{ processorOptions?: { chunkSize?: unknown } }}
 * AudioCaptureProcessorConstructionOptions
 */

class AudioCaptureProcessor extends AudioWorkletProcessor {
  /** @param {AudioCaptureProcessorConstructionOptions} options */
  constructor(options) {
    super();
    const chunkSize = options?.processorOptions?.chunkSize;
    if (typeof chunkSize !== 'number' || !Number.isInteger(chunkSize) || chunkSize <= 0) {
      throw new TypeError('Audio capture chunkSize must be a positive integer');
    }
    this.chunkSize = chunkSize;
    this.chunk = new Float32Array(chunkSize);
    this.chunkOffset = 0;
  }

  /**
   * @param {Float32Array[][]} inputs
   * @returns {boolean}
   */
  process(inputs) {
    const input = inputs[0]?.[0];
    if (!input || input.length === 0) return true;

    let inputOffset = 0;
    while (inputOffset < input.length) {
      const sampleCount = Math.min(
        input.length - inputOffset,
        this.chunkSize - this.chunkOffset,
      );
      this.chunk.set(input.subarray(inputOffset, inputOffset + sampleCount), this.chunkOffset);
      inputOffset += sampleCount;
      this.chunkOffset += sampleCount;

      if (this.chunkOffset === this.chunkSize) {
        this.port.postMessage(this.chunk, [this.chunk.buffer]);
        this.chunk = new Float32Array(this.chunkSize);
        this.chunkOffset = 0;
      }
    }

    return true;
  }
}

registerProcessor(AUDIO_CAPTURE_PROCESSOR_NAME, AudioCaptureProcessor);
