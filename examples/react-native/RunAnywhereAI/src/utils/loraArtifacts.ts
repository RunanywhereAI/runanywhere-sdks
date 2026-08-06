/**
 * loraArtifacts - app-level LoRA adapter download composition.
 *
 * `RunAnywhere.lora.catalog` register/download/registerArtifact convenience
 * verbs were removed outright from the LoRA domain
 * (idl/lora_options.proto: LoraAdapterDownloadCompletedRequest/Result and
 * LoraAdapterImportRequest/Result deleted, "lora-delete-download-import-
 * bookkeeping"). The Swift and Kotlin SDKs each ship an SDK-level
 * `lora.registerArtifact`/`lora.download` convenience that composes the
 * models domain internally (see `sdk/runanywhere-swift/.../
 * RunAnywhere+LoRADownload.swift` and `sdk/runanywhere-kotlin/.../
 * RunAnywhereLoRA.kt`), but the React Native SDK (`@runanywhere/core`) has
 * no equivalent — only the bare catalog register/query/get verbs exist
 * there. This module reproduces the same composition those two SDKs use
 * internally, entirely from the RN SDK's public `models`/`lora.catalog`
 * verbs, so this app doesn't hand-roll its own download bookkeeping:
 *
 *   1. The adapter's bytes are registered as a plain model artifact whose id
 *      is the catalog entry id prefixed with "lora-adapter:" (the same
 *      linking convention `RALoraAdapterCatalogEntry.loraArtifactModelID`
 *      uses on iOS/Android) and tagged "lora-adapter".
 *   2. `RunAnywhere.models.download(...)` runs the canonical download
 *      pipeline (resume/checksum/progress) for that artifact.
 *   3. The resolved `ModelInfo.localPath` is read back from
 *      `RunAnywhere.models.get(...)` — the same source of truth the Swift/
 *      Kotlin SDKs resolve from after their own download call.
 */

import { RunAnywhere } from '@runanywhere/core';
import type { DownloadEvent } from '@runanywhere/core';

const LORA_ARTIFACT_ID_PREFIX = 'lora-adapter:';

/** Stable model-registry id used for a LoRA catalog entry's download artifact. */
export function loraArtifactModelId(catalogEntryId: string): string {
  return catalogEntryId.startsWith(LORA_ARTIFACT_ID_PREFIX)
    ? catalogEntryId
    : `${LORA_ARTIFACT_ID_PREFIX}${catalogEntryId}`;
}

/**
 * Register a LoRA adapter's downloadable bytes as a model artifact, without
 * fetching them. Idempotent — safe to call every time the catalog is seeded.
 */
export async function registerLoraArtifact(params: {
  catalogEntryId: string;
  name: string;
  url: string;
  sizeBytes?: number;
}): Promise<void> {
  await RunAnywhere.models.register({
    id: loraArtifactModelId(params.catalogEntryId),
    name: params.name,
    url: params.url,
    ...(params.sizeBytes !== undefined
      ? { memoryRequirementBytes: params.sizeBytes }
      : {}),
  });
}

/** The on-disk path for a LoRA adapter's artifact, or null if not downloaded. */
export async function getLoraLocalPath(
  catalogEntryId: string
): Promise<string | null> {
  const model = await RunAnywhere.models.get(loraArtifactModelId(catalogEntryId));
  return model?.localPath || null;
}

/**
 * Generic artifact facts for a LoRA adapter — download size, description,
 * and local path — read from the ModelInfo record `registerLoraArtifact`
 * created. `LoraAdapterCatalogEntry` deliberately carries none of this
 * (idl/lora_options.proto: "everything generic about the artifact ... lives
 * on the ModelInfo record for this adapter").
 */
export async function getLoraArtifactInfo(catalogEntryId: string): Promise<{
  localPath: string | null;
  sizeBytes: number;
  description: string;
} | null> {
  const model = await RunAnywhere.models.get(loraArtifactModelId(catalogEntryId));
  if (!model) return null;
  return {
    localPath: model.localPath || null,
    sizeBytes: model.downloadSizeBytes || 0,
    description: model.metadata?.description ?? '',
  };
}

/**
 * Download a registered LoRA adapter's artifact through the canonical
 * model-download pipeline, reporting the same progress shape
 * `RunAnywhere.models.download` reports for any other model.
 *
 * KNOWN SDK GAP (flagged, not worked around): commons only *preserves* a
 * catalog entry's existing `localPath` across `lora.catalog.register`
 * re-registration (`lora_registry.cpp`'s `clear_completion_state` /
 * `preserve_completion_state`) — there is no path through the public
 * `@runanywhere/core` surface that can ever ORIGINATE a fresh `localPath` on
 * a catalog entry from a download; every register call clears it first and
 * only restores a value that was already there. `RunAnywhere.lora.apply
 * (adapterId, scale)` resolves its on-disk path exclusively from that
 * catalog-entry field, so applying a just-downloaded adapter genuinely
 * cannot succeed through the public RN SDK today (Swift/Kotlin sidestep this
 * by taking an explicit `localPath` parameter on their `apply`, which the RN
 * facade does not expose). This function still returns the resolved path —
 * the best a caller can do — so `RunAnywhere.lora.apply` fails loudly with
 * its own SDKException instead of this app inventing a shim around it.
 *
 * @returns the resolved local file path once the download completes.
 * @throws if the download fails or completes without a resolvable path.
 */
export async function downloadLoraArtifact(
  catalogEntryId: string,
  onProgress?: (event: DownloadEvent) => void
): Promise<string> {
  const modelId = loraArtifactModelId(catalogEntryId);
  const iterator = RunAnywhere.models.download(modelId)[Symbol.asyncIterator]();
  try {
    let step = await iterator.next();
    while (!step.done) {
      onProgress?.(step.value);
      if (step.value.type === 'failed') {
        throw step.value.error;
      }
      step = await iterator.next();
    }
  } finally {
    await iterator.return?.();
  }
  const localPath = await getLoraLocalPath(catalogEntryId);
  if (!localPath) {
    throw new Error(
      `LoRA adapter '${catalogEntryId}' downloaded but no local path was recorded`
    );
  }
  return localPath;
}
