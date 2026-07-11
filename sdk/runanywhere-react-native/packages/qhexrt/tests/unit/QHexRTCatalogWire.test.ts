import { HexagonArch } from '@runanywhere/proto-ts/hardware_profile';
import {
  InferenceFramework,
  ModelCategory,
  ModelSource,
  RegisterModelFromUrlRequest,
} from '@runanywhere/proto-ts/model_types';
import { QHexRTCatalogWire } from '../../src/QHexRTCatalogWire';

describe('QHexRT catalog wire contract', () => {
  it('passes generated V75 V79 V81 values to Nitro unchanged', () => {
    expect(
      QHexRTCatalogWire.archValues([
        HexagonArch.HEXAGON_ARCH_V75,
        HexagonArch.HEXAGON_ARCH_V79,
        HexagonArch.HEXAGON_ARCH_V81,
      ])
    ).toEqual([75, 79, 81]);
  });

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
});
