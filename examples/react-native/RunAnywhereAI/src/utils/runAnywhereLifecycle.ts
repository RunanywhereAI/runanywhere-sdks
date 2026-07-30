import { RunAnywhere } from '@runanywhere/core';
import type { ModelCategory } from '@runanywhere/proto-ts/model_types';

export async function isModelLoadedForCategory(
  category: ModelCategory
): Promise<boolean> {
  const model = await RunAnywhere.models.loaded(category);
  return (model?.id.length ?? 0) > 0;
}

export async function unloadModelsForCategory(
  category: ModelCategory
): Promise<void> {
  await RunAnywhere.models.unload(category);
}
