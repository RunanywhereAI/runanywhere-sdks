/**
 * loraFixture.ts
 *
 * Shared LoRA fixture descriptor for the validation harness. The
 * SDK's `RunAnywhere.lora.attachAdapter(...)` resolves this into a
 * sandboxed adapter path so view code does not need to know the
 * platform sandbox layout. The harness operator stages the file at
 * the SDK-resolved path per
 * `test_workflows/instructions/cross-platform-e2e-test-catalog.md
 * §9b "LoRA fixture deployment"` before the validation lane runs.
 */

import { RunAnywhere } from '@runanywhere/core';
import type { LoRAAdapterConfig } from '@runanywhere/proto-ts/lora_options';

const FIXTURE_FILENAME = 'identity-adapter.gguf';

const FIXTURE_REQUEST = {
  adapterId: 'rn-validation-identity',
  modelId: 'rn-validation-base',
  filename: FIXTURE_FILENAME,
  scale: 0.5,
  targetModules: ['q_proj', 'v_proj'],
  metadata: {
    lane: 'react-native-validation',
    fixture: 'identity-adapter',
  },
};

export interface LoRAFixtureAttachResult {
  config: LoRAAdapterConfig;
  adapterPath: string;
}

/**
 * Resolve the staged LoRA fixture into a `LoRAAdapterConfig` plus the
 * SDK-managed sandboxed path the operator must stage the file into.
 */
export async function attachLoRAFixture(): Promise<LoRAFixtureAttachResult> {
  return RunAnywhere.lora.attachAdapter(FIXTURE_REQUEST);
}
