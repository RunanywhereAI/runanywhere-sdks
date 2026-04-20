// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Public adapters over PlatformBridge — mirror the Swift/Kotlin/Dart
// helper namespaces so sample-app code ports 1:1 across platforms.

import { getPlatformBridge, MissingPlatformBridgeError } from './PlatformBridge.js';

// MARK: - Telemetry

export const Telemetry = {
  /** Track a named event with optional JSON-stringified properties. */
  track(event: string, propertiesJson: string = '{}'): boolean {
    const b = getPlatformBridge();
    if (!b) throw new MissingPlatformBridgeError('Telemetry.track');
    return b.telemetryTrack(event, propertiesJson);
  },

  flush(): boolean {
    const b = getPlatformBridge();
    if (!b) throw new MissingPlatformBridgeError('Telemetry.flush');
    return b.telemetryFlush();
  },

  defaultPayloadJson(): string {
    const b = getPlatformBridge();
    if (!b) return '{}';  // pure-JS fallback for unit tests
    return b.telemetryDefaultPayloadJson();
  },
};

// MARK: - Auth

export const Auth = {
  get isAuthenticated(): boolean {
    return getPlatformBridge()?.authIsAuthenticated() ?? false;
  },

  needsRefresh(horizonSeconds: number = 60): boolean {
    return getPlatformBridge()?.authNeedsRefresh(horizonSeconds) ?? false;
  },

  get accessToken(): string  { return getPlatformBridge()?.authGetAccessToken()  ?? ''; },
  get refreshToken(): string { return getPlatformBridge()?.authGetRefreshToken() ?? ''; },
  get deviceId(): string     { return getPlatformBridge()?.authGetDeviceId()     ?? ''; },

  buildAuthenticateRequest(apiKey: string, deviceId: string): string {
    const b = getPlatformBridge();
    if (!b) throw new MissingPlatformBridgeError('Auth.buildAuthenticateRequest');
    return b.authBuildAuthenticateRequest(apiKey, deviceId);
  },

  handleAuthenticateResponse(body: string): boolean {
    const b = getPlatformBridge();
    if (!b) throw new MissingPlatformBridgeError('Auth.handleAuthenticateResponse');
    return b.authHandleAuthenticateResponse(body);
  },

  handleRefreshResponse(body: string): boolean {
    const b = getPlatformBridge();
    if (!b) throw new MissingPlatformBridgeError('Auth.handleRefreshResponse');
    return b.authHandleRefreshResponse(body);
  },

  clear(): void { getPlatformBridge()?.authClear(); },
};

// MARK: - Model helpers

export const ModelHelpers = {
  frameworkSupports(framework: string, category: string): boolean {
    return getPlatformBridge()?.modelFrameworkSupports(framework, category) ?? false;
  },

  detectFormat(urlOrPath: string): number {
    return getPlatformBridge()?.modelDetectFormat(urlOrPath) ?? 0;
  },

  inferCategory(modelId: string): number {
    return getPlatformBridge()?.modelInferCategory(modelId) ?? 0;
  },

  isArchive(urlOrPath: string): boolean {
    return getPlatformBridge()?.modelIsArchive(urlOrPath) ?? false;
  },
};

// MARK: - File integrity

export const FileIntegrity = {
  /** Hex SHA-256 of a file, or null on I/O error. */
  sha256(path: string): string | null {
    return getPlatformBridge()?.sha256File(path) ?? null;
  },

  verify(path: string, expectedHex: string): boolean {
    return getPlatformBridge()?.verifySha256(path, expectedHex) ?? false;
  },
};

// MARK: - RAG

export class RagStore {
  constructor(private handle: number) {}

  get size(): number {
    return getPlatformBridge()?.ragStoreSize(this.handle) ?? 0;
  }

  add(rowId: string, embedding: Float32Array, metadataJson: string = '{}'): boolean {
    return getPlatformBridge()?.ragStoreAdd(
      this.handle, rowId, metadataJson, embedding) ?? false;
  }

  search(query: Float32Array, topK: number = 6):
      Array<{ id: string; metadataJson: string; score: number }> {
    return getPlatformBridge()?.ragStoreSearch(this.handle, query, topK) ?? [];
  }

  close(): void {
    getPlatformBridge()?.ragStoreDestroy(this.handle);
  }

  static create(dim: number): RagStore | null {
    const b = getPlatformBridge();
    if (!b) return null;
    const h = b.ragStoreCreate(dim);
    return h === 0 ? null : new RagStore(h);
  }
}
