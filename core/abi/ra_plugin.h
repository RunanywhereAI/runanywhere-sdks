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
                                 int32_t, int32_t, uint8_t*);

    // Plugin teardown — called when the core unloads the plugin.
    // Optional; may be NULL.
    void (*plugin_shutdown)(void);

    // ----------------------------------------------------------------
    // Extension slots (appended to preserve binary compat with plugins
    // built against older vtable layouts). Plugins that do not implement
    // these leave the pointer NULL — the core returns
    // RA_ERR_CAPABILITY_UNSUPPORTED when the frontend calls into them.
    // ----------------------------------------------------------------

    // LLM context injection — port of legacy
    // rac_llm_{inject_system_prompt,append_context,generate_from_context,
    // clear_context}. Lets the frontend build persistent KV-cache state
    // across turns without re-prefilling the system prompt each time.
    // Useful for adaptive-query patterns (chat with RAG context).
    ra_status_t (*llm_inject_system_prompt)(ra_llm_session_t*, const char* prompt);
    ra_status_t (*llm_append_context)(ra_llm_session_t*, const char* text);
    ra_status_t (*llm_generate_from_context)(ra_llm_session_t*, const char* query,
                                              ra_token_callback_t on_token,
                                              ra_error_callback_t on_error,
                                              void* user_data);
    ra_status_t (*llm_clear_context)(ra_llm_session_t*);
} ra_engine_vtable_t;

// ---------------------------------------------------------------------------
// Plugin entry point.
//
// Every plugin provides ONE function that fills a vtable. It is delivered to
// the core in one of two ways:
//
//   * dlopen platforms (Android/macOS/Linux/Windows): the function is
//     exported under the fixed extern "C" symbol `ra_plugin_entry`, resolved
//     via `dlsym()`. Each plugin lives in its own .so/.dylib, so the symbol
//     never collides at link time.
//
//   * static platforms (iOS/WASM): every plugin's fill function is linked
//     into the same binary, so exporting a shared extern "C" symbol would
//     collide. Instead, each plugin keeps its fill function in an anonymous
//     namespace and registers it at dynamic-init time via
//     RA_STATIC_PLUGIN_REGISTER. The macro generates a unique auto-register
//     type per plugin name, preventing any duplicate symbols.
// ---------------------------------------------------------------------------
typedef ra_status_t (*ra_plugin_entry_fn)(ra_engine_vtable_t* out_vtable);

// ---------------------------------------------------------------------------
// Public plugin registry ABI — lets frontends load an engine plugin at
// runtime without depending on the C++ PluginRegistry class directly.
// On iOS / WASM static builds, plugin_load is a no-op returning
// RA_ERR_CAPABILITY_UNSUPPORTED since plugins are already compiled in.
// ---------------------------------------------------------------------------

// Loads a plugin from a shared-library path (.so / .dylib / .dll). Returns
// RA_OK when the plugin is registered and its capability_check passes.
ra_status_t ra_registry_load_plugin(const char* library_path);

// Unloads a previously-loaded plugin by its declared name
// (ra_engine_metadata_t.name). Returns RA_OK on success.
ra_status_t ra_registry_unload_plugin(const char* plugin_name);

// Returns the count of currently-registered plugins — useful for frontends
// to confirm a load call succeeded without having to enumerate.
int32_t     ra_registry_plugin_count(void);

// Plugin authors: use this macro to declare the fill function. It expands to
// an extern "C" symbol on dlopen builds, and to a file-local function with
// a fresh name on static builds.
//
// The entry symbol must survive -fvisibility=hidden. Engine plugin libs are
// built with CXX_VISIBILITY_PRESET hidden so internal symbols don't leak;
// ra_plugin_entry is the one symbol the host dlsym()'s, so it carries an
// explicit visibility("default") attribute. Without it the dlsym call in
// PluginRegistry::load_plugin returns NULL and the plugin fails to load.
#if defined(_WIN32)
#  define RA_PLUGIN_ENTRY_EXPORT __declspec(dllexport)
#else
#  define RA_PLUGIN_ENTRY_EXPORT __attribute__((visibility("default")))
#endif

#ifdef RA_STATIC_PLUGINS
#  define RA_PLUGIN_ENTRY_DECL(PluginName) \
    static ra_status_t PluginName##_fill_vtable(ra_engine_vtable_t* out_vtable)
#else
#  ifdef __cplusplus
#    define RA_PLUGIN_ENTRY_DECL(PluginName) \
    extern "C" RA_PLUGIN_ENTRY_EXPORT ra_status_t ra_plugin_entry(ra_engine_vtable_t* out_vtable)
#  else
#    define RA_PLUGIN_ENTRY_DECL(PluginName) \
    RA_PLUGIN_ENTRY_EXPORT ra_status_t ra_plugin_entry(ra_engine_vtable_t* out_vtable)
#  endif
#endif

// Static plugin registration. On static platforms this generates a
// `PluginName##_auto_register` symbol that calls
// ra_registry_register_static() at dynamic-init time, wiring up the local
// fill function. On dlopen platforms this is a no-op — the core discovers
// the plugin via dlopen/dlsym at runtime.
#ifdef RA_STATIC_PLUGINS

#ifdef __cplusplus
#define RA_STATIC_PLUGIN_REGISTER(PluginName)                              \
    namespace {                                                             \
        struct PluginName##_auto_register_t {                               \
            PluginName##_auto_register_t() {                                \
                extern "C" void ra_registry_register_static(                \
                    const char* name, ra_plugin_entry_fn entry);            \
                ra_registry_register_static(#PluginName,                    \
                                             PluginName##_fill_vtable);     \
            }                                                               \
        };                                                                  \
        static PluginName##_auto_register_t PluginName##_auto_register_;    \
    }
#else
#define RA_STATIC_PLUGIN_REGISTER(PluginName)                              \
    __attribute__((constructor))                                            \
    static void PluginName##_auto_register_fn(void) {                       \
        extern void ra_registry_register_static(                            \
            const char* name, ra_plugin_entry_fn entry);                    \
        ra_registry_register_static(#PluginName,                            \
                                     PluginName##_fill_vtable);             \
    }
#endif  // __cplusplus

#else
// On dlopen platforms the extern "C" ra_plugin_entry is the contract.
#define RA_STATIC_PLUGIN_REGISTER(PluginName) /* no-op on dlopen builds */
#endif  // RA_STATIC_PLUGINS

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_PLUGIN_H
