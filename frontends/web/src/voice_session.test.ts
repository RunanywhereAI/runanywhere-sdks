// SPDX-License-Identifier: Apache-2.0
import { describe, it, expect } from 'vitest';
import { RunAnywhere } from './index.js';

describe('Web VoiceSession without WASM', () => {
    it('yields WASM-not-loaded error', async () => {
        const session = await RunAnywhere.solution({
            kind:   'voice-agent',
            config: { llm: 'qwen3-4b' },
        });
        const events: unknown[] = [];
        for await (const e of session.run()) events.push(e);
        expect(events.length).toBe(1);
        expect(events[0]).toMatchObject({ kind: 'error', code: -6 });
    });
});
