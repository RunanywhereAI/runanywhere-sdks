// Telemetry / control-plane wiring: initialize() must assemble the two-phase
// init protos correctly and call configureControlPlane exactly once when creds
// are supplied — and skip it otherwise. Runs against a fake backend (no addon).
//
// The server-side half (verifying the telemetry row actually lands in the
// backend Postgres) is a manual check over the database MCP once a connection is
// configured; it cannot run from node:test, so it is not automated here.
import assert from 'node:assert/strict';
import test from 'node:test';

import { SdkInitPhase1Request } from '@runanywhere/proto-ts/sdk_init';

import type { ControlPlaneRequest, RaBackend } from '../../src/backend.js';
import { createRunAnywhere } from '../../src/facade.js';
import { Environment } from '../../src/types.js';

function fakeBackend(opts: { hasControlPlane: boolean }): {
  backend: RaBackend;
  calls: ControlPlaneRequest[];
} {
  const calls: ControlPlaneRequest[] = [];
  const backend = {
    initialize: async () => {},
    version: async () => '1.2.3',
    shutdown: async () => {},
    hasControlPlane: async () => opts.hasControlPlane,
    devicePersistentId: async () => 'dev-1',
    devStagingBaseUrl: async () => '',
    configureControlPlane: async (req: ControlPlaneRequest) => {
      calls.push(req);
      return new Uint8Array();
    },
  } as unknown as RaBackend;
  return { backend, calls };
}

test('initialize runs the control plane and builds phase-1 correctly when creds are given', async () => {
  const { backend, calls } = fakeBackend({ hasControlPlane: true });
  const ra = createRunAnywhere(backend);
  await ra.initialize({ apiKey: 'k', baseUrl: 'https://cp.example', environment: Environment.PRODUCTION });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].sdkBinding, 'electron');
  assert.equal(calls[0].deviceId, 'dev-1');
  const p1 = SdkInitPhase1Request.decode(calls[0].phase1Bytes);
  assert.equal(p1.apiKey, 'k');
  assert.equal(p1.baseUrl, 'https://cp.example');
  assert.equal(p1.deviceId, 'dev-1');
  assert.equal(p1.sdkVersion, '1.2.3');
  assert.equal(ra.deviceId, 'dev-1');
});

test('initialize skips the control plane when no creds are given', async () => {
  const { backend, calls } = fakeBackend({ hasControlPlane: true });
  const ra = createRunAnywhere(backend);
  await ra.initialize({ environment: Environment.PRODUCTION });
  assert.equal(calls.length, 0);
  assert.equal(ra.isReady, true);
});

test('initialize stays usable when the build has no control plane', async () => {
  const { backend, calls } = fakeBackend({ hasControlPlane: false });
  const ra = createRunAnywhere(backend);
  await ra.initialize({ apiKey: 'k', baseUrl: 'https://cp.example', environment: Environment.PRODUCTION });
  assert.equal(calls.length, 0); // no control plane -> not called
  assert.equal(ra.isReady, true); // but local inference still comes up
});
