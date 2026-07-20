// Integration test for the DPAPI-backed secure store (needs the real addon; no
// model). Verifies the round-trip AND that the value is encrypted on disk.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const HAVE_ADDON = Boolean(NATIVE_PATH) && (() => {
  try { return fs.existsSync(NATIVE_PATH); } catch { return false; }
})();
const SKIP = HAVE_ADDON ? {} : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

let RunAnywhere = null;
const KEY = 'test-secret-key';
const SECRET = 'sk-integration-secret-XYZ-9876';

before(() => {
  if (!HAVE_ADDON) return;
  ({ RunAnywhere } = require('../../dist'));
  RunAnywhere.initialize();
});
after(() => {
  if (RunAnywhere) {
    try { RunAnywhere.secureDelete(KEY); } catch {}
    try { RunAnywhere.shutdown(); } catch {}
  }
});

test('secureSet stores an encrypted (non-plaintext) blob on disk', SKIP, () => {
  RunAnywhere.secureSet(KEY, SECRET);
  const file = path.join(os.homedir(), '.runanywhere', 'secure', KEY);
  assert.ok(fs.existsSync(file), 'secure file was written');
  const blob = fs.readFileSync(file);
  // DPAPI blob = version DWORD then the provider GUID (D0 8C 9D DF ...).
  assert.ok(blob.length > 8 && blob[4] === 0xd0 && blob[5] === 0x8c && blob[6] === 0x9d && blob[7] === 0xdf,
    'on-disk value is a DPAPI blob');
  assert.ok(!blob.toString('latin1').includes(SECRET), 'plaintext secret is NOT recoverable from disk');
});

test('secureGet decrypts the stored value (round-trip)', SKIP, () => {
  RunAnywhere.secureSet(KEY, SECRET);
  assert.equal(RunAnywhere.secureGet(KEY), SECRET);
});

test('secureGet returns null for a missing key', SKIP, () => {
  assert.equal(RunAnywhere.secureGet('no-such-key-' + Date.now()), null);
});

test('secureDelete removes the value', SKIP, () => {
  RunAnywhere.secureSet(KEY, SECRET);
  RunAnywhere.secureDelete(KEY);
  assert.equal(RunAnywhere.secureGet(KEY), null);
});

test('overwriting a key updates the stored value', SKIP, () => {
  RunAnywhere.secureSet(KEY, 'first');
  RunAnywhere.secureSet(KEY, 'second');
  assert.equal(RunAnywhere.secureGet(KEY), 'second');
});
