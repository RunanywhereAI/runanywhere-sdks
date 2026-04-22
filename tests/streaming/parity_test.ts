// SPDX-License-Identifier: Apache-2.0
//
// parity_test.ts — GAP 09 Phase 20 streaming parity test (TypeScript).
// Shared by the RN + Web SDK Jest suites. See tests/streaming/README.md.

describe('GAP 09 streaming parity (TS)', () => {
  it.skip('voiceAgent streams expected events', async () => {
    // GAP 09 ship: scaffold + adapter wiring; golden events land in Wave D.
    // const adapter = new VoiceAgentStreamAdapter(handle);
    // const collected: string[] = [];
    // for await (const evt of adapter.stream()) {
    //   collected.push(eventSummary(evt));
    //   if (collected.length >= 20) break;
    // }
    // expect(collected).toEqual(expectedGoldenSequence());
  });

  it.skip('cancellation yields no stale events', async () => {
    // After break, sleep 100ms, assert no further events were collected.
  });
});
