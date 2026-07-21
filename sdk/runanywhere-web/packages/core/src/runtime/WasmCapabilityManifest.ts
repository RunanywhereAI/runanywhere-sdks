import type { WasmCapability } from './EmscriptenModule.js';

/**
 * Single source of truth for the Web WASM ABI expected by capability adapters.
 * Keep this data-only so a future build step can generate CMake export lists,
 * adapter guards, and package diagnostics from it.
 */
export const WASM_CAPABILITY_EXPORT_MANIFEST: Readonly<Record<WasmCapability, readonly string[]>> = {
  commons: ['_rac_get_model_registry', '_rac_model_lifecycle_load_proto'],
  llm: ['_rac_llm_generate_proto', '_rac_llm_generate_stream_proto'],
  vlm: ['_rac_vlm_generate_proto', '_rac_vlm_stream_proto'],
  stt: ['_rac_stt_component_transcribe_proto', '_rac_stt_transcribe_lifecycle_proto'],
  tts: ['_rac_tts_component_synthesize_proto', '_rac_tts_synthesize_lifecycle_proto'],
  vad: ['_rac_vad_component_process_proto', '_rac_vad_process_lifecycle_proto'],
  embedding: ['_rac_embeddings_embed_batch_proto', '_rac_embeddings_embed_batch_lifecycle_proto'],
  segmentation: ['_rac_segmentation_segment_lifecycle_proto'],
  rag: ['_rac_rag_session_create_proto', '_rac_rag_query_proto'],
  diffusion: ['_rac_diffusion_generate_lifecycle_proto', '_rac_diffusion_cancel_proto'],
  'structured-output': ['_rac_structured_output_parse_proto', '_rac_structured_output_validate_proto'],
  'tool-calling': ['_rac_tool_calling_session_create_proto', '_rac_tool_calling_session_destroy_proto'],
  lora: ['_rac_lora_register_proto', '_rac_lora_apply_proto'],
  'voice-agent': ['_rac_voice_agent_initialize_proto', '_rac_voice_agent_process_voice_turn_proto'],
};
