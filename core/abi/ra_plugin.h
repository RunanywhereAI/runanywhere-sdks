// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — L2 engine plugin ABI.
//
// Every engine plugin exports ONE symbol: `ra_plugin_entry` with the signature
// below. The core calls this once at load time to populate its vtable struct.
//
// On iOS and WASM (static plugin mode), the "load" step is a compile-time
// call to `RA_STATIC_PLUGIN_REGISTER(name, ra_plugin_entry)`. On Android,
// macOS, and Linux, the core dlopens the shared library and dlsym's
// `ra_plugin_entry`.

#ifndef RA_PLUGIN_H
#define RA_PLUGIN_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"
#include "ra_version.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Engine metadata — returned by every plugin.
// ---------------------------------------------------------------------------
typedef struct {
    const char*            name;              // "llamacpp", "sherpa", etc.
    const char*            version;           // Semver of the plugin
    unsigned int           abi_version;       // Must equal RA_PLUGIN_API_VERSION
    const ra_primitive_t*  primitives;        // Array of supported primitives
    size_t                 primitives_count;
    const ra_model_format_t* formats;
    size_t                 formats_count;
    const ra_runtime_id_t* runtimes;
    size_t                 runtimes_count;
} ra_engine_metadata_t;

// ---------------------------------------------------------------------------
// Engine vtable — the core's handle to an engine plugin. The plugin fills
// only the function pointers corresponding to the primitives it serves;
// unsupported primitives leave the pointer NULL.
// ---------------------------------------------------------------------------
typedef struct {
    ra_engine_metadata_t metadata;

    // Optional capability gate — called before any session is created. The
    // plugin MAY inspect the host hardware (e.g. chip ID) and return false
    // to decline loading. When NULL, the core assumes "always available".
    bool (*capability_check)(void);

    // L3 generate_text
    ra_status_t (*llm_create)(const ra_model_spec_t*,
                              const ra_session_config_t*,
                              ra_llm_session_t**);
    void        (*llm_destroy)(ra_llm_session_t*);
    ra_status_t (*llm_generate)(ra_llm_session_t*, const ra_prompt_t*,
                                ra_token_callback_t, ra_error_callback_t,
                                void*);
    ra_status_t (*llm_cancel)(ra_llm_session_t*);
    ra_status_t (*llm_reset)(ra_llm_session_t*);

    // L3 transcribe
    ra_status_t (*stt_create)(const ra_model_spec_t*,
                              const ra_session_config_t*,
                              ra_stt_session_t**);
    void        (*stt_destroy)(ra_stt_session_t*);
    ra_status_t (*stt_feed_audio)(ra_stt_session_t*, const float*,
                                  int32_t, int32_t);
    ra_status_t (*stt_flush)(ra_stt_session_t*);
    ra_status_t (*stt_set_callback)(ra_stt_session_t*,
                                    ra_transcript_callback_t, void*);

    // L3 synthesize
    ra_status_t (*tts_create)(const ra_model_spec_t*,
                              const ra_session_config_t*,
                              ra_tts_session_t**);
    void        (*tts_destroy)(ra_tts_session_t*);
    ra_status_t (*tts_synthesize)(ra_tts_session_t*, const char*,
                                  float*, int32_t, int32_t*, int32_t*);
    ra_status_t (*tts_cancel)(ra_tts_session_t*);

    // L3 detect_voice
    ra_status_t (*vad_create)(const ra_model_spec_t*,
                              const ra_session_config_t*,
                              ra_vad_session_t**);
    void        (*vad_destroy)(ra_vad_session_t*);
    ra_status_t (*vad_feed_audio)(ra_vad_session_t*, const float*,
                                  int32_t, int32_t);
    ra_status_t (*vad_set_callback)(ra_vad_session_t*,
                                    ra_vad_callback_t, void*);

    // L3 embed
    ra_status_t (*embed_create)(const ra_model_spec_t*,
                                const ra_session_config_t*,
                                ra_embed_session_t**);
    void        (*embed_destroy)(ra_embed_session_t*);
    ra_status_t (*embed_text)(ra_embed_session_t*, const char*,
                              float*, int32_t);
    int32_t     (*embed_dims)(ra_embed_session_t*);

    // L3 wake_word
    ra_status_t (*ww_create)(const ra_model_spec_t*, const char*, float,
                             ra_ww_session_t**);
    void        (*ww_destroy)(ra_ww_session_t*);
    ra_status_t (*ww_feed_audio)(ra_ww_session_t*, const float*,
                                 int32_t, int32_t, bool*);

    // Plugin teardown — called when the core unloads the plugin.
    // Optional; may be NULL.
    void (*plugin_shutdown)(void);
} ra_engine_vtable_t;

// ---------------------------------------------------------------------------
// Plugin entry point.
//
// The single function every plugin must export. On dlopen platforms the core
// resolves this via dlsym. On static platforms (iOS/WASM), it is registered
// at link time via RA_STATIC_PLUGIN_REGISTER.
//
// Returns RA_OK if the vtable was populated successfully, or an error code
// if the plugin cannot run on this host.
// ---------------------------------------------------------------------------
typedef ra_status_t (*ra_plugin_entry_fn)(ra_engine_vtable_t* out_vtable);

// Static plugin registration. Expands to a zero-argument static initializer
// that registers the plugin at dynamic-init time. iOS and WASM only.
#ifdef RA_STATIC_PLUGINS

#ifdef __cplusplus
#define RA_STATIC_PLUGIN_REGISTER(PluginName, EntryFn)                     \
    namespace {                                                             \
        struct PluginName##_auto_register {                                 \
            PluginName##_auto_register() {                                  \
                extern void ra_registry_register_static(                    \
                    const char* name, ra_plugin_entry_fn entry);            \
                ra_registry_register_static(#PluginName, EntryFn);          \
            }                                                               \
        };                                                                  \
        static PluginName##_auto_register PluginName##_auto_register_{};    \
    }
#else
#define RA_STATIC_PLUGIN_REGISTER(PluginName, EntryFn)                     \
    __attribute__((constructor))                                            \
    static void PluginName##_auto_register(void) {                          \
        extern void ra_registry_register_static(                            \
            const char* name, ra_plugin_entry_fn entry);                    \
        ra_registry_register_static(#PluginName, EntryFn);                  \
    }
#endif  // __cplusplus

#else
// On dlopen platforms static registration is a no-op — the plugin is
// discovered at runtime via dlopen/dlsym.
#define RA_STATIC_PLUGIN_REGISTER(PluginName, EntryFn)
#endif  // RA_STATIC_PLUGINS

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_PLUGIN_H
