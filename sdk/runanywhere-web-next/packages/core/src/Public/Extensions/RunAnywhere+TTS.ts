import {
  type TTSOptions as ProtoTTSOptions,
  type TTSOutput as ProtoTTSOutput,
  type TTSVoiceInfo as ProtoTTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
import { ModelRegistryAdapter } from '../../Adapters/ModelRegistryAdapter';
import { TTSProtoAdapter } from '../../Adapters/TTSProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    ttsLoadModel(modelId: string): Promise<number>;
    ttsDestroy(handle: number): Promise<void>;
    listVoices(handle: number): Promise<ProtoTTSVoiceInfo[]>;
    synthesize(handle: number, text: string, options: ProtoTTSOptions): Promise<ProtoTTSOutput | null>;
    synthesizeStream(handle: number, text: string, options: ProtoTTSOptions): AsyncIterable<ProtoTTSOutput>;
  }
}

function tts(): TTSProtoAdapter {
  const adapter = TTSProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('TTS');
  return adapter;
}

// Create a TTS component in the TTS worker and load the voice from the model's
// on-device path. The path lives in the TTS worker's registry (that is where
// the model was downloaded + self-healed), so it is read from that worker.
RunAnywhereSDK.prototype.ttsLoadModel = async function (this: RunAnywhereSDK, modelId) {
  this.ensureInitialized();
  const model = await ModelRegistryAdapter.tryDefaultFor('tts')?.get(modelId);
  const voicePath = model?.localPath;
  if (!voicePath) {
    throw SDKException.processingFailed(`TTS model '${modelId}' is not downloaded (no local path)`);
  }
  const adapter = tts();
  const handle = await adapter.createComponent();
  try {
    await adapter.loadVoice(handle, voicePath, modelId, model?.name ?? modelId);
  } catch (err) {
    await adapter.destroy(handle);
    throw err;
  }
  return handle;
};

RunAnywhereSDK.prototype.ttsDestroy = async function (this: RunAnywhereSDK, handle) {
  await tts().destroy(handle);
};

RunAnywhereSDK.prototype.listVoices = function (this: RunAnywhereSDK, handle) {
  this.ensureInitialized();
  return tts().listVoices(handle);
};

RunAnywhereSDK.prototype.synthesize = function (this: RunAnywhereSDK, handle, text, options) {
  this.ensureInitialized();
  return tts().synthesize(handle, text, options);
};

RunAnywhereSDK.prototype.synthesizeStream = function (this: RunAnywhereSDK, handle, text, options) {
  this.ensureInitialized();
  return tts().synthesizeStream(handle, text, options);
};
