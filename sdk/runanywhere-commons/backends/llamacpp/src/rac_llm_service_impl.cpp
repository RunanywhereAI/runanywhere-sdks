/**
 * @file rac_llm_service_impl.cpp
 * @brief LlamaCPP Backend - Legacy Compatibility Stub
 *
 * NOTE: The generic LLM service API (rac_llm_create, rac_llm_generate, etc.)
 * is now implemented in src/features/llm/rac_llm_service.cpp which provides
 * framework-aware dispatch to the correct backend (LlamaCpp, Foundation Models,
 * ONNX, etc.) based on the model's framework type.
 *
 * This file is intentionally empty as all generic implementations have been
 * moved to the central service layer for proper multi-backend dispatch.
 *
 * Backend-specific functions remain in rac_llm_llamacpp.cpp:
 * - rac_llm_llamacpp_create()
 * - rac_llm_llamacpp_destroy()
 * - rac_llm_llamacpp_generate()
 * - rac_llm_llamacpp_generate_stream()
 * - etc.
 */

// This file is intentionally minimal.
// All generic service functions are now in rac_llm_service.cpp
