/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-text namespace — mirrors Swift's `RunAnywhere+STT.swift`.
 * Provides `RunAnywhere.stt.*` capability surface around transcribe.
 */

import type { STTOptions, STTOutput, STTPartialResult } from '@runanywhere/proto-ts/stt_options';
import type { STTTranscriptionResult, STTTranscribeOptions } from '../../types/index';
import { transcribe } from './RunAnywhere+Convenience';
import { SDKException } from '../../Foundation/SDKException';
import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';

export type { STTOptions, STTOutput, STTPartialResult };

/** STT provider interface extensions for model management. */
interface STTModelProvider {
  loadSTTModel?(modelId: string): Promise<void>;
  unloadSTTModel?(): Promise<void>;
  isSTTModelLoaded?: boolean;
  processStreamingAudio?(samples: Uint8Array): Promise<void>;
  stopStreamingTranscription?(): Promise<void>;
  isStreamingSTT?: boolean;
  transcribeStream?(audio: AsyncIterable<Uint8Array>): AsyncIterable<STTPartialResult>;
}

function getSTTProvider(): STTModelProvider | null {
  return ExtensionPoint.getProvider('stt') as STTModelProvider | null;
}

export const STT = {
  async transcribe(
    audio: Float32Array | File,
    options?: STTTranscribeOptions,
  ): Promise<STTTranscriptionResult> {
    return transcribe(audio, options);
  },

  /**
   * Stream transcription from an audio stream (§4). Delegates to the STT
   * provider's `transcribeStream` if available. If the provider does not
   * implement streaming, throws `backendNotAvailable`.
   */
  transcribeStream(audio: AsyncIterable<Uint8Array>): AsyncIterable<STTPartialResult> {
    const provider = getSTTProvider();
    if (typeof provider?.transcribeStream === 'function') {
      return provider.transcribeStream(audio);
    }
    throw SDKException.backendNotAvailable(
      'transcribeStream',
      'The active STT provider does not implement streaming transcription.',
    );
  },

  /** Process a streaming audio chunk (§4). */
  async processStreamingAudio(samples: Uint8Array): Promise<void> {
    const provider = getSTTProvider();
    if (typeof provider?.processStreamingAudio === 'function') {
      return provider.processStreamingAudio(samples);
    }
    throw SDKException.backendNotAvailable(
      'processStreamingAudio',
      'The active STT provider does not implement streaming audio processing.',
    );
  },

  /** Stop streaming transcription (§4). */
  async stopStreamingTranscription(): Promise<void> {
    const provider = getSTTProvider();
    if (typeof provider?.stopStreamingTranscription === 'function') {
      return provider.stopStreamingTranscription();
    }
  },

  /** Whether a streaming STT session is active (§4). */
  get isStreamingSTT(): boolean {
    return getSTTProvider()?.isStreamingSTT ?? false;
  },

  /** Load an STT model by ID (§4). */
  async loadSTTModel(modelId: string): Promise<void> {
    const provider = getSTTProvider();
    if (typeof provider?.loadSTTModel === 'function') {
      return provider.loadSTTModel(modelId);
    }
    throw SDKException.backendNotAvailable(
      'loadSTTModel',
      'No STT provider registered. Install and register @runanywhere/web-onnx.',
    );
  },

  /** Unload the active STT model (§4). */
  async unloadSTTModel(): Promise<void> {
    const provider = getSTTProvider();
    if (typeof provider?.unloadSTTModel === 'function') {
      return provider.unloadSTTModel();
    }
  },

  /** Whether an STT model is currently loaded (§4). */
  get isSTTModelLoaded(): boolean {
    return getSTTProvider()?.isSTTModelLoaded ?? false;
  },
};
