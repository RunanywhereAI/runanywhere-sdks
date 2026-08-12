// End-to-end for the one thing a capability snapshot must never do: report the
// same backend as available AND unavailable.
//
// `capabilities()` is the surface an app reads to decide whether to show a
// button. Before the ledger was folded into the available-backend set, a fat
// addon whose sherpa engine was REFUSED at registration answered "stt/tts/vad
// are available" (compile-time linkage) and "backend:sherpa is unavailable"
// (runtime ledger) in the same object — so the app enabled a feature that
// could only fail at call time.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createRunAnywhere } from '../../dist/api/facade';
import type { RaBackend } from '../../dist/api/backend';
import type { UnavailablePlugin } from '../../dist/bridge';
import { InferenceFramework } from '../../dist/api/types';

/**
 * The three calls `capabilities()` makes, and nothing else.
 *
 * `capabilities()` reads only the engine registry (`readEngineRegistry`), so a
 * fake that answers those three questions exercises the real snapshot code
 * without a native addon. Any other method is a bug in the test, not a gap in
 * the fake — hence the throw.
 */
function fakeBackend(registry: {
  thinAddon: boolean;
  pluginNames: string[];
  unavailablePlugins: UnavailablePlugin[];
}): RaBackend {
  const stub = {
    isThinAddon: async () => registry.thinAddon,
    listPlugins: async () => registry.pluginNames,
    listUnavailablePlugins: async () => registry.unavailablePlugins,
  };
  return new Proxy(stub, {
    get(target, prop: string, receiver) {
      if (prop in target) return Reflect.get(target, prop, receiver);
      return () => {
        throw new Error(`capabilities() must not call backend.${prop}`);
      };
    },
  }) as unknown as RaBackend;
}

test('fat capabilities: a refused backend leaves the available set', async () => {
  const ra = createRunAnywhere(
    fakeBackend({
      thinAddon: false,
      pluginNames: ['llamacpp', 'onnx'],
      // -811 RAC_ERROR_CAPABILITY_UNSUPPORTED, empty path: a statically linked
      // engine whose capability_check declined. This is the shape a stub build
      // produces, and the reason path cannot be the filter key.
      unavailablePlugins: [{ name: 'sherpa', path: '', status: -811 }],
    })
  );

  const caps = await ra.capabilities();

  assert.ok(!caps.backends.includes(InferenceFramework.SHERPA), 'sherpa must not be a backend');
  for (const modality of ['stt', 'tts', 'vad']) {
    assert.ok(!caps.modalities.includes(modality), `${modality} must not be available`);
  }
  assert.equal(caps.streaming.stt, false);
  assert.equal(caps.streaming.tts, false);
  assert.equal(caps.streaming.vad, false);

  // …and it is reported, with a reason, at the one place apps already look.
  const entry = caps.unavailable.find((u) => u.name === 'backend:sherpa');
  assert.ok(entry, 'capabilities().unavailable must name the refused backend');
  assert.match(entry.reason, /declined registration/);

  // The engines that DID register keep serving — one refusal is a degradation,
  // not an outage.
  assert.deepEqual(
    [...caps.backends],
    [InferenceFramework.LLAMA_CPP, InferenceFramework.ONNX]
  );
  assert.ok(caps.modalities.includes('llm'));
  assert.ok(caps.modalities.includes('embeddings'));
});

test('thin capabilities: a plugin whose artifact is missing is named, not silent', async () => {
  // What host.ts now produces for a staged-but-absent plugin file: commons
  // derives "sherpa" from the file stem and records -820
  // RAC_ERROR_PLUGIN_LOAD_FAILED against it. Pre-filtering the path in the host
  // would have produced an empty ledger and an app that just sees no speech.
  const ra = createRunAnywhere(
    fakeBackend({
      thinAddon: true,
      pluginNames: ['llamacpp'],
      unavailablePlugins: [
        { name: 'sherpa', path: '/stage/librunanywhere_sherpa.dylib', status: -820 },
      ],
    })
  );

  const caps = await ra.capabilities();

  assert.deepEqual([...caps.backends], [InferenceFramework.LLAMA_CPP]);
  assert.ok(!caps.modalities.includes('stt'));
  const entry = caps.unavailable.find((u) => u.name === 'backend:sherpa');
  assert.ok(entry, 'capabilities().unavailable must name the missing plugin');
  assert.match(entry.reason, /could not be loaded/);
});

test('healthy fat build reports all three engines and no backend gaps', async () => {
  const ra = createRunAnywhere(
    fakeBackend({
      thinAddon: false,
      pluginNames: ['llamacpp', 'onnx', 'sherpa'],
      unavailablePlugins: [],
    })
  );

  const caps = await ra.capabilities();

  assert.deepEqual(
    [...caps.backends],
    [InferenceFramework.LLAMA_CPP, InferenceFramework.ONNX, InferenceFramework.SHERPA]
  );
  assert.equal(caps.streaming.stt, true);
  assert.equal(
    caps.unavailable.some((u) => u.name.startsWith('backend:')),
    false
  );
});
