jest.mock('@runanywhere/core', () => ({
  RunAnywhere: {
    downloadedModels: jest.fn(),
    listModels: jest.fn(),
  },
}));

import { RunAnywhere } from '@runanywhere/core';
import {
  InferenceFramework,
  ModelInfo,
  ModelInfoList,
  ModelListResult,
} from '@runanywhere/proto-ts/model_types';
import {
  listDownloadedCatalogModels,
  listVisibleCatalogModels,
} from '../../src/services/ModelRegistryQueries';
import { publishNpuCatalogAcceptance } from '../../src/services/NpuModelCatalog';

const listModelsMock = jest.mocked(RunAnywhere.listModels);
const downloadedModelsMock = jest.mocked(RunAnywhere.downloadedModels);

describe('visible model registry query', () => {
  it('filters direct and preferred QHexRT rows before consumers receive them', async () => {
    const ordinary = ModelInfo.fromPartial({
      id: 'ordinary',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    });
    const accepted = ModelInfo.fromPartial({
      id: 'accepted',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    });
    const stale = ModelInfo.fromPartial({
      id: 'stale',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    });
    const stalePreferred = ModelInfo.fromPartial({
      id: 'stale-preferred',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      preferredFramework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    });
    publishNpuCatalogAcceptance(['accepted']);
    const result = ModelListResult.fromPartial({
      success: true,
      models: ModelInfoList.fromPartial({
        models: [ordinary, accepted, stale, stalePreferred],
      }),
    });
    listModelsMock.mockResolvedValue(result);
    downloadedModelsMock.mockResolvedValue(result);

    await expect(listVisibleCatalogModels()).resolves.toEqual([
      ordinary,
      accepted,
    ]);
    // Storage cleanup deliberately retains stale/unaccepted QHexRT rows so
    // users can delete orphaned on-disk models after a catalog/device change.
    await expect(listDownloadedCatalogModels()).resolves.toEqual([
      ordinary,
      accepted,
      stale,
      stalePreferred,
    ]);
  });
});
