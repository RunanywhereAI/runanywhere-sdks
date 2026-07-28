// Unit tests for the app's JSON store (store.js). Losing this data is silent and
// total, so these pin the two properties that prevent it: atomic writes, and a
// corrupt file being preserved rather than discarded.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { createStore, capConversations } = require('../../store');

const fresh = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ra-store-'));

test('readJson returns the fallback when the file does not exist', () => {
  const s = createStore(fresh());
  assert.deepEqual(s.readJson('conversations.json', []), []);
  assert.deepEqual(s.readJson('settings.json', { a: 1 }), { a: 1 });
});

test('writeJson then readJson round-trips', () => {
  const s = createStore(fresh());
  const data = { nextConvId: 3, conversations: [{ id: 1, title: 'hi' }] };
  assert.equal(s.writeJson('conversations.json', data), true);
  assert.deepEqual(s.readJson('conversations.json', null), data);
});

test('writeJson creates the directory if it is missing', () => {
  const dir = path.join(fresh(), 'not', 'there', 'yet');
  const s = createStore(dir);
  assert.equal(s.writeJson('settings.json', { x: 1 }), true);
  assert.equal(fs.existsSync(path.join(dir, 'settings.json')), true);
});

test('writeJson leaves NO temp file behind', () => {
  const dir = fresh();
  const s = createStore(dir);
  s.writeJson('settings.json', { x: 1 });
  const strays = fs.readdirSync(dir).filter((f) => f.includes('.tmp'));
  assert.deepEqual(strays, [], 'temp files must be renamed, not left around');
});

test('a write never leaves a truncated file: the old value survives a failed write', () => {
  const dir = fresh();
  const s = createStore(dir);
  s.writeJson('settings.json', { good: true });
  // Data that cannot be serialized (a BigInt) makes JSON.stringify throw AFTER
  // the store has decided to write — the live file must be untouched.
  assert.equal(s.writeJson('settings.json', { bad: 1n }), false);
  assert.deepEqual(s.readJson('settings.json', null), { good: true });
  const strays = fs.readdirSync(dir).filter((f) => f.includes('.tmp'));
  assert.deepEqual(strays, [], 'a failed write must clean up its temp file');
});

test('a corrupt store is backed up, not silently discarded', () => {
  const dir = fresh();
  const s = createStore(dir);
  fs.writeFileSync(path.join(dir, 'conversations.json'), '{"conversations": [tr');
  assert.deepEqual(s.readJson('conversations.json', []), [], 'falls back cleanly');
  const backups = fs.readdirSync(dir).filter((f) => f.includes('.corrupt-'));
  assert.equal(backups.length, 1, 'the unreadable bytes are kept for recovery');
  assert.match(fs.readFileSync(path.join(dir, backups[0]), 'utf8'), /conversations/);
});

test('a rewritten store replaces the previous contents completely', () => {
  const s = createStore(fresh());
  s.writeJson('settings.json', { a: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' });
  s.writeJson('settings.json', { b: 1 });
  assert.deepEqual(s.readJson('settings.json', null), { b: 1 }, 'no leftover tail from the longer write');
});

// --- capConversations --------------------------------------------------------

test('capConversations keeps the newest entries and bounds the list', () => {
  const many = Array.from({ length: 250 }, (_, i) => ({ id: i }));
  const capped = capConversations(many, 200);
  assert.equal(capped.length, 200);
  assert.equal(capped[0].id, 0, 'newest-first order is preserved');
  assert.equal(capped[199].id, 199);
});

test('capConversations leaves a short list untouched and tolerates junk', () => {
  const few = [{ id: 1 }, { id: 2 }];
  assert.equal(capConversations(few, 200), few);
  assert.deepEqual(capConversations(null), []);
  assert.deepEqual(capConversations(undefined), []);
});
