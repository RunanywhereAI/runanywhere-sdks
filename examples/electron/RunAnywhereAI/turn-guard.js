// turn-guard.js — "is this still the turn the user cares about?"
//
// A voice turn is a long chain of awaits (transcribe -> generate -> synthesize ->
// play) and none of the inference stack supports cancellation. So a cancelled turn
// keeps running to completion in the background. It must not be allowed to touch
// anything when it finally lands.
//
// A single `abandoned` boolean is NOT enough, and this is the bug that shipped:
// the next turn resets the flag, so the old turn's `if (abandoned) return` stops
// firing, and it goes on to overwrite the reply text, start its own playback, and
// — worst — run its `finally` block, clearing `busy` and forcing the orb to idle
// while the NEW turn is still mid-flight. The orb then looks dead.
//
// Handing every turn a number fixes it: `current()` is false the moment anything
// supersedes this turn, and it can never become true again.
//
// Loaded as a plain <script> by the app AND require()d by the unit tests.

function createTurnGuard() {
  let seq = 0;

  return {
    /** Claim the next turn. Returns a handle whose `current()` is true until superseded. */
    begin() {
      const mine = ++seq;
      return {
        id: mine,
        /** True while this is still the newest turn. Never becomes true again once false. */
        current: () => mine === seq,
      };
    },

    /**
     * Supersede whatever is in flight without starting a new turn — the cancel
     * path, and the self-heal path for a state we did not anticipate.
     */
    cancel() {
      seq++;
    },

    /** The id of the newest turn (diagnostics/tests). */
    get currentId() {
      return seq;
    },
  };
}

/* eslint-disable no-undef */
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { createTurnGuard };
}
