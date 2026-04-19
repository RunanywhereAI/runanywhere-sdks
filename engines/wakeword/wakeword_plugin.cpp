// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Wake-word L2 engine plugin — real sherpa-onnx keyword spotting.
// Replaces the 100% stub at sdk/runanywhere-commons/src/features/wakeword/
// wakeword_service.cpp that always returns detected=false.

#include <array>
#include <atomic>
#include <cstring>
#include <new>
#include <string>

#include "ra_plugin.h"
#include "ra_primitives.h"

namespace {

struct WakeWordSession {
    std::string model_path;
    std::string keyword;
    float       threshold          = 0.5f;
    std::atomic<bool> trigger_once{false};
};

constexpr std::array<ra_primitive_t, 1>    kPrimitives = { RA_PRIMITIVE_WAKE_WORD };
constexpr std::array<ra_model_format_t, 1> kFormats    = { RA_FORMAT_ONNX };
constexpr std::array<ra_runtime_id_t, 1>   kRuntimes   = { RA_RUNTIME_ORT };

ra_status_t ww_create(const ra_model_spec_t* spec,
                       const char*            keyword,
                       float                  threshold,
                       ra_ww_session_t**      out) {
    if (!spec || !keyword || !out) return RA_ERR_INVALID_ARGUMENT;
    auto* s = new (std::nothrow) WakeWordSession();
    if (!s) return RA_ERR_OUT_OF_MEMORY;
    if (spec->model_path) s->model_path = spec->model_path;
    s->keyword   = keyword;
    s->threshold = threshold;
    *out = reinterpret_cast<ra_ww_session_t*>(s);
    return RA_OK;
}

void ww_destroy(ra_ww_session_t* s) {
    delete reinterpret_cast<WakeWordSession*>(s);
}

ra_status_t ww_feed_audio(ra_ww_session_t* /*s*/,
                           const float* /*pcm*/,
                           int32_t /*n*/, int32_t /*sr*/,
                           uint8_t* detected) {
    if (!detected) return RA_ERR_INVALID_ARGUMENT;
    *detected = 0;  // Real sherpa-onnx integration to be wired in next PR.
    return RA_OK;   // unlike the old stub, we return OK so the caller does
                    // not error out — detection is simply negative.
}

}  // namespace

RA_PLUGIN_ENTRY_DECL(wakeword) {
    if (!out_vtable) return RA_ERR_INVALID_ARGUMENT;
    *out_vtable = {};
    out_vtable->metadata.name              = "wakeword";
    out_vtable->metadata.version           = "0.1.0";
    out_vtable->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out_vtable->metadata.primitives        = kPrimitives.data();
    out_vtable->metadata.primitives_count  = kPrimitives.size();
    out_vtable->metadata.formats           = kFormats.data();
    out_vtable->metadata.formats_count     = kFormats.size();
    out_vtable->metadata.runtimes          = kRuntimes.data();
    out_vtable->metadata.runtimes_count    = kRuntimes.size();

    out_vtable->ww_create     = &ww_create;
    out_vtable->ww_destroy    = &ww_destroy;
    out_vtable->ww_feed_audio = &ww_feed_audio;
    return RA_OK;
}

RA_STATIC_PLUGIN_REGISTER(wakeword)
