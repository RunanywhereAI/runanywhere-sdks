/**
 * Multi-backend BackendWorker host registry.
 *
 * LlamaCPP and ONNX each own a DedicatedWorker. Adapters resolve the host by
 * backend id so speech and LLM inference never share a single WASM heap.
 *
 * @internal
 */

import type { BackendWorkerBackendId } from './BackendWorkerProtocol.js';
import type { BackendWorkerHost } from './BackendWorkerHost.js';
import type { BackendWorkerDiagnostics } from './BackendWorkerProtocol.js';

const hosts = new Map<BackendWorkerBackendId, BackendWorkerHost>();

export function setBackendWorkerHost(
  backendId: BackendWorkerBackendId,
  host: BackendWorkerHost | null,
): void {
  if (!host) {
    hosts.delete(backendId);
    return;
  }
  hosts.set(backendId, host);
}

export function getBackendWorkerHost(
  backendId: BackendWorkerBackendId,
): BackendWorkerHost | null {
  return hosts.get(backendId) ?? null;
}

/** Aggregate diagnostics: worker if any backend host is in worker context. */
export function getRegisteredBackendWorkerDiagnostics(): BackendWorkerDiagnostics {
  let queueDepth = 0;
  let anyWorker = false;
  for (const host of hosts.values()) {
    const d = host.diagnostics;
    queueDepth += d.queueDepth;
    if (d.executionContext === 'worker') anyWorker = true;
  }
  return {
    executionContext: anyWorker ? 'worker' : 'main',
    queueDepth,
  };
}

export function clearAllBackendWorkerHosts(): void {
  for (const host of [...hosts.values()]) {
    try {
      host.dispose();
    } catch {
      /* ignore */
    }
  }
  hosts.clear();
}
