// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Emscripten entry point — stitches the C ABI into a WASM module. All
// engine plugins are compiled in statically (RA_STATIC_PLUGINS=ON), so they
// self-register at ctor-init time. The C ABI functions are exported by
// Emscripten linker flags (see CMakeLists.txt).
//
// `keep_alive` touches every non-pipeline ABI symbol we want browsers to
// reach from JavaScript. Without this `volatile` reference emcc's dead-
// code elimination can sometimes drop symbols even when they're in
// EXPORTED_FUNCTIONS, depending on LTO aggressiveness.

#include "ra_auth.h"
#include "ra_download.h"
#include "ra_model.h"
#include "ra_rag.h"
#include "ra_structured.h"
#include "ra_telemetry.h"
#include "ra_tool.h"

namespace {
volatile void* keep_alive[] = {
    reinterpret_cast<void*>(&ra_auth_is_authenticated),
    reinterpret_cast<void*>(&ra_auth_get_access_token),
    reinterpret_cast<void*>(&ra_auth_handle_authenticate_response),
    reinterpret_cast<void*>(&ra_telemetry_track),
    reinterpret_cast<void*>(&ra_telemetry_flush),
    reinterpret_cast<void*>(&ra_telemetry_payload_default),
    reinterpret_cast<void*>(&ra_model_detect_format),
    reinterpret_cast<void*>(&ra_model_infer_category),
    reinterpret_cast<void*>(&ra_framework_supports),
    reinterpret_cast<void*>(&ra_rag_chunk_text),
    reinterpret_cast<void*>(&ra_rag_store_create),
    reinterpret_cast<void*>(&ra_rag_store_destroy),
    reinterpret_cast<void*>(&ra_rag_store_add),
    reinterpret_cast<void*>(&ra_rag_store_search),
    reinterpret_cast<void*>(&ra_rag_format_context),
    reinterpret_cast<void*>(&ra_download_sha256_file),
    reinterpret_cast<void*>(&ra_download_verify_sha256),
};
}  // namespace

int main() {
    (void)keep_alive;
    return 0;
}
