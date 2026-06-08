/**
 * @file rac_proto_adapters.h
 * @brief RunAnywhere Commons - C ABI <-> Proto adapters.
 *
 * Field-by-field adapters between the legacy C ABI structs (rac_*_t) and the
 * canonical wire-format proto messages declared under idl/ (and generated to
 * src/generated/proto/<name>.pb.h). The C ABI structs are unchanged — these
 * adapters only move bytes back and forth.
 *
 * Compilation contract:
 *   - When the library is built with Protobuf available
 *     (RAC_HAVE_PROTOBUF defined by the root CMake when `protoc`'s C++ output
 *     under `src/generated/proto/` is linked), every adapter below is a real,
 *     symbol-emitting function.
 *   - When Protobuf is NOT available, these declarations are still visible
 *     (so headers compile) but resolve to no-op stubs in the .cpp that always
 *     return false. Callers SHOULD guard usage with `#ifdef RAC_HAVE_PROTOBUF`
 *     when they need a real conversion.
 *
 * Conventions:
 *   - All adapters return `bool` — true on success, false on failure (NULL
 *     pointer or otherwise unmappable input). Callers MUST check.
 *   - Adapters NEVER own memory in the destination object beyond what proto's
 *     own arena/string ownership rules dictate. C-side outputs must be
 *     pre-allocated by the caller; the adapter only copies fields.
 *   - For C-side `bytes` outputs (e.g. tts audio_data, diffusion image_data,
 *     vlm raw_rgb pixel buffer), `*_from_proto` allocates with rac_alloc and
 *     the caller is responsible for calling rac_free.
 *   - For C-side repeated outputs (words, alternatives, phoneme_timestamps,
 *     vectors, retrieved_chunks, models), `*_from_proto` allocates an array
 *     with rac_alloc; the caller frees with the corresponding `*_free`
 *     function (or rac_free + per-element string free).
 *   - Optional proto fields with sentinel-bearing C counterparts map as:
 *       proto unset / 0  -> C sentinel value (-1, 0, "" depending on field)
 *       proto set        -> C value
 *     Inverse direction maps the C sentinel back to proto unset.
 *
 * Drift table (see .cpp for inline notes per adapter):
 *   - STTLanguage        : C uses BCP-47 string ("en-US"), proto uses enum.
 *                          Adapter strips region, looks up base code (see
 *                          stt_language_from_string / stt_language_to_string).
 *                          STT_LANGUAGE_UNSPECIFIED maps to "" / NULL.
 *   - VAD frame_length   : C uses float seconds (0.1), proto uses int32 ms.
 *                          Adapter multiplies / divides by 1000 with clamping.
 *   - VAD threshold      : C `energy_threshold_override` uses -1.0f sentinel,
 *                          proto `threshold` uses 0.0 (unset). Adapter maps
 *                          0.0 -> -1.0f and vice versa.
 *   - TTS speaking_rate  : C struct has `rate`; proto names it speaking_rate.
 *                          Pure rename — no value conversion.
 *   - TTS use_ssml       : C struct has `use_ssml`; proto names it enable_ssml.
 *                          Pure rename.
 *   - Diffusion seed=-1  : C uses -1 for "random", proto preserves -1 verbatim.
 *   - VLM image          : C struct carries pointer + format enum; proto uses
 *                          oneof source. Adapter inspects rac_vlm_image_t.format
 *                          and writes the matching oneof case.
 *   - Diffusion scheduler: C has DPM_PP_2M_SDE (=2) which the proto deliberately
 *                          drops in favour of folding to DPMPP_2M. Adapter
 *                          collapses C SDE -> proto DPMPP_2M.
 *   - Diffusion variant 0: C `RAC_DIFFUSION_MODEL_SD_1_5 = 0` collides with
 *                          proto `DIFFUSION_MODEL_VARIANT_UNSPECIFIED = 0`.
 *                          Adapter offsets by +1 in to-proto direction
 *                          (and SD_1_5 is the documented default when proto is
 *                          UNSPECIFIED).
 *   - Errors             : C `rac_result_t` is a signed negative int (e.g.
 *                          -110 for MODEL_NOT_FOUND); proto ErrorCode enum
 *                          mirrors absolute magnitudes. Adapter: code =
 *                          abs(rac_result), c_abi_code = rac_result.
 *   - Storage device.used_percent: C struct has no pre-computed percent;
 *                                  adapter computes used / total * 100.0f
 *                                  on the to-proto path.
 *
 * Files:
 *   - sdk/runanywhere-commons/include/rac/foundation/rac_proto_adapters.h (this file)
 *   - sdk/runanywhere-commons/src/foundation/rac_proto_adapters.cpp
 */

#ifndef RAC_PROTO_ADAPTERS_H
#define RAC_PROTO_ADAPTERS_H

// Newer libc++ on macOS no longer transitively pulls <cstddef> into other
// headers. Several google/protobuf and absl headers reference ::ptrdiff_t
// without `std::` — we must include the C <stddef.h> (which defines the
// type in the global namespace) before any *.pb.h.
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
#endif

#include "rac/core/rac_structured_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"

// foundation/ MUST NOT depend on features/.
// The per-modality adapter declarations that previously lived in this
// header (and forced six features/ includes) now live alongside their
// C ABI type headers:
//   - rac/features/stt/rac_stt_proto_adapters.h
//   - rac/features/tts/rac_tts_proto_adapters.h
//   - rac/features/vad/rac_vad_proto_adapters.h
//   - rac/features/vlm/rac_vlm_proto_adapters.h
//   - rac/features/diffusion/rac_diffusion_proto_adapters.h
//   - rac/features/embeddings/rac_embeddings_proto_adapters.h
// This header retains only adapters for cross-cutting types (LoRA,
// Storage, Errors) whose C ABI types live in core/ or infrastructure/.

#ifdef __cplusplus

// Proto types are forward-declared here instead of included via
// the generated `*.pb.h` headers. This keeps `runanywhere::v1::*` symbols and
// the entire google::protobuf / absl transitive include set OUT of the public
// interface of rac_commons — L5 consumers (Swift CRACommons, Kotlin JNI, Web,
// Flutter, RN) include `rac_proto_adapters.h` indirectly and must not pull in
// protobuf. The `#include` of the generated headers now lives in
// rac_proto_adapters.cpp, which sees them via the PRIVATE include path
// configured in CMakeLists.txt.
//
// Forward declarations are sufficient because every adapter parameter is
// either a pointer-to-proto or a const-ref-to-proto. The only by-value uses
// are the two scoped enums `ErrorCode` / `ErrorCategory`, which we forward
// declare with their explicit `: int` underlying type so the compiler knows
// their size at the function-prototype site.

namespace runanywhere::v1 {

// LoRA
class LoraAdapterCatalogEntry;
class LoRAAdapterInfo;

// Storage
class DeviceStorageInfo;
class AppStorageInfo;
class ModelStorageMetrics;
class StorageInfo;
class StorageAvailability;

// Errors — these are scoped enums that some adapter functions accept /
// return by value; the explicit underlying type makes the forward
// declaration usable at the function-prototype site.
class SDKError;
enum ErrorCode : int;
enum ErrorCategory : int;

}  // namespace runanywhere::v1

namespace rac::foundation {

// ===========================================================================
// LoRA
// ===========================================================================

bool rac_lora_entry_to_proto(const rac_lora_entry_t* in,
                             ::runanywhere::v1::LoraAdapterCatalogEntry* out);
bool rac_lora_entry_from_proto(const ::runanywhere::v1::LoraAdapterCatalogEntry& in,
                               rac_lora_entry_t* out);

// ===========================================================================
// STORAGE
// ===========================================================================

bool rac_device_storage_to_proto(const rac_device_storage_t* in,
                                 ::runanywhere::v1::DeviceStorageInfo* out);
bool rac_device_storage_from_proto(const ::runanywhere::v1::DeviceStorageInfo& in,
                                   rac_device_storage_t* out);

bool rac_app_storage_to_proto(const rac_app_storage_t* in, ::runanywhere::v1::AppStorageInfo* out);
bool rac_app_storage_from_proto(const ::runanywhere::v1::AppStorageInfo& in,
                                rac_app_storage_t* out);

bool rac_model_storage_metrics_to_proto(const rac_model_storage_metrics_t* in,
                                        ::runanywhere::v1::ModelStorageMetrics* out);
bool rac_model_storage_metrics_from_proto(const ::runanywhere::v1::ModelStorageMetrics& in,
                                          rac_model_storage_metrics_t* out);

// ===========================================================================
// ERRORS
// ===========================================================================

// Convert a single rac_result_t error code to the proto ErrorCode enum.
// Returns ERROR_CODE_UNSPECIFIED for unknown / unmapped codes.
::runanywhere::v1::ErrorCode rac_result_to_proto_error_code(rac_result_t code);

// Inverse: convert proto ErrorCode (positive) back to the canonical signed
// rac_result_t. Returns 0 (RAC_SUCCESS) for ERROR_CODE_UNSPECIFIED.
rac_result_t rac_proto_error_code_to_result(::runanywhere::v1::ErrorCode code);

// Convert C category enum to proto category. Folds modality categories
// (STT/TTS/LLM/...) into ERROR_CATEGORY_COMPONENT per the canonicalized
// 9-bucket scheme; transport / lifecycle map to their own bucket.
::runanywhere::v1::ErrorCategory rac_category_to_proto(rac_error_category_t category);
rac_error_category_t rac_proto_to_category(::runanywhere::v1::ErrorCategory category);

}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_PROTO_ADAPTERS_H
