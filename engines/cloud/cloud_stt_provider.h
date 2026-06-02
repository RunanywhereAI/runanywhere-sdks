/**
 * @file cloud_stt_provider.h
 * @brief The STT-modality provider-adapter contract for the `cloud` engine.
 *
 * This is the STT MODALITY of the modality-agnostic `cloud` engine (engine
 * identity lives in rac_plugin_entry_cloud.*); its `stt` naming is intentional.
 * The cloud STT modality is ONE generic speech-to-text path whose wire behavior
 * is chosen at create() time via config_json["provider"]. It is a shared
 * HTTP/multipart core (request issue, timeout/header assembly, multipart writer,
 * MIME map, JSON decode helpers) plus a small per-provider adapter that supplies
 * only the genuinely provider-specific bits:
 *
 *   - default base URL / endpoint path
 *   - auth header name + value template (e.g. Sarvam: "api-subscription-key" + "{key}")
 *   - build_request:  fills the HTTP body + content-type for one transcribe call
 *   - parse_response: decodes the provider's JSON into a rac_stt_result_t
 *
 * Sarvam is the first adapter (providers/sarvam.cpp). New providers add a data
 * struct + (often) a one-line call to the shared default helpers below.
 *
 * This header is engine-internal (lives under engines/cloud_stt/, not in the
 * public include/ tree): only the engine TUs and its provider adapters include
 * it.
 */

#ifndef RAC_ENGINES_CLOUD_STT_PROVIDER_H
#define RAC_ENGINES_CLOUD_STT_PROVIDER_H

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace rac::cloud_stt {

// -----------------------------------------------------------------------------
// Engine-wide defaults
// -----------------------------------------------------------------------------

// "unknown" is Sarvam's documented auto-detect language sentinel and a benign
// default for any flat-JSON provider that accepts an optional language field;
// providers that need a different default can override it from config or skip
// the language part entirely in their build_request.
inline constexpr const char* kDefaultLanguage  = "unknown";
inline constexpr int32_t     kDefaultTimeoutMs = 30000;

// -----------------------------------------------------------------------------
// CloudSttImpl — the per-instance engine state
// -----------------------------------------------------------------------------

struct CloudSttProvider;  // fwd-decl; full definition below.

/**
 * @brief Per-service engine state.
 *
 * Holds the selected provider adapter plus the resolved connection knobs. The
 * adapter pointer (`provider`) is a pointer into the process-static provider
 * table and is never owned/freed by the impl. `base_url` / `path` start from
 * the provider's defaults and may be overridden via config_json.
 */
struct CloudSttImpl {
    const CloudSttProvider* provider = nullptr;  // borrowed; static table entry

    std::string api_key;
    std::string model;
    std::string language_code;
    std::string base_url;  // resolved: provider default unless config overrides
    std::string path;      // resolved: provider default unless config overrides

    int32_t           timeout_ms = kDefaultTimeoutMs;
    std::atomic<bool> cancelled{false};
    std::mutex        http_mutex;
};

// -----------------------------------------------------------------------------
// HttpRequestParts — what an adapter's build_request fills in
// -----------------------------------------------------------------------------

/**
 * @brief Provider-built pieces of a single HTTP transcribe request.
 *
 * The shared core owns URL assembly (base_url + path), auth header injection,
 * timeout, and the actual rac_http_request_send call. The adapter only fills:
 *   - `body`         : the serialized request body (e.g. multipart bytes)
 *   - `content_type` : the value for the Content-Type header (includes the
 *                      multipart boundary when applicable)
 */
struct HttpRequestParts {
    std::vector<uint8_t> body;
    std::string          content_type;
};

// -----------------------------------------------------------------------------
// CloudSttProvider — the adapter vtable
// -----------------------------------------------------------------------------

/**
 * @brief A cloud STT provider adapter.
 *
 * One process-static instance per supported provider, gathered into
 * g_cloud_stt_providers[] (see providers/sarvam.cpp) and looked up by name via
 * find_cloud_stt_provider().
 *
 * The string fields carry the provider's defaults; create() copies the relevant
 * ones into CloudSttImpl (where config_json may override base_url / path). The
 * two function pointers are the only required behavior — everything else is
 * shared plumbing the callbacks reuse.
 */
struct CloudSttProvider {
    const char* name;                 // e.g. "sarvam"
    const char* default_base_url;     // e.g. "https://api.sarvam.ai"
    const char* default_path;         // e.g. "/speech-to-text"
    const char* auth_header_name;     // e.g. "api-subscription-key"
    const char* auth_value_template;  // e.g. "{key}" (Sarvam); "Bearer {key}", "Token {key}"

    /**
     * Build the request body + content-type for one transcribe call. The
     * resolved per-call language (options override or impl default) is passed in
     * so adapters do not re-derive it. Audio format comes from `options`.
     */
    rac_result_t (*build_request)(const CloudSttImpl*       impl,
                                  const void*               audio,
                                  size_t                    audio_size,
                                  const std::string&        language_code,
                                  const rac_stt_options_t*  options,
                                  HttpRequestParts*         out_parts);

    /**
     * Decode a 2xx provider response body into out_result. `elapsed_ms` is the
     * measured round-trip; the adapter stamps it into processing_time_ms.
     * Confidence MUST be set to NaN when the provider returns no per-result
     * confidence (cloud "no-signal" contract for the hybrid router).
     */
    rac_result_t (*parse_response)(const rac_http_response_t* resp,
                                   rac_stt_result_t*          out_result,
                                   int64_t                    elapsed_ms);
};

// -----------------------------------------------------------------------------
// Provider table lookup (defined in providers/sarvam.cpp)
// -----------------------------------------------------------------------------

/**
 * @brief Look up a provider adapter by name (case-sensitive, exact match).
 * @return The static adapter, or nullptr if no provider matches.
 */
const CloudSttProvider* find_cloud_stt_provider(const std::string& name);

// -----------------------------------------------------------------------------
// Shared helpers reused by every adapter
// -----------------------------------------------------------------------------

/**
 * @brief NaN confidence sentinel.
 *
 * Cloud STT results carry NO meaningful per-result confidence; the hybrid
 * router contract documents that as NaN ("no signal") so a cloud result never
 * wrongly triggers or suppresses a cascade. Use this anywhere a provider would
 * otherwise leave confidence unset.
 */
float cloud_stt_no_confidence();

/**
 * @brief malloc + copy a std::string into a NUL-terminated C string.
 * @return Heap buffer (free with the matching rac_free path) or nullptr on OOM.
 */
char* cloud_stt_dup_cstr(const std::string& s);

/**
 * @brief Default multipart/form-data body builder.
 *
 * Writes one file part plus an arbitrary set of text fields, in order, using a
 * freshly generated boundary; sets out_parts->content_type to
 * "multipart/form-data; boundary=...". The file field name, the audio bytes,
 * and the chosen audio_format (-> MIME type + extension) come from the caller.
 *
 * This is the generalized form of Sarvam's original build_multipart_body: a
 * simple provider supplies its file field name + (name,value) text fields and
 * needs nothing else.
 *
 * @param file_field   multipart field name for the audio part (e.g. "file").
 * @param audio        audio bytes.
 * @param audio_size   length of `audio`.
 * @param fmt          audio container -> MIME/type + filename extension.
 * @param text_fields  ordered (name, value) text parts; entries whose value is
 *                     empty are skipped (matches Sarvam's optional-field rule).
 * @param out_parts    receives body + content_type.
 */
rac_result_t cloud_stt_build_multipart_default(
    const std::string&                                            file_field,
    const void*                                                   audio,
    size_t                                                        audio_size,
    rac_audio_format_enum_t                                       fmt,
    const std::vector<std::pair<std::string, std::string>>&       text_fields,
    HttpRequestParts*                                             out_parts);

/**
 * @brief Default flat-JSON response parser.
 *
 * Parses a 2xx body as a flat JSON object and reads:
 *   - out_result->text             from json[text_key]   (required to exist;
 *                                  missing -> empty string, like Sarvam)
 *   - out_result->detected_language from json[lang_key]  (optional; lang_key may
 *                                  be empty/"" to skip language extraction)
 * Sets confidence to NaN (cloud_stt_no_confidence) and processing_time_ms to
 * `elapsed_ms`. HTTP status / empty-body checks are handled by the shared
 * issue path BEFORE this is called, but the function still guards a null/empty
 * body defensively.
 *
 * This is the generalized form of Sarvam's original parse_response.
 */
rac_result_t cloud_stt_parse_flat_json(const rac_http_response_t* resp,
                                       const char*                text_key,
                                       const char*                lang_key,
                                       rac_stt_result_t*          out_result,
                                       int64_t                    elapsed_ms);

}  // namespace rac::cloud_stt

#endif  // RAC_ENGINES_CLOUD_STT_PROVIDER_H
