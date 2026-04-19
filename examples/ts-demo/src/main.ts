// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Minimal Node/TS demo. The TS SDK uses a NativePipelineBindings
// injection model (so the same TS surface serves Node N-API, React
// Native TurboModules, and browser WASM). This demo plugs in a
// no-op bindings provider to prove the public API traverses through.

import { RunAnywhere, VoiceSession } from '../../../frontends/ts/src/index.js';
import type { NativePipelineBindings } from '../../../frontends/ts/src/adapter/VoiceSession.js';
import type { VoiceEvent } from '../../../frontends/ts/src/adapter/VoiceEvent.js';

let nextHandle = 1;
let eventsEmitted = 0;

const bindings: NativePipelineBindings = {
  createVoiceAgent: (config) => {
    console.log('  native.createVoiceAgent', config);
    return nextHandle++;
  },
  subscribe: (handle, onEvent, onDone, onError) => {
    console.log(`  native.subscribe handle=${handle}`);
    // Simulate a USER_SAID event, a state change, then close.
    setImmediate(() => {
      onEvent({ kind: 'user-said', text: 'hello world', isFinal: true });
      eventsEmitted++;
      onError(-6, 'no engines registered in this demo binary');
    });
  },
  run:    (h) => { console.log(`  native.run handle=${h}`); return 0; },
  cancel: (h) => { console.log(`  native.cancel handle=${h}`); return 0; },
  destroy: (h) => { console.log(`  native.destroy handle=${h}`); },
  feedAudio: (h, s, sr) => { console.log(`  native.feedAudio h=${h} n=${s.length} sr=${sr}`); return 0; },
  bargeIn: (h) => { console.log(`  native.bargeIn h=${h}`); return 0; },
};

async function main(): Promise<void> {
  console.log('RunAnywhere TypeScript demo');
  VoiceSession.setNativeBindings(bindings);
  const session = RunAnywhere.solution({ kind: 'voice-agent', config: {} });
  for await (const event of session.run()) {
    console.log('  event:', event);
  }
  console.log(`  ✓ stream completed (${eventsEmitted} synthetic events)`);
  console.log('');
  console.log('End-to-end path: TS → VoiceSession.setNativeBindings({...}) → ');
  console.log('  user-provided adapter (N-API/TurboModule/WASM fills in).');
}

main().catch((e) => { console.error(e); process.exit(1); });
