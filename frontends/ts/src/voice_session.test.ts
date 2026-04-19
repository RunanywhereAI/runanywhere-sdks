// SPDX-License-Identifier: Apache-2.0
import { describe, it, expect } from 'vitest';
import { RunAnywhere, type VoiceAgentConfig } from './index.js';

describe('VoiceAgentConfig defaults', () => {
    it('compiles with no overrides', () => {
        const cfg: VoiceAgentConfig = {};
        expect(cfg.llm).toBeUndefined();
    });
});

describe('VoiceSession without native core', () => {
    it('yields backend-unavailable error', async () => {
        const session = RunAnywhere.solution({
            kind:   'voice-agent',
            config: { llm: 'qwen3-4b' },
        });
        const events: unknown[] = [];
        for await (const e of session.run()) events.push(e);
        expect(events.length).toBe(1);
        expect(events[0]).toMatchObject({ kind: 'error', code: -6 });
    });
});
