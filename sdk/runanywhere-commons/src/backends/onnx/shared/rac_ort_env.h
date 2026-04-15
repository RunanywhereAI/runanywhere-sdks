// =============================================================================
// rac_ort_env.h
// -----------------------------------------------------------------------------
// Process-lifetime shared Ort::Env for RAC's ONNX consumers.
//
// Previously onnx_backend.cpp, wakeword_onnx.cpp, and onnx_embedding_provider
// each created their own OrtEnv. ORT does not forbid multiple envs, but each
// one spins up its own logger, thread-pool, and arena, so the duplication was
// pure waste. This header exposes a single lazy-initialized env that all
// three call sites share.
//
// Lifetime: the env is intentionally leaked (never destroyed) so it outlives
// any Ort::Session that references it. Destruction order across translation
// units is otherwise unmanageable.
//
// Only included by code compiled inside rac_backend_onnx (native platforms).
// WASM builds do not compile rac_backend_onnx at all — see
// sdk/runanywhere-web/wasm/CMakeLists.txt.
// =============================================================================

#pragma once

#ifdef RAC_HAS_ONNX

#include <onnxruntime_c_api.h>
#include <onnxruntime_cxx_api.h>

namespace rac::onnx {

/// Returns the shared ONNX Runtime C API table. Thread-safe; lazy-initialized.
/// Can return nullptr if ORT failed to load — callers must null-check.
const OrtApi* shared_ort_api();

/// Returns a non-owning pointer to the shared OrtEnv. Thread-safe.
/// Can return nullptr if the env failed to create.
OrtEnv* shared_ort_env();

/// Returns the shared Ort::Env (C++ API). Thread-safe; lazy-initialized.
/// Throws Ort::Exception if ORT could not create the env.
Ort::Env& shared_cxx_env();

}  // namespace rac::onnx

#endif  // RAC_HAS_ONNX
