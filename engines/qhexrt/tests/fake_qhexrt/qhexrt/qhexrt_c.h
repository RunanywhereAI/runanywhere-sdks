// Minimal QHexRT C ABI used by the host-only session serialization test.
// Production builds include the real staged QHexRT header instead.
#ifndef RUNANYWHERE_TEST_FAKE_QHEXRT_C_H
#define RUNANYWHERE_TEST_FAKE_QHEXRT_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct qhx_model qhx_model;
typedef struct qhx_session qhx_session;
typedef int qhx_status;

typedef int (*qhx_token_cb)(void* user, const char* utf8, int len, int token_id, int is_final);

typedef struct {
    float temperature;
    int top_k;
    float top_p;
    float min_p;
    float repetition_penalty;
    int repetition_window;
    uint64_t seed;
    int max_new_tokens;
    const char* const* stop_strings;
    int n_stop_strings;
    const int32_t* stop_token_ids;
    int n_stop_token_ids;
    const char* grammar;
    int grammar_kind;
} qhx_gen_cfg;

typedef struct {
    const char* text;
    const char* system_prompt;
    const char* const* history;
    int n_history;
    int no_template;
    const char* image_path;
    const uint8_t* image_data;
    int image_size;
    const char* mask_path;
    const float* audio;
    int n_audio;
    int audio_sr;
    int disable_thinking;
} qhx_inputs;

typedef struct {
    qhx_status status;
    const char* text;
    int n_generated;
    int n_prompt;
    double prefill_ms;
    double decode_ms;
    const float* audio;
    int n_audio;
    uint32_t sample_rate;
    const float* embedding;
    int n_embedding;
    const uint8_t* image;
    int img_h;
    int img_w;
    int img_c;
} qhx_output;

void qhx_session_reset(qhx_session* session);
void qhx_session_cancel(qhx_session* session);
void qhx_gen_cfg_default(qhx_gen_cfg* cfg);
qhx_status qhx_generate(qhx_session* session, const qhx_inputs* inputs, const qhx_gen_cfg* cfg,
                        qhx_token_cb callback, void* user, qhx_output* output);
const char* qhx_status_str(qhx_status status);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RUNANYWHERE_TEST_FAKE_QHEXRT_C_H
