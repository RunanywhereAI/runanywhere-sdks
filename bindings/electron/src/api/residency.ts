// residency.ts — how many models may stay in memory at once.
//
// The backend keeps one slot per modality and nothing evicts anything else on
// its own: chat loads a language model, captioning loads a VLM on top of it, a
// voice turn adds speech-to-text and text-to-speech. Left alone the process
// accumulates every model it has ever touched.
//
// The rule here is memory, not screens. A resident model is only released when
// the machine cannot fit the incoming one, and the verdict comes from commons —
// `rac_model_compatibility_check_proto` reads the model's requirement out of the
// registry and compares it against the RAM the platform adapter reports. When a
// registry row carries no memory requirement commons answers "fits", so the
// policy does nothing rather than guessing.

import { SDKException } from '../errors';
import type { RaBackend } from './backend';
import type { ModelAbi } from './model-abi';
import type { ModelCategory, ModelCompatibility } from './types';

/** A model holding a slot right now. */
export interface ResidentModel {
  category: ModelCategory;
  id: string;
}

/** What a residency check decided, and what it cost. */
export interface ResidencyDecision {
  /** Whether commons believes the incoming model fits once eviction is done. */
  fits: boolean;
  /** Models released to make room, in the order they were released. */
  evicted: ResidentModel[];
  /** RAM the model needs, per its registry row. Zero means the row does not say. */
  requiredBytes: number;
  /** RAM the platform adapter reported free at the last check. */
  availableBytes: number;
  /** Commons' explanation when the verdict is still negative. */
  reasons: string[];
}

/** The memory half of a compatibility verdict, in the shape a load reports. */
function decisionOf(
  verdict: ModelCompatibility,
  evicted: ResidentModel[]
): ResidencyDecision {
  return {
    fits: verdict.canRun,
    evicted,
    requiredBytes: verdict.requiredMemoryBytes,
    availableBytes: verdict.availableMemoryBytes,
    reasons: verdict.reasons,
  };
}

/** The policy's view of what is loaded and how to release it. */
export interface ResidencySlots {
  resident(): Promise<ResidentModel[]>;
  release(model: ResidentModel): Promise<void>;
}

/**
 * Decide whether a model can become resident, releasing others when it cannot.
 *
 * `keep` names the categories the caller still needs alongside the incoming one
 * — a voice turn passes speech-to-text and text-to-speech so answering out loud
 * does not evict the microphone. The incoming category is always kept.
 */
export class ResidencyPolicy {
  constructor(
    private readonly backend: RaBackend,
    private readonly abi: ModelAbi,
    private readonly slots: ResidencySlots
  ) {}

  async admit(
    modelId: string,
    category: ModelCategory,
    keep: readonly ModelCategory[] = []
  ): Promise<ResidencyDecision> {
    const evicted: ResidentModel[] = [];
    let verdict = await this.check(modelId);
    if (verdict.canRun) return decisionOf(verdict, evicted);

    const keepSet = new Set<ModelCategory>([category, ...keep]);
    for (const victim of await this.releaseOrder(keepSet)) {
      await this.slots.release(victim);
      evicted.push(victim);
      verdict = await this.check(modelId);
      if (verdict.canRun) break;
    }
    return decisionOf(verdict, evicted);
  }

  /**
   * What commons says about `modelId` against the machine as it stands now.
   *
   * The whole verdict, not just the memory half: `models.compatibility(id)` is
   * this same call, so the RAM and disk probes have one place to happen rather
   * than two that can disagree.
   */
  async check(modelId: string): Promise<ModelCompatibility> {
    const [memory, storage] = await Promise.all([
      this.backend.memoryInfo(),
      this.backend.storage(),
    ]);
    const result = await this.abi.compatibility({
      modelId,
      availableRamBytes: memory.availableBytes,
      availableStorageBytes: storage.freeBytes,
    });
    if (result.error) throw SDKException.fromProto(result.error);
    return {
      compatible: result.isCompatible,
      canRun: result.canRun,
      canFit: result.canFit,
      requiredMemoryBytes: result.requiredMemoryBytes,
      availableMemoryBytes: result.availableMemoryBytes,
      requiredStorageBytes: result.requiredStorageBytes,
      availableStorageBytes: result.availableStorageBytes,
      reasons: result.reasons,
    };
  }

  // Biggest first: download size is the only footprint number a registry row is
  // guaranteed to carry, and releasing the largest occupant frees the most
  // memory for the fewest evictions. An unknown size sorts last.
  private async releaseOrder(keep: Set<ModelCategory>): Promise<ResidentModel[]> {
    const candidates = (await this.slots.resident()).filter((m) => !keep.has(m.category));
    const sized = await Promise.all(
      candidates.map(async (model) => ({ model, bytes: await this.footprintOf(model.id) }))
    );
    return sized.sort((a, b) => b.bytes - a.bytes).map((entry) => entry.model);
  }

  private async footprintOf(modelId: string): Promise<number> {
    const row = await this.abi.get(modelId).catch(() => null);
    return row?.downloadSizeBytes ?? 0;
  }
}
