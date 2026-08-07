import assert from 'node:assert/strict';
import test from 'node:test';

import { NativeResource, ResourceGuard, releaseLeaked } from '../../src/resources.js';

test('ResourceGuard runs release once and reports released', () => {
  let freed = 0;
  const guard = new ResourceGuard({}, () => { freed += 1; }, 'test');
  assert.equal(guard.released, false);
  guard.free();
  guard.free();
  assert.equal(freed, 1);
  assert.equal(guard.released, true);
});

test('NativeResource: dispose, close, and Symbol.dispose are the same idempotent release', () => {
  class Handle extends NativeResource {
    freed = 0;
    constructor() {
      // A real subclass captures the handle/backend here, never `this`; the test
      // counter is on the instance only to observe the call.
      super('Handle', () => { count.n += 1; });
    }
  }
  const count = { n: 0 };
  const h = new Handle();
  h.dispose();
  h.close();
  h[Symbol.dispose]();
  assert.equal(count.n, 1);
});

test('using disposes at scope exit', () => {
  const count = { n: 0 };
  class Handle extends NativeResource {
    constructor() {
      super('Handle', () => { count.n += 1; });
    }
  }
  {
    using _h = new Handle();
    assert.equal(count.n, 0);
  }
  assert.equal(count.n, 1);
});

test('releaseLeaked warns then frees once, and swallows a throwing release', () => {
  const warnings: string[] = [];
  let freed = 0;
  releaseLeaked({ label: 'Leaked', warn: (m) => warnings.push(m), release: () => { freed += 1; } });
  assert.equal(freed, 1);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /garbage-collected before dispose\(\)/);

  // A finalizer must never throw out.
  assert.doesNotThrow(() =>
    releaseLeaked({ label: 'Boom', warn: () => {}, release: () => { throw new Error('boom'); } })
  );
});
