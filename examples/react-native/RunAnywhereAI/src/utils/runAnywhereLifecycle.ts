import { RunAnywhere } from '@runanywhere/core';
import type { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  CurrentModelRequest,
  ModelUnloadRequest,
} from '@runanywhere/proto-ts/model_types';

export async function isModelLoadedForCategory(
  category: ModelCategory
): Promise<boolean> {
  const result = await RunAnywhere.currentModel(
    CurrentModelRequest.fromPartial({
      category,
      includeModelMetadata: false,
    })
  );
  return result?.found === true && result.modelId.length > 0;
}

export async function unloadModelsForCategory(
  category: ModelCategory
): Promise<void> {
  await RunAnywhere.unloadModel(
    ModelUnloadRequest.fromPartial({
      category,
      unloadAll: true,
    })
  );
}
