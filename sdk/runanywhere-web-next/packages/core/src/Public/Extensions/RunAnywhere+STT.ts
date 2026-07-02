import {
  type STTOptions as ProtoSTTOptions,
  type STTOutput as ProtoSTTOutput,
  type STTPartialResult as ProtoSTTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import { ModelRegistryAdapter } from '../../Adapters/ModelRegistryAdapter';
import { STTProtoAdapter } from '../../Adapters/STTProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    sttLoadModel(modelId: string): Promise<number>;
    sttDestroy(handle: number): Promise<void>;
    transcribe(handle: number, audio: Uint8Array, options: ProtoSTTOptions): Promise<ProtoSTTOutput | null>;
    transcribeStream(handle: number, audio: Uint8Array, options: ProtoSTTOptions): AsyncIterable<ProtoSTTPartialResult>;
  }
}

function stt(): STTProtoAdapter {
  const adapter = STTProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('STT');
  return adapter;
}

// Create an STT component in the STT worker and load the model from its
// on-device path. Sherpa STT models are framework=SHERPA and self-heal in the
// onnx/sherpa worker (the same worker STT runs in), so the local path is read
// from that worker's registry.
RunAnywhereSDK.prototype.sttLoadModel = async function (this: RunAnywhereSDK, modelId) {
  this.ensureInitialized();
  const model = await ModelRegistryAdapter.tryDefaultFor('stt')?.get(modelId);
  const modelPath = model?.localPath;
  if (!modelPath) {
    throw SDKException.processingFailed(`STT model '${modelId}' is not downloaded (no local path)`);
  }
  const adapter = stt();
  const handle = await adapter.createComponent();
  try {
    await adapter.loadModel(handle, modelPath, modelId, model?.name ?? modelId);
  } catch (err) {
    await adapter.destroy(handle);
    throw err;
  }
  return handle;
};

RunAnywhereSDK.prototype.sttDestroy = async function (this: RunAnywhereSDK, handle) {
  await stt().destroy(handle);
};

RunAnywhereSDK.prototype.transcribe = function (this: RunAnywhereSDK, handle, audio, options) {
  this.ensureInitialized();
  return stt().transcribe(handle, audio, options);
};

RunAnywhereSDK.prototype.transcribeStream = function (this: RunAnywhereSDK, handle, audio, options) {
  this.ensureInitialized();
  return stt().transcribeStream(handle, audio, options);
};
