import {
  InferenceFramework,
  ModelCategory,
  ModelInfo,
  ModelSource,
  RegisterModelFromUrlRequest,
} from '@runanywhere/proto-ts/model_types';
import { QHexRTCatalogWire } from '../../src/QHexRTCatalogWire';

describe('QHexRT catalog wire contract', () => {
  it('passes the model definition as canonical proto bytes', () => {
    const request = RegisterModelFromUrlRequest.fromPartial({
      id: 'catalog-contract-model',
      name: 'Catalog Contract Model',
      url: 'https://huggingface.co/runanywhere/catalog-contract-model_HNPU/model.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      source: ModelSource.MODEL_SOURCE_REMOTE,
    });

    const encoded = QHexRTCatalogWire.encodeRequest(request);
    const decoded = RegisterModelFromUrlRequest.decode(new Uint8Array(encoded));

    expect(Buffer.from(encoded).toString('hex')).toBe(
      '0a4968747470733a2f2f68756767696e67666163652e636f2f72756e616e7977686572652f636174616c6f672d636f6e74726163742d6d6f64656c5f484e50552f6d6f64656c2e6a736f6e1216436174616c6f6720436f6e7472616374204d6f64656c1818200128016a16636174616c6f672d636f6e74726163742d6d6f64656c'
    );
    expect(decoded).toEqual(request);
  });

  it('preserves device-registration capability metadata for native QHexRT', () => {
    const request = RegisterModelFromUrlRequest.fromPartial({
      id: 'qwen3_5_0_8b',
      name: 'Qwen3.5 0.8B (HNPU)',
      url: 'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      source: ModelSource.MODEL_SOURCE_REMOTE,
      memoryRequiredBytes: 2_046_527_848,
      downloadSizeBytes: 2_046_527_848,
      contextLength: 1_024,
      supportsThinking: true,
      supportsLora: false,
      description: 'Qualcomm Hexagon NPU model bundle.',
    });

    const decoded = RegisterModelFromUrlRequest.decode(
      new Uint8Array(QHexRTCatalogWire.encodeRequest(request))
    );

    expect(decoded).toEqual(request);
  });

  it('decodes the exact model id returned by native registration', () => {
    const saved = ModelInfo.fromPartial({
      id: 'internvl3_5_1b',
      name: 'InternVL3.5 1B (HNPU)',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      contextLength: 512,
    });
    const bytes = ModelInfo.encode(saved).finish();
    const buffer = bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength
    ) as ArrayBuffer;

    expect(QHexRTCatalogWire.decodeModel(buffer)).toEqual(saved);
  });
});
