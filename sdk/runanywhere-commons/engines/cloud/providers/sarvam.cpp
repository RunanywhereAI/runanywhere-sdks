/**
 * @file providers/sarvam.cpp
 * @brief Sarvam adapter for the `cloud` engine's STT modality — the FIRST provider.
 *
 * Sarvam exposes the Saarika/Saaras multilingual STT family behind a multipart
 * upload endpoint. This file carries ONLY the Sarvam-specific wire bits; all the
 * HTTP/multipart/JSON plumbing lives in the shared core (rac_stt_cloud.cpp) and
 * is reused here verbatim through cloud_stt_build_multipart_default /
 * cloud_stt_parse_flat_json.
 *
 * Wire shape (unchanged from the pre-generalization Sarvam backend):
 *   POST {base_url}/speech-to-text
 *   header: api-subscription-key: <key>
 *   body:   multipart/form-data { file, model, language_code }
 *   resp:   {"request_id": ..., "transcript": ..., "language_code": ...}
 *
 * The provider table (g_cloud_stt_providers[]) + find_cloud_stt_provider() also
 * live here for now since Sarvam is the only entry; a second provider just
 * appends its CloudSttProvider to the table.
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

// Sarvam build_request — relocated from the original build_multipart_body.
//
// Same multipart shape as before: one `file` part (audio bytes + format-derived
// MIME/extension) then a `model` text field and, when present, a `language_code`
// text field. The shared writer reproduces the original byte layout; the empty-
// language skip is preserved by cloud_stt_build_multipart_default (it drops
// empty-valued text fields).
rac_result_t sarvam_build_request(const CloudSttImpl*      impl,
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

    const std::vector<std::pair<std::string, std::string>> text_fields = {
        {"model", impl->model},
        {"language_code", language_code},  // empty -> skipped by the shared writer
    };
    return cloud_stt_build_multipart_default("file", audio, audio_size, fmt, text_fields,
                                             out_parts);
}

// Sarvam parse_response — relocated from the original parse_response.
//
// Reads `transcript` + `language_code` from the flat JSON body. The shared
// decoder now sets confidence to NaN (the cloud "no-signal" value) instead of
// the old RAC_STT_DEFAULT_CONFIDENCE (0.9) — the only behavioral change vs the
// pre-generalization backend, and the documented hybrid-router contract.
rac_result_t sarvam_parse_response(const rac_http_response_t* resp,
                                   rac_stt_result_t*          out_result,
                                   int64_t                    elapsed_ms) {
    return cloud_stt_parse_flat_json(resp, /*text_key=*/"transcript",
                                     /*lang_key=*/"language_code", out_result, elapsed_ms);
}

// Sarvam provider descriptor — the genuinely Sarvam-specific data.
constexpr CloudSttProvider k_sarvam_provider = {
    /* name                */ "sarvam",
    /* default_base_url     */ "https://api.sarvam.ai",
    /* default_path         */ "/speech-to-text",
    /* auth_header_name     */ "api-subscription-key",
    /* auth_value_template  */ "{key}",  // raw key (no scheme prefix)
    /* build_request        */ sarvam_build_request,
    /* parse_response       */ sarvam_parse_response,
};

// Provider table + lookup.
//
// Process-static; add a second provider by appending its CloudSttProvider here.
constexpr const CloudSttProvider* g_cloud_stt_providers[] = {
    &k_sarvam_provider,
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
