// Unit tests for thin-addon / core-alone engine registry helpers (Track B8).
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  FAT_ADDON_FRAMEWORKS,
  assertBackendEnginesRegistered,
  backendsForRegistry,
  frameworksFromPluginNames,
  noBackendEnginesException,
} from '../../dist/backend/engines';
import { InferenceFramework } from '../../dist/api/types';
import { ErrorCodes, SDKException, isSDKException } from '../../dist/errors';

test('frameworksFromPluginNames maps common registry / package stems', () => {
  assert.deepEqual(
    [...frameworksFromPluginNames(['llamacpp', 'onnx', 'sherpa'])],
    [
      InferenceFramework.LLAMA_CPP,
      InferenceFramework.ONNX,
      InferenceFramework.SHERPA,
    ]
  );
  assert.deepEqual(
    [...frameworksFromPluginNames(['librunanywhere_llamacpp', 'runanywhere_onnx'])],
    [InferenceFramework.LLAMA_CPP, InferenceFramework.ONNX]
  );
  assert.deepEqual([...frameworksFromPluginNames(['cloud', 'unknown'])], []);
});

test('frameworksFromPluginNames maps QHexRT from both of its stems', () => {
  // The plugin ships as runanywhere_qhexrt.dll, but the engine's CMake target is
  // rac_backend_qhexrt — a registry reporting either name must resolve to the
  // same framework, or capabilities() silently omits the NPU on a box that has one.
  for (const stem of [
    'qhexrt',
    'runanywhere_qhexrt',
    'librunanywhere_qhexrt',
    'rac_backend_qhexrt',
  ]) {
    assert.deepEqual(
      [...frameworksFromPluginNames([stem])],
      [InferenceFramework.QHEXRT],
      `stem ${stem} should map to QHEXRT`
    );
  }
});

test('backendsForRegistry returns fat defaults when not thin', () => {
  assert.deepEqual(
    [...backendsForRegistry({ thinAddon: false, pluginNames: [] })],
    [...FAT_ADDON_FRAMEWORKS]
  );
});

test('backendsForRegistry reports zero engines for thin core-alone', () => {
  assert.deepEqual([...backendsForRegistry({ thinAddon: true, pluginNames: [] })], []);
});

test('backendsForRegistry lists only registered thin plugins', () => {
  assert.deepEqual(
    [...backendsForRegistry({ thinAddon: true, pluginNames: ['sherpa'] })],
    [InferenceFramework.SHERPA]
  );
});

test('assertBackendEnginesRegistered is a no-op for fat and non-empty thin', () => {
  assert.doesNotThrow(() =>
    assertBackendEnginesRegistered({ thinAddon: false, pluginNames: [] })
  );
  assert.doesNotThrow(() =>
    assertBackendEnginesRegistered({ thinAddon: true, pluginNames: ['llamacpp'] })
  );
});

test('assertBackendEnginesRegistered throws typed SDKException for thin core-alone', () => {
  try {
    assertBackendEnginesRegistered({ thinAddon: true, pluginNames: [] });
    assert.fail('expected throw');
  } catch (e) {
    assert.ok(isSDKException(e));
    assert.equal(e.code, ErrorCodes.FEATURE_NOT_AVAILABLE);
    assert.equal(e.component, 'backend');
    assert.match(e.message, /No inference backends are registered/);
  }
});

test('SDKException.noBackendEngines matches noBackendEnginesException', () => {
  const a = SDKException.noBackendEngines();
  const b = noBackendEnginesException();
  assert.equal(a.code, b.code);
  assert.equal(a.message, b.message);
  assert.equal(a.component, 'backend');
});
