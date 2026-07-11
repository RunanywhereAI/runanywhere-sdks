import { describe, expect, it, vi } from 'vitest';

import {
  getVoiceAgentAvailability,
  setVoiceAgentProvider,
  type VoiceAgentProvider,
} from '../../../src/Public/Extensions/RunAnywhere+VoiceAgent';
import { RunAnywhere } from '../../../src/Public/RunAnywhere';

describe('RunAnywhere.shutdown provider cleanup', () => {
  it('cleans up and forgets a voice-agent provider before module teardown', async () => {
    const cleanupVoiceAgent = vi.fn();
    const provider = {
      providerKind: 'custom',
      initializeVoiceAgent: vi.fn(),
      initializeVoiceAgentWithLoadedModels: vi.fn(),
      isVoiceAgentReady: vi.fn(() => true),
      getVoiceAgentComponentStates: vi.fn(),
      processVoiceTurn: vi.fn(),
      voiceAgentTranscribe: vi.fn(),
      voiceAgentGenerateResponse: vi.fn(),
      voiceAgentSynthesizeSpeech: vi.fn(),
      cleanupVoiceAgent,
    } as unknown as VoiceAgentProvider;
    setVoiceAgentProvider(provider);

    await RunAnywhere.shutdown();

    expect(cleanupVoiceAgent).toHaveBeenCalledOnce();
    expect(getVoiceAgentAvailability().available).toBe(false);
  });
});
