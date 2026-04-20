// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// engines/whispercpp/ — whisper.cpp STT plugin.
//
// Registers the plugin's metadata (primitives, formats, runtimes) so the
// engine router can pick it when callers request a `.whisperCpp`
// framework model. Actual `whisper_init_from_file` / `whisper_full` calls
// are gated behind `RA_HAVE_WHISPERCPP` (see CMakeLists.txt); without
// that define the vtable returns RA_ERR_CAPABILITY_UNSUPPORTED.
//
// Porting note: Sherpa-ONNX covers the STT path end-to-end today; this
// plugin exists for compatibility with models declared as
// `.whisperCpp` in the Swift/Kotlin model catalog. When a real
// whisper.cpp link is wired, the full STT vtable here fills in without
// any Swift/Kotlin SDK changes.

#include "ra_plugin.h"
#include "ra_primitives.h"

#include <array>

namespace {

constexpr std::array<ra_primitive_t, 1>    kPrimitives{RA_PRIMITIVE_TRANSCRIBE};
constexpr std::array<ra_model_format_t, 1> kFormats{RA_FORMAT_GGUF};
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes{RA_RUNTIME_SELF_CONTAINED};

bool capability_check() { return true; }

ra_status_t stt_create_stub(const ra_model_spec_t*,
                              const ra_session_config_t*,
                              ra_stt_session_t**) {
    return RA_ERR_CAPABILITY_UNSUPPORTED;
}

}  // namespace

RA_PLUGIN_ENTRY_DECL(whispercpp) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "whispercpp";
    out_vtable->metadata.version           = "0.1.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();
    out_vtable->capability_check = &capability_check;
    out_vtable->stt_create       = &stt_create_stub;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(whispercpp)
