// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// PlatformBridge — transport-neutral interface that @runanywhere/core
// (React Native) and @runanywhere/web implementations fulfill. The
// public adapter (Auth / Telemetry / ModelHelpers / Rag / FileIntegrity)
// calls the currently-registered bridge; the bridge is the one that
// owns the actual ra_* C ABI (via Nitro JSI or WASM cwrap).

/** Surface of methods that platform bridges must implement. */
export interface PlatformBridge {
  // Auth (ra_auth.h)
  authIsAuthenticated(): boolean;
  authNeedsRefresh(horizonSeconds?: number): boolean;
  authGetAccessToken(): string;
  authGetRefreshToken(): string;
  authGetDeviceId(): string;
  authBuildAuthenticateRequest(apiKey: string, deviceId: string): string;
  authHandleAuthenticateResponse(body: string): boolean;
  authHandleRefreshResponse(body: string): boolean;
  authClear(): void;

  // Telemetry (ra_telemetry.h)
  telemetryTrack(event: string, propertiesJson?: string): boolean;
  telemetryFlush(): boolean;
  telemetryDefaultPayloadJson(): string;

  // Model helpers (ra_model.h)
  modelFrameworkSupports(framework: string, category: string): boolean;
  modelDetectFormat(urlOrPath: string): number;
  modelInferCategory(modelId: string): number;
  modelIsArchive(urlOrPath: string): boolean;

  // RAG (ra_rag.h)
  ragStoreCreate(dim: number): number;       // returns opaque handle (bigint-compatible)
  ragStoreDestroy(handle: number): void;
  ragStoreSize(handle: number): number;
  ragStoreAdd(handle: number, rowId: string, metadataJson: string,
                embedding: Float32Array): boolean;
  ragStoreSearch(handle: number, query: Float32Array,
                   topK: number): Array<{ id: string; metadataJson: string; score: number }>;

  // Download integrity (ra_download.h)
  sha256File(path: string): string | null;
  verifySha256(path: string, expectedHex: string): boolean;
}

/// Currently-registered bridge (null when running in a host that hasn't
/// wired one up — SDK falls back to JS-only stubs).
let _registered: PlatformBridge | null = null;

export function setPlatformBridge(bridge: PlatformBridge | null): void {
  _registered = bridge;
}

export function getPlatformBridge(): PlatformBridge | null {
  return _registered;
}

/** Thrown when a public adapter method needs a bridge but none is registered. */
export class MissingPlatformBridgeError extends Error {
  constructor(method: string) {
    super(`PlatformBridge not registered; cannot call ${method}. ` +
          `In React Native install @runanywhere/core and call setPlatformBridge(). ` +
          `In Web use @runanywhere/core-web which wires up the WASM bridge on init.`);
    this.name = 'MissingPlatformBridgeError';
  }
}
