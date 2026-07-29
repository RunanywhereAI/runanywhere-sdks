import { describe, expect, it } from 'vitest';
import { WASM_CAPABILITY_EXPORT_MANIFEST } from '../../../src/runtime/WasmCapabilityManifest';

describe('WASM capability export manifest', () => {
  it('lists the exports required by the primary modality adapters', () => {
    expect(WASM_CAPABILITY_EXPORT_MANIFEST.llm).toEqual(expect.arrayContaining([
      '_rac_llm_generate_proto',
      '_rac_llm_generate_stream_proto',
    ]));
    expect(WASM_CAPABILITY_EXPORT_MANIFEST.embedding).toContain(
      '_rac_embeddings_embed_batch_lifecycle_proto',
    );
    expect(WASM_CAPABILITY_EXPORT_MANIFEST.stt).toContain(
      '_rac_stt_transcribe_lifecycle_proto',
    );
    expect(WASM_CAPABILITY_EXPORT_MANIFEST['voice-agent']).toContain(
      '_rac_voice_agent_process_voice_turn_proto',
    );
  });
});
