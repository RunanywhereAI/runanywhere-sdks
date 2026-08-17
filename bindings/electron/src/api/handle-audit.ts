// handle-audit.ts — Cross-reference native handle audit data against known
// NativeBackend slots to detect handles loaded outside the normal load path
// (direct C++ calls, old handles from crashed renderers).

import type { NativeAddon } from '../bridge';

/** One entry returned by native handleAudit(). */
export interface HandleAuditEntry {
  id: number;
  category: string;
  model?: string;
}

/** Slot types that carry a native handle in NativeBackend. */
export const SLOT_TYPES = [
  'llm',
  'vlm',
  'stt',
  'tts',
  'embedder',
  'rerank',
  'diarization',
  'segmentation',
] as const;

type LoadSlotHandle = (typeof SLOT_TYPES)[number];

/** All handle-bearing slots plus special collections. */
export interface KnownHandleSet {
  /** Slot -> handle mapping, equivalent to NativeBackend.slots. */
  slotHandles: Map<LoadSlotHandle, number>;
  /** Single VAD handle. null when not loaded. */
  vadHandle: number | null;
  /** RAG session id -> native handle. */
  ragSessions: ReadonlyMap<string, number>;
  /** Voice session id -> native handle. */
  voiceSessions: ReadonlyMap<string, number>;
}

export interface HandleLeak {
  entry: HandleAuditEntry;
  source: string;
  details?: string;
}

/**
 * Reports leaked handles: entries present in the native audit table but not
 * accounted for by any known slot (slotHandles, vadHandle, ragSessions, voiceSessions).
 */
export function detectLeaks(
  audit: HandleAuditEntry[],
  known: KnownHandleSet,
): HandleLeak[] {
  const knownIds = new Set<number>();

  for (const h of known.slotHandles.values()) knownIds.add(h);
  if (known.vadHandle !== null) knownIds.add(known.vadHandle);
  for (const h of known.ragSessions.values()) knownIds.add(h);
  for (const h of known.voiceSessions.values()) knownIds.add(h);

  const leaks: HandleLeak[] = [];
  for (const entry of audit) {
    if (!knownIds.has(entry.id)) {
      leaks.push({
        entry,
        source: 'native_audit_only',
        details: `handle ${entry.id} (${entry.category}) found in native audit but not in any known slot`,
      });
    }
  }
  return leaks;
}

/**
 * HandleAuditor — periodic cross-reference of NativeBackend slots against
 * the native addon's handle audit table.
 */
export class HandleAuditor {
  private intervalId: ReturnType<typeof setInterval> | null = null;
  private previousAudit: HandleAuditEntry[] = [];
  private readonly addon: NativeAddon;
  private enabled = false;

  constructor(addon: NativeAddon) {
    this.addon = addon;
  }

  /** Start periodic audit sync. */
  start(intervalMs = 5000): void {
    if (this.intervalId) return;
    this.enabled = true;
    this.intervalId = setInterval(() => {
      try {
        this.sync();
      } catch {
        // Non-fatal: addon may be in teardown.
      }
    }, intervalMs);
  }

  /** Stop periodic audit sync. */
  stop(): void {
    this.enabled = false;
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  /** Query native addon and compare against known handles. Returns detected leaks. */
  getLeaks(known: KnownHandleSet): HandleLeak[] {
    const audit = this.queryNative();
    return detectLeaks(audit, known);
  }

  /** Query the native handleAudit() export. */
  private queryNative(): HandleAuditEntry[] {
    if (typeof this.addon.handleAudit !== 'function') return [];
    const raw = this.addon.handleAudit();
    if (!Array.isArray(raw)) return [];
    return raw as unknown as HandleAuditEntry[];
  }

  /** Print a summary of audit changes. */
  report(label = 'handle-audit'): void {
    const audit = this.queryNative();
    const added = audit.filter((a) => !this.previousAudit.some((p) => p.id === a.id));
    const removed = this.previousAudit.filter((p) => !audit.some((a) => a.id === p.id));

    if (added.length || removed.length) {
      const parts: string[] = [`[${label}] audit delta: +${added.length} / -${removed.length}`];
      for (const a of added) {
        parts.push(`  + handle ${a.id} (${a.category}${a.model ? ` model=${a.model}` : ''})`);
      }
      for (const r of removed) {
        parts.push(`  - handle ${r.id} (${r.category})`);
      }
      console.warn(parts.join('\n'));
    }

    this.previousAudit = audit;
  }

  private sync(): void {
    this.report('handle-audit');
  }
}
