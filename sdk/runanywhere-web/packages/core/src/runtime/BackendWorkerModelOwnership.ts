/**
 * Tracks LLM models loaded exclusively in the BackendWorker so main-thread
 * adapters can skip duplicate GGUF loads while still reporting ownership.
 *
 * @internal
 */

const workerOwnedModels = new Set<string>();

export function markModelOwnedByBackendWorker(modelId: string): void {
  if (!modelId) return;
  workerOwnedModels.add(modelId);
}

export function clearModelOwnedByBackendWorker(modelId?: string): void {
  if (!modelId) {
    workerOwnedModels.clear();
    return;
  }
  workerOwnedModels.delete(modelId);
}

export function isModelOwnedByBackendWorker(modelId: string): boolean {
  return Boolean(modelId) && workerOwnedModels.has(modelId);
}

export function hasBackendWorkerOwnedModels(): boolean {
  return workerOwnedModels.size > 0;
}
