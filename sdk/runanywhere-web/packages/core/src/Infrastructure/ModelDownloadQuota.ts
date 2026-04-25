import type { MetadataMap, OPFSStorage } from './OPFSStorage';
import type { ManagedModel } from './ModelRegistry';
import type { ModelRegistry } from './ModelRegistry';

/** Candidate model that could be evicted to free space. */
export interface EvictionCandidateInfo {
  id: string;
  name: string;
  sizeBytes: number;
  lastUsedAt: number;
}

/** Result of a pre-download quota check. */
export interface QuotaCheckResult {
  /** Whether the model fits in available storage without eviction. */
  fits: boolean;
  /** Currently available bytes (estimate). */
  availableBytes: number;
  /** Total bytes needed for the model (primary + additional files). */
  neededBytes: number;
  /** Candidate models sorted by least-recently-used first. */
  evictionCandidates: EvictionCandidateInfo[];
}

export async function checkModelStorageQuota(
  model: ManagedModel,
  metadata: MetadataMap,
  loadedModelId: string | undefined,
  storage: OPFSStorage,
  registry: ModelRegistry,
): Promise<QuotaCheckResult> {
  const { usedBytes, quotaBytes } = await storage.getStorageUsage();
  const availableBytes = Math.max(0, quotaBytes - usedBytes);
  const neededBytes = model.memoryRequirement ?? 0;

  if (availableBytes >= neededBytes) {
    return { fits: true, availableBytes, neededBytes, evictionCandidates: [] };
  }

  const stored = await storage.listModels();
  const keepBase = model.id.split('__')[0];
  const candidates: EvictionCandidateInfo[] = [];

  for (const storedModel of stored) {
    const storedBase = storedModel.id.split('__')[0];
    if (storedBase === keepBase) continue;
    if (loadedModelId && storedModel.id === loadedModelId) continue;
    if (storedModel.id === '_metadata.json') continue;

    const registered = registry.getModel(storedModel.id) ?? registry.getModel(storedBase);
    candidates.push({
      id: storedBase,
      name: registered?.name ?? storedModel.id,
      sizeBytes: storedModel.sizeBytes,
      lastUsedAt: metadata[storedBase]?.lastUsedAt ?? storedModel.lastModified,
    });
  }

  const deduped = new Map<string, EvictionCandidateInfo>();
  for (const candidate of candidates) {
    const existing = deduped.get(candidate.id);
    if (existing) {
      existing.sizeBytes += candidate.sizeBytes;
    } else {
      deduped.set(candidate.id, { ...candidate });
    }
  }

  const evictionCandidates = [...deduped.values()].sort((a, b) => a.lastUsedAt - b.lastUsedAt);
  return { fits: false, availableBytes, neededBytes, evictionCandidates };
}
