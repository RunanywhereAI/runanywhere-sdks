/**
 * Tracks LLM models loaded exclusively in the BackendWorker so main-thread
 * adapters can skip duplicate GGUF loads while still reporting ownership.
 *
 * @internal
 */

export interface BackendWorkerOwnedModel {
  modelId: string;
  loadedAtUnixMs: number;
  backendId: 'llamacpp' | 'onnx';
}

const workerOwnedModels = new Map<string, BackendWorkerOwnedModel>();
/** When true, LLM/VLM must not fall back to main-thread WASM. */
let llamaWorkerRequired = false;
/** Sticky failure after a required worker crash until a successful re-init. */
let llamaWorkerDeadReason: string | null = null;
/** Llama model ids owned at the last crash — used to reload after CPU fallback. */
let lastLlamaOwnedModelIds: string[] = [];

export function setLlamaBackendWorkerRequired(required: boolean): void {
  llamaWorkerRequired = required;
  if (!required) llamaWorkerDeadReason = null;
}

export function isLlamaBackendWorkerRequired(): boolean {
  return llamaWorkerRequired;
}

export function markLlamaBackendWorkerDead(reason: string): void {
  llamaWorkerDeadReason = reason;
  lastLlamaOwnedModelIds = [...workerOwnedModels.values()]
    .filter((model) => model.backendId === 'llamacpp')
    .map((model) => model.modelId);
  // Clear only llama ownership; ONNX speech models may still be alive in
  // their own BackendWorker.
  for (const [id, model] of workerOwnedModels) {
    if (model.backendId === 'llamacpp') workerOwnedModels.delete(id);
  }
}

/** Consume llama model ids that were loaded when the worker last crashed. */
export function takeLastLlamaOwnedModelIdsForRecovery(): string[] {
  const ids = lastLlamaOwnedModelIds;
  lastLlamaOwnedModelIds = [];
  return ids;
}

export function clearLlamaBackendWorkerDead(): void {
  llamaWorkerDeadReason = null;
}

export function getLlamaBackendWorkerDeadReason(): string | null {
  return llamaWorkerDeadReason;
}

/** True when generate must use the worker or throw (no main-thread fallback). */
export function mustUseLlamaBackendWorker(): boolean {
  // Only llama-owned models force the LLM worker path. ONNX STT/TTS/VAD
  // ownership must not make chat refuse the main-thread llama bridge.
  return (
    llamaWorkerRequired
    || hasBackendWorkerOwnedModels('llamacpp')
    || llamaWorkerDeadReason != null
  );
}

export function markModelOwnedByBackendWorker(
  modelId: string,
  backendId: 'llamacpp' | 'onnx' = 'llamacpp',
): void {
  if (!modelId) return;
  llamaWorkerDeadReason = null;
  workerOwnedModels.set(modelId, {
    modelId,
    loadedAtUnixMs: Date.now(),
    backendId,
  });
}

export function clearModelOwnedByBackendWorker(
  modelId?: string,
  backendId: 'llamacpp' | 'onnx' = 'llamacpp',
): void {
  if (!modelId) {
    for (const [id, model] of workerOwnedModels) {
      if (model.backendId === backendId) workerOwnedModels.delete(id);
    }
    return;
  }
  if (workerOwnedModels.get(modelId)?.backendId === backendId) {
    workerOwnedModels.delete(modelId);
  }
}

export function isModelOwnedByBackendWorker(
  modelId: string,
  backendId: 'llamacpp' | 'onnx' = 'llamacpp',
): boolean {
  const model = workerOwnedModels.get(modelId);
  return Boolean(modelId) && model?.backendId === backendId;
}

/** BackendWorker that currently owns `modelId`, if any. */
export function getBackendWorkerOwner(
  modelId: string,
): 'llamacpp' | 'onnx' | null {
  if (!modelId) return null;
  return workerOwnedModels.get(modelId)?.backendId ?? null;
}

export function hasBackendWorkerOwnedModels(
  backendId: 'llamacpp' | 'onnx' = 'llamacpp',
): boolean {
  return [...workerOwnedModels.values()].some((model) => model.backendId === backendId);
}

/** Snapshot of models currently loaded inside the BackendWorker. */
export function listBackendWorkerOwnedModels(): BackendWorkerOwnedModel[] {
  return [...workerOwnedModels.values()];
}
