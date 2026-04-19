// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// rac_compat.c — ABI-level wrapper functions so pre-compiled frontend
// binaries that link expecting `rac_*` symbols resolve against the new
// `ra_*` implementation.
//
// The header `rac_compat.h` handles the source-level migration via
// #define aliases — but the XCFramework / .so / .dylib we ship must
// also expose `rac_*` as real exported symbols for pre-compiled Swift
// / Kotlin / Dart binaries that were linked against legacy commons.
//
// Each wrapper is a thin forwarder — trivially inlinable, zero cost.
// Non-trivial call-shape mappings live in rac_compat_shim.c (future).

#include "ra_primitives.h"
#include "ra_version.h"
#include "ra_errors.h"
#include "ra_lifecycle.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  define RA_COMPAT_EXPORT __declspec(dllexport)
#else
#  define RA_COMPAT_EXPORT __attribute__((visibility("default")))
#endif

/* Forward declarations of the ra_* entry points we're wrapping. */
extern ra_status_t ra_llm_create(const ra_model_spec_t*, const ra_session_config_t*,
                                  ra_llm_session_t**);
extern void        ra_llm_destroy(ra_llm_session_t*);
extern ra_status_t ra_llm_generate(ra_llm_session_t*, const ra_prompt_t*,
                                    ra_token_callback_t, ra_error_callback_t, void*);
extern ra_status_t ra_llm_cancel(ra_llm_session_t*);
extern ra_status_t ra_llm_reset(ra_llm_session_t*);

extern ra_status_t ra_stt_create(const ra_model_spec_t*, const ra_session_config_t*,
                                  ra_stt_session_t**);
extern void        ra_stt_destroy(ra_stt_session_t*);
extern ra_status_t ra_stt_feed_audio(ra_stt_session_t*, const float*, int32_t, int32_t);
extern ra_status_t ra_stt_flush(ra_stt_session_t*);
extern ra_status_t ra_stt_set_callback(ra_stt_session_t*, ra_transcript_callback_t, void*);

extern ra_status_t ra_tts_create(const ra_model_spec_t*, const ra_session_config_t*,
                                  ra_tts_session_t**);
extern void        ra_tts_destroy(ra_tts_session_t*);
extern ra_status_t ra_tts_synthesize(ra_tts_session_t*, const char*, float*,
                                      int32_t, int32_t*, int32_t*);
extern ra_status_t ra_tts_cancel(ra_tts_session_t*);

extern ra_status_t ra_vad_create(const ra_model_spec_t*, const ra_session_config_t*,
                                  ra_vad_session_t**);
extern void        ra_vad_destroy(ra_vad_session_t*);
extern ra_status_t ra_vad_feed_audio(ra_vad_session_t*, const float*, int32_t, int32_t);
extern ra_status_t ra_vad_set_callback(ra_vad_session_t*, ra_vad_callback_t, void*);

extern ra_status_t ra_embed_create(const ra_model_spec_t*, const ra_session_config_t*,
                                    ra_embed_session_t**);
extern void        ra_embed_destroy(ra_embed_session_t*);
extern ra_status_t ra_embed_text(ra_embed_session_t*, const char*, float*, int32_t);
extern int32_t     ra_embed_dims(ra_embed_session_t*);

extern ra_status_t ra_ww_create(const ra_model_spec_t*, const char*, float,
                                 ra_ww_session_t**);
extern void        ra_ww_destroy(ra_ww_session_t*);
extern ra_status_t ra_ww_feed_audio(ra_ww_session_t*, const float*, int32_t,
                                     int32_t, uint8_t*);

/* --- LLM ---------------------------------------------------------------- */
RA_COMPAT_EXPORT ra_status_t rac_llm_create(const ra_model_spec_t* s,
                                              const ra_session_config_t* c,
                                              ra_llm_session_t** o) {
    return ra_llm_create(s, c, o);
}
RA_COMPAT_EXPORT void rac_llm_destroy(ra_llm_session_t* s) { ra_llm_destroy(s); }
RA_COMPAT_EXPORT ra_status_t rac_llm_generate(ra_llm_session_t* s, const ra_prompt_t* p,
                                                ra_token_callback_t on_token,
                                                ra_error_callback_t on_error, void* ud) {
    return ra_llm_generate(s, p, on_token, on_error, ud);
}
RA_COMPAT_EXPORT ra_status_t rac_llm_cancel(ra_llm_session_t* s) { return ra_llm_cancel(s); }
RA_COMPAT_EXPORT ra_status_t rac_llm_reset(ra_llm_session_t* s)  { return ra_llm_reset(s); }

/* --- STT ---------------------------------------------------------------- */
RA_COMPAT_EXPORT ra_status_t rac_stt_create(const ra_model_spec_t* s,
                                              const ra_session_config_t* c,
                                              ra_stt_session_t** o) {
    return ra_stt_create(s, c, o);
}
RA_COMPAT_EXPORT void rac_stt_destroy(ra_stt_session_t* s) { ra_stt_destroy(s); }
RA_COMPAT_EXPORT ra_status_t rac_stt_feed_audio(ra_stt_session_t* s, const float* p,
                                                  int32_t n, int32_t sr) {
    return ra_stt_feed_audio(s, p, n, sr);
}
RA_COMPAT_EXPORT ra_status_t rac_stt_flush(ra_stt_session_t* s) { return ra_stt_flush(s); }
RA_COMPAT_EXPORT ra_status_t rac_stt_set_callback(ra_stt_session_t* s,
                                                    ra_transcript_callback_t cb, void* ud) {
    return ra_stt_set_callback(s, cb, ud);
}

/* --- TTS ---------------------------------------------------------------- */
RA_COMPAT_EXPORT ra_status_t rac_tts_create(const ra_model_spec_t* s,
                                              const ra_session_config_t* c,
                                              ra_tts_session_t** o) {
    return ra_tts_create(s, c, o);
}
RA_COMPAT_EXPORT void rac_tts_destroy(ra_tts_session_t* s) { ra_tts_destroy(s); }
RA_COMPAT_EXPORT ra_status_t rac_tts_synthesize(ra_tts_session_t* s, const char* t,
                                                  float* out, int32_t max,
                                                  int32_t* written, int32_t* sr) {
    return ra_tts_synthesize(s, t, out, max, written, sr);
}
RA_COMPAT_EXPORT ra_status_t rac_tts_cancel(ra_tts_session_t* s) { return ra_tts_cancel(s); }

/* --- VAD ---------------------------------------------------------------- */
RA_COMPAT_EXPORT ra_status_t rac_vad_create(const ra_model_spec_t* s,
                                              const ra_session_config_t* c,
                                              ra_vad_session_t** o) {
    return ra_vad_create(s, c, o);
}
RA_COMPAT_EXPORT void rac_vad_destroy(ra_vad_session_t* s) { ra_vad_destroy(s); }
RA_COMPAT_EXPORT ra_status_t rac_vad_feed_audio(ra_vad_session_t* s, const float* p,
                                                  int32_t n, int32_t sr) {
    return ra_vad_feed_audio(s, p, n, sr);
}
RA_COMPAT_EXPORT ra_status_t rac_vad_set_callback(ra_vad_session_t* s,
                                                    ra_vad_callback_t cb, void* ud) {
    return ra_vad_set_callback(s, cb, ud);
}

/* --- Embed -------------------------------------------------------------- */
RA_COMPAT_EXPORT ra_status_t rac_embed_create(const ra_model_spec_t* s,
                                                const ra_session_config_t* c,
                                                ra_embed_session_t** o) {
    return ra_embed_create(s, c, o);
}
RA_COMPAT_EXPORT void rac_embed_destroy(ra_embed_session_t* s) { ra_embed_destroy(s); }
RA_COMPAT_EXPORT ra_status_t rac_embed_text(ra_embed_session_t* s, const char* t,
                                              float* out, int32_t d) {
    return ra_embed_text(s, t, out, d);
}
RA_COMPAT_EXPORT int32_t rac_embed_dims(ra_embed_session_t* s) { return ra_embed_dims(s); }

/* --- Wake word ---------------------------------------------------------- */
RA_COMPAT_EXPORT ra_status_t rac_ww_create(const ra_model_spec_t* s, const char* kw,
                                             float th, ra_ww_session_t** o) {
    return ra_ww_create(s, kw, th, o);
}
RA_COMPAT_EXPORT void rac_ww_destroy(ra_ww_session_t* s) { ra_ww_destroy(s); }
RA_COMPAT_EXPORT ra_status_t rac_ww_feed_audio(ra_ww_session_t* s, const float* p,
                                                 int32_t n, int32_t sr, uint8_t* d) {
    return ra_ww_feed_audio(s, p, n, sr, d);
}

/* --- Version / status / lifecycle --------------------------------------- */
RA_COMPAT_EXPORT unsigned int rac_abi_version(void)         { return ra_abi_version(); }
RA_COMPAT_EXPORT unsigned int rac_plugin_api_version(void)  { return ra_plugin_api_version(); }
RA_COMPAT_EXPORT const char*  rac_build_info(void)          { return ra_build_info(); }
RA_COMPAT_EXPORT const char*  rac_status_string(ra_status_t s) { return ra_status_str(s); }
RA_COMPAT_EXPORT const char*  rac_error_string(ra_status_t s)  { return ra_status_str(s); }
RA_COMPAT_EXPORT const char*  rac_extended_error_string(ra_extended_error_t c) {
    return ra_extended_error_str(c);
}
RA_COMPAT_EXPORT const char*  rac_lifecycle_state_string(ra_lifecycle_state_t s) {
    return ra_lifecycle_state_str(s);
}

#ifdef __cplusplus
}  /* extern "C" */
#endif
