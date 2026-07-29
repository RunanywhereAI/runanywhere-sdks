// The voice orb froze twice in real use. Both times the cause was the same shape:
// a cancelled turn kept running (nothing in the inference stack cancels) and then
// clobbered the state of the turn that replaced it. These tests pin the rule that
// makes that impossible: a superseded turn can never report itself as current.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { createTurnGuard } = require('../../turn-guard');

test('the turn in flight is current', () => {
  const g = createTurnGuard();
  const t = g.begin();
  assert.equal(t.current(), true);
});

test('starting the next turn supersedes the previous one', () => {
  const g = createTurnGuard();
  const first = g.begin();
  const second = g.begin();
  assert.equal(first.current(), false, 'the old turn must not think it is current');
  assert.equal(second.current(), true);
});

test('cancelling supersedes the in-flight turn without starting one', () => {
  const g = createTurnGuard();
  const t = g.begin();
  g.cancel();
  assert.equal(t.current(), false);
});

test('a cancelled turn stays superseded even after a new turn begins', () => {
  // THE bug: `abandoned` was a single boolean, so the new turn resetting it to
  // false made the old turn believe it was live again.
  const g = createTurnGuard();
  const cancelled = g.begin();
  g.cancel();
  const fresh = g.begin();
  assert.equal(cancelled.current(), false, 'a cancelled turn must never become current again');
  assert.equal(fresh.current(), true);
});

test('a late-landing turn cannot clear the state of the turn that replaced it', () => {
  // Models the real sequence: turn A is mid-synthesis, the user cancels and
  // speaks again (turn B), then A's finally block finally runs.
  const g = createTurnGuard();
  let busy = false;
  let orb = 'idle';

  const a = g.begin();
  busy = true; orb = 'thinking';

  g.cancel();                      // user taps to cancel
  if (a.current()) busy = false;   // (does not run)

  const b = g.begin();             // user starts a new turn
  busy = true; orb = 'thinking';

  // ...A's chain finally lands and runs its cleanup, guarded:
  if (a.current()) { busy = false; orb = 'idle'; }

  assert.equal(busy, true, 'the new turn must still be marked in flight');
  assert.equal(orb, 'thinking', 'the orb must not be forced back to idle');
  assert.equal(b.current(), true);
});

test('turn ids are distinct and monotonic', () => {
  const g = createTurnGuard();
  const ids = [g.begin().id, g.begin().id, g.begin().id];
  assert.deepEqual(ids, [1, 2, 3]);
  assert.equal(g.currentId, 3);
});
