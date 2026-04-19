// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Minimal Web demo. The Web SDK uses a WasmCoreModule injection model
// (the emscripten-emitted racommons_core.js is registered via
// VoiceSession.setWasmModule at page init). Until the emscripten bundle
// lands, this demo just proves the public surface runs to completion
// with a BACKEND_UNAVAILABLE error.

import { RunAnywhere, VoiceSession } from '../../../sdk/web/src/index.js';

async function main(): Promise<void> {
  console.log('RunAnywhere Web demo');
  // Leave setWasmModule(null) — the expected error path fires.
  VoiceSession.setWasmModule(null);
  const session = await RunAnywhere.solution(
    { kind: 'voice-agent', config: {} });

  for await (const event of session.run()) {
    console.log('  event:', event);
  }
  console.log('  ✓ stream completed');
  console.log('');
  console.log('End-to-end path: browser JS → @runanywhere/web-core →');
  console.log('  VoiceSession.setWasmModule(<emscripten exports>) once bundled.');
}

main().catch((e) => { console.error(e); process.exit(1); });
