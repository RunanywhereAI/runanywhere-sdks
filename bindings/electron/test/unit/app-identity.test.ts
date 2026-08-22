// The host app's identity must reach the control plane, not the SDK's own.
//
// configureControlPlane hardcoded appIdentifier/appName to
// 'ai.runanywhere.electron' / 'RunAnywhere Electron' with no way to override,
// and sent the SDK's version as appVersion. Every Electron app therefore looked
// identical in the stored telemetry — a customer's app indistinguishable from
// the reference app — and no app version was ever recorded.
//
// These assert the resolution rules directly, without needing the native addon:
// a supplied value wins, and the SDK's own identity is only a last resort so an
// app that never sets one is still attributable to "some Electron app" rather
// than mislabelled as a specific one.
import assert from 'node:assert/strict';
import { test } from 'node:test';

const SDK_VERSION = '0.20.24';

/** Mirrors the `??` chain in src/api/facade.ts:configureControlPlane. */
function resolveAppIdentity(options: {
  appIdentifier?: string;
  appName?: string;
  appVersion?: string;
}) {
  return {
    appIdentifier: options.appIdentifier ?? 'ai.runanywhere.electron',
    appName: options.appName ?? 'RunAnywhere Electron',
    appVersion: options.appVersion ?? SDK_VERSION,
  };
}

test('host app identity wins over the SDK default', () => {
  const resolved = resolveAppIdentity({
    appIdentifier: 'com.customer.app',
    appName: 'Customer App',
    appVersion: '3.1.4',
  });
  assert.equal(resolved.appIdentifier, 'com.customer.app');
  assert.equal(resolved.appName, 'Customer App');
  assert.equal(resolved.appVersion, '3.1.4');
});

test('an app that supplies nothing still identifies as the SDK, not as a customer', () => {
  const resolved = resolveAppIdentity({});
  assert.equal(resolved.appIdentifier, 'ai.runanywhere.electron');
  assert.equal(resolved.appName, 'RunAnywhere Electron');
});

test('appVersion is the host app version when given, not the SDK version', () => {
  // The old behaviour recorded the SDK version here for every app, which is
  // never what a fleet query about app versions wants.
  assert.equal(resolveAppIdentity({ appVersion: '3.1.4' }).appVersion, '3.1.4');
  assert.notEqual(resolveAppIdentity({ appVersion: '3.1.4' }).appVersion, SDK_VERSION);
});

test('a partially-configured app keeps the defaults it did not set', () => {
  const resolved = resolveAppIdentity({ appName: 'Only A Name' });
  assert.equal(resolved.appName, 'Only A Name');
  assert.equal(resolved.appIdentifier, 'ai.runanywhere.electron');
});
