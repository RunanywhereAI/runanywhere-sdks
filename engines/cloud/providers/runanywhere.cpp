/**
 * @file providers/runanywhere.cpp
 * @brief RunAnywhere backend-proxy adapter for the `cloud` engine's STT modality.
 *
 * This provider REPLACES the direct-to-vendor Sarvam adapter. The device never
 * holds a speech-provider credential: audio goes to the RunAnywhere backend
 * (`POST {base_url}/api/v1/sdk/stt/transcribe`), authenticated with the SDK's
 * own device access token, and the backend holds the upstream (Gemini) key,
 * enforces the per-key hybrid_stt entitlement, and meters the monthly quota.
 *
 * Wire shape (deliberately identical to the old Sarvam multipart contract so
 * the shared writer is reused byte-for-byte):
 *   POST {base_url}/api/v1/sdk/stt/transcribe
 *   header: Authorization: Bearer <device access token>   (fresh per request)
 *   body:   multipart/form-data { file, model, language_code }
 *   resp:   {"transcript": ..., "model": ..., "audio_duration_ms": ...}
 *
 * base_url is empty here on purpose: the shared core falls back to the SDK's
 * configured backend (rac_state_get_base_url()), so dev/staging/prod need no
 * per-provider configuration. config_json{"base_url"} still overrides for
 * tests.
 *
 * The provider table + find_cloud_stt_provider() live here (single-provider
 * file, same layout the Sarvam file had); a second provider just appends its
 * CloudSttProvider to the table.
 */

#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

#include "../cloud_stt_provider.h"

namespace rac::cloud_stt {
namespace {

rac_result_t runanywhere_build_request(const CloudSttImpl*      impl,
                                       const void*              audio,
                                       size_t                   audio_size,
                                       const std::string&       language_code,
                                       const rac_stt_options_t* options,
                                       HttpRequestParts*        out_parts) {
    if (impl == nullptr || out_parts == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const rac_audio_format_enum_t fmt =
        (options != nullptr) ? options->audio_format : RAC_AUDIO_FORMAT_WAV;

    // `model` is advisory: the backend chooses the served model and ignores the
    // field, but it stays on the wire for parity with the old provider contract
    // and for request attribution in backend logs.
    const std::vector<std::pair<std::string, std::string>> text_fields = {
        {"model", impl->model},
        {"language_code", language_code},  // empty -> skipped by the shared writer
    };
    return cloud_stt_build_multipart_default("file", audio, audio_size, fmt, text_fields,
                                             out_parts);
}

rac_result_t runanywhere_parse_response(const rac_http_response_t* resp,
                                        rac_stt_result_t*          out_result,
                                        int64_t                    elapsed_ms) {
    // Flat JSON; no language echo (the proxy does not detect language today).
    return cloud_stt_parse_flat_json(resp, /*text_key=*/"transcript",
                                     /*lang_key=*/nullptr, out_result, elapsed_ms);
}

constexpr CloudSttProvider k_runanywhere_provider = {
    /* name                  */ "runanywhere",
    /* default_base_url      */ "",  // resolved from the SDK's configured backend
    /* default_path          */ "/api/v1/sdk/stt/transcribe",
    /* auth_header_name      */ "Authorization",
    /* auth_value_template   */ "Bearer {key}",
    /* auth_from_sdk_session */ true,
    /* build_request         */ runanywhere_build_request,
    /* parse_response        */ runanywhere_parse_response,
};

constexpr const CloudSttProvider* g_cloud_stt_providers[] = {
    &k_runanywhere_provider,
};

}  // namespace

const CloudSttProvider* find_cloud_stt_provider(const std::string& name) {
    for (const CloudSttProvider* p : g_cloud_stt_providers) {
        if (p != nullptr && p->name != nullptr && name == p->name) {
            return p;
        }
    }
    return nullptr;
}

}  // namespace rac::cloud_stt
