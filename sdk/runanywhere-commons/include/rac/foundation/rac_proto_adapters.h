/**
 * @file rac_proto_adapters.h
 * @brief RunAnywhere Commons - C ABI <-> Proto adapters (Phase C6).
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
 * Coverage (Phase C6 deliverable):
 *   - STT  : config <-> proto STTConfiguration
 *            options <-> proto STTOptions (with STTLanguage enum mapping)
 *            output  <-> proto STTOutput  (rac_stt_output_t / rac_stt_result_t)
 *            word    <-> proto WordTimestamp
 *            metadata<-> proto TranscriptionMetadata
 *            alternative <-> proto TranscriptionAlternative
 *   - TTS  : config <-> proto TTSConfiguration
 *            options <-> proto TTSOptions
 *            output  <-> proto TTSOutput  (rac_tts_output_t / rac_tts_result_t)
 *            speak_result <-> proto TTSSpeakResult
 *            phoneme <-> proto TTSPhonemeTimestamp
 *            metadata<-> proto TTSSynthesisMetadata
 *   - VAD  : config <-> proto VADConfiguration
 *            options <-> proto VADOptions    (synthesized from input override)
 *            output  <-> proto VADResult
 *            statistics <-> proto VADStatistics
 *            speech_activity <-> proto SpeechActivityEvent
 *   - VLM  : config  <-> proto VLMConfiguration
 *            options <-> proto VLMGenerationOptions (subset)
 *            result  <-> proto VLMResult
 *            image   <-> proto VLMImage (oneof source)
 *   - Diffusion: config <-> proto DiffusionConfiguration
 *                options <-> proto DiffusionGenerationOptions
 *                result  <-> proto DiffusionResult
 *                progress<-> proto DiffusionProgress
 *   - LoRA : adapter entry <-> proto LoraAdapterCatalogEntry
 *            adapter info  <-> proto LoRAAdapterInfo (limited; C side has no info struct)
 *   - RAG  : config <-> proto RAGConfiguration
 *            query  <-> proto RAGQueryOptions
 *            result <-> proto RAGResult (with retrieved_chunks)
 *            search_result <-> proto RAGSearchResult
 *   - Embeddings: config <-> proto EmbeddingsConfiguration
 *                 options <-> proto EmbeddingsOptions
 *                 vector  <-> proto EmbeddingVector
 *                 result  <-> proto EmbeddingsResult
 *   - Storage: device <-> proto DeviceStorageInfo
 *              app    <-> proto AppStorageInfo
 *              metrics<-> proto ModelStorageMetrics
 *              info   <-> proto StorageInfo
 *              avail  <-> proto StorageAvailability
 *   - Errors: structured error <-> proto SDKError (+ context map)
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
 * Drift table (recorded for the Phase C6 deliverable; see .cpp for inline
 * notes per adapter):
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
 * Files added in Phase C6:
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

#include "rac/core/rac_types.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/vlm/rac_vlm_types.h"
#include "rac/features/diffusion/rac_diffusion_types.h"
#include "rac/features/embeddings/rac_embeddings_types.h"
#include "rac/features/rag/rac_rag_pipeline.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"

#ifdef __cplusplus

// Proto type forward declarations — only included when Protobuf is available.
// Keeps the header portable for C consumers that compile without protobuf.
#ifdef RAC_HAVE_PROTOBUF

#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "vad_options.pb.h"
#include "vlm_options.pb.h"
#include "diffusion_options.pb.h"
#include "embeddings_options.pb.h"
#include "rag.pb.h"
#include "storage_types.pb.h"
#include "lora_options.pb.h"
#include "errors.pb.h"

namespace rac::foundation {

// ===========================================================================
// STT
// ===========================================================================

bool rac_stt_config_to_proto(const rac_stt_config_t* in,
                             ::runanywhere::v1::STTConfiguration* out);
bool rac_stt_config_from_proto(const ::runanywhere::v1::STTConfiguration& in,
                               rac_stt_config_t* out);

bool rac_stt_options_to_proto(const rac_stt_options_t* in,
                              ::runanywhere::v1::STTOptions* out);
bool rac_stt_options_from_proto(const ::runanywhere::v1::STTOptions& in,
                                rac_stt_options_t* out);

bool rac_stt_word_to_proto(const rac_stt_word_t* in,
                           ::runanywhere::v1::WordTimestamp* out);
bool rac_stt_word_from_proto(const ::runanywhere::v1::WordTimestamp& in,
                             rac_stt_word_t* out);

bool rac_transcription_metadata_to_proto(const rac_transcription_metadata_t* in,
                                         ::runanywhere::v1::TranscriptionMetadata* out);
bool rac_transcription_metadata_from_proto(
    const ::runanywhere::v1::TranscriptionMetadata& in,
    rac_transcription_metadata_t* out);

bool rac_transcription_alternative_to_proto(
    const rac_transcription_alternative_t* in,
    ::runanywhere::v1::TranscriptionAlternative* out);
bool rac_transcription_alternative_from_proto(
    const ::runanywhere::v1::TranscriptionAlternative& in,
    rac_transcription_alternative_t* out);

// rac_stt_output_t is the canonical STT output and aliases rac_stt_transcription_result_t.
// The proto STTOutput does not carry a wall-clock timestamp_ms field; we drop
// it on the to-proto path. metadata.processing_time_ms stays.
bool rac_stt_output_to_proto(const rac_stt_output_t* in,
                             ::runanywhere::v1::STTOutput* out);
bool rac_stt_output_from_proto(const ::runanywhere::v1::STTOutput& in,
                               rac_stt_output_t* out);

// rac_stt_result_t is a smaller projection (text + words + lang + confidence
// + processing_time_ms) than rac_stt_output_t. Adapter folds processing_time_ms
// into proto metadata, leaves audio_length_ms unset.
bool rac_stt_result_to_proto(const rac_stt_result_t* in,
                             ::runanywhere::v1::STTOutput* out);
bool rac_stt_result_from_proto(const ::runanywhere::v1::STTOutput& in,
                               rac_stt_result_t* out);

// ===========================================================================
// TTS
// ===========================================================================

bool rac_tts_config_to_proto(const rac_tts_config_t* in,
                             ::runanywhere::v1::TTSConfiguration* out);
bool rac_tts_config_from_proto(const ::runanywhere::v1::TTSConfiguration& in,
                               rac_tts_config_t* out);

bool rac_tts_options_to_proto(const rac_tts_options_t* in,
                              ::runanywhere::v1::TTSOptions* out);
bool rac_tts_options_from_proto(const ::runanywhere::v1::TTSOptions& in,
                                rac_tts_options_t* out);

bool rac_tts_phoneme_timestamp_to_proto(const rac_tts_phoneme_timestamp_t* in,
                                        ::runanywhere::v1::TTSPhonemeTimestamp* out);
bool rac_tts_phoneme_timestamp_from_proto(
    const ::runanywhere::v1::TTSPhonemeTimestamp& in,
    rac_tts_phoneme_timestamp_t* out);

bool rac_tts_synthesis_metadata_to_proto(
    const rac_tts_synthesis_metadata_t* in,
    ::runanywhere::v1::TTSSynthesisMetadata* out);
bool rac_tts_synthesis_metadata_from_proto(
    const ::runanywhere::v1::TTSSynthesisMetadata& in,
    rac_tts_synthesis_metadata_t* out);

bool rac_tts_output_to_proto(const rac_tts_output_t* in,
                             ::runanywhere::v1::TTSOutput* out);
bool rac_tts_output_from_proto(const ::runanywhere::v1::TTSOutput& in,
                               rac_tts_output_t* out);

bool rac_tts_result_to_proto(const rac_tts_result_t* in,
                             ::runanywhere::v1::TTSOutput* out);
bool rac_tts_result_from_proto(const ::runanywhere::v1::TTSOutput& in,
                               rac_tts_result_t* out);

bool rac_tts_speak_result_to_proto(const rac_tts_speak_result_t* in,
                                   ::runanywhere::v1::TTSSpeakResult* out);
bool rac_tts_speak_result_from_proto(const ::runanywhere::v1::TTSSpeakResult& in,
                                     rac_tts_speak_result_t* out);

// ===========================================================================
// VAD
// ===========================================================================

bool rac_vad_config_to_proto(const rac_vad_config_t* in,
                             ::runanywhere::v1::VADConfiguration* out);
bool rac_vad_config_from_proto(const ::runanywhere::v1::VADConfiguration& in,
                               rac_vad_config_t* out);

// VAD has no first-class C "options" struct — the closest is
// rac_vad_input_t::energy_threshold_override. We expose two adapters:
//   - input -> proto VADOptions (only the threshold field; gates are
//     constants in C ABI)
//   - proto VADOptions -> input (writes threshold; ignores gates which
//     callers must enforce themselves)
bool rac_vad_input_to_proto_options(const rac_vad_input_t* in,
                                    ::runanywhere::v1::VADOptions* out);
bool rac_vad_input_from_proto_options(const ::runanywhere::v1::VADOptions& in,
                                      rac_vad_input_t* out);

bool rac_vad_output_to_proto(const rac_vad_output_t* in,
                             ::runanywhere::v1::VADResult* out);
bool rac_vad_output_from_proto(const ::runanywhere::v1::VADResult& in,
                               rac_vad_output_t* out);

bool rac_vad_statistics_to_proto(const rac_vad_statistics_t* in,
                                 ::runanywhere::v1::VADStatistics* out);
bool rac_vad_statistics_from_proto(const ::runanywhere::v1::VADStatistics& in,
                                   rac_vad_statistics_t* out);

bool rac_speech_activity_to_proto(rac_speech_activity_t in_kind,
                                  int64_t in_timestamp_ms, int32_t in_duration_ms,
                                  ::runanywhere::v1::SpeechActivityEvent* out);
bool rac_speech_activity_from_proto(const ::runanywhere::v1::SpeechActivityEvent& in,
                                    rac_speech_activity_t* out_kind,
                                    int64_t* out_timestamp_ms,
                                    int32_t* out_duration_ms);

// ===========================================================================
// VLM
// ===========================================================================

bool rac_vlm_config_to_proto(const rac_vlm_config_t* in,
                             ::runanywhere::v1::VLMConfiguration* out);
bool rac_vlm_config_from_proto(const ::runanywhere::v1::VLMConfiguration& in,
                               rac_vlm_config_t* out);

// VLM proto VLMGenerationOptions is a subset of the C ABI rac_vlm_options_t
// (only prompt + max_tokens + sampling). Other C-side fields (system_prompt,
// stop_sequences, n_threads, model_family, etc.) are NOT carried on this
// proto by design — they remain backend-private knobs.
bool rac_vlm_options_to_proto(const rac_vlm_options_t* in,
                              const char* prompt /*can be NULL*/,
                              ::runanywhere::v1::VLMGenerationOptions* out);
bool rac_vlm_options_from_proto(const ::runanywhere::v1::VLMGenerationOptions& in,
                                rac_vlm_options_t* out,
                                const char** out_prompt /*optional*/);

bool rac_vlm_result_to_proto(const rac_vlm_result_t* in,
                             ::runanywhere::v1::VLMResult* out);
bool rac_vlm_result_from_proto(const ::runanywhere::v1::VLMResult& in,
                               rac_vlm_result_t* out);

bool rac_vlm_image_to_proto(const rac_vlm_image_t* in,
                            ::runanywhere::v1::VLMImage* out);
bool rac_vlm_image_from_proto(const ::runanywhere::v1::VLMImage& in,
                              rac_vlm_image_t* out);

// ===========================================================================
// DIFFUSION
// ===========================================================================

bool rac_diffusion_config_to_proto(const rac_diffusion_config_t* in,
                                   ::runanywhere::v1::DiffusionConfiguration* out);
bool rac_diffusion_config_from_proto(const ::runanywhere::v1::DiffusionConfiguration& in,
                                     rac_diffusion_config_t* out);

bool rac_diffusion_options_to_proto(const rac_diffusion_options_t* in,
                                    ::runanywhere::v1::DiffusionGenerationOptions* out);
bool rac_diffusion_options_from_proto(
    const ::runanywhere::v1::DiffusionGenerationOptions& in,
    rac_diffusion_options_t* out);

bool rac_diffusion_progress_to_proto(const rac_diffusion_progress_t* in,
                                     ::runanywhere::v1::DiffusionProgress* out);
bool rac_diffusion_progress_from_proto(
    const ::runanywhere::v1::DiffusionProgress& in,
    rac_diffusion_progress_t* out);

bool rac_diffusion_result_to_proto(const rac_diffusion_result_t* in,
                                   ::runanywhere::v1::DiffusionResult* out);
bool rac_diffusion_result_from_proto(const ::runanywhere::v1::DiffusionResult& in,
                                     rac_diffusion_result_t* out);

// ===========================================================================
// LoRA
// ===========================================================================

bool rac_lora_entry_to_proto(const rac_lora_entry_t* in,
                             ::runanywhere::v1::LoraAdapterCatalogEntry* out);
bool rac_lora_entry_from_proto(const ::runanywhere::v1::LoraAdapterCatalogEntry& in,
                               rac_lora_entry_t* out);

// proto LoRAAdapterInfo has no exact C ABI counterpart. We expose helpers that
// build / parse it from the loose set of fields a C consumer typically holds.
// Use these when round-tripping the "adapter is currently applied" snapshot.
bool rac_lora_info_to_proto(const char* adapter_id, const char* adapter_path,
                            float scale, bool applied,
                            const char* error_message /*can be NULL*/,
                            ::runanywhere::v1::LoRAAdapterInfo* out);
bool rac_lora_info_from_proto(const ::runanywhere::v1::LoRAAdapterInfo& in,
                              char** out_adapter_id /*owned*/,
                              char** out_adapter_path /*owned*/,
                              float* out_scale, bool* out_applied,
                              char** out_error_message /*owned, may be NULL*/);

// ===========================================================================
// RAG
// ===========================================================================

bool rac_rag_config_to_proto(const rac_rag_config_t* in,
                             ::runanywhere::v1::RAGConfiguration* out);
bool rac_rag_config_from_proto(const ::runanywhere::v1::RAGConfiguration& in,
                               rac_rag_config_t* out);

bool rac_rag_query_to_proto(const rac_rag_query_t* in,
                            ::runanywhere::v1::RAGQueryOptions* out);
bool rac_rag_query_from_proto(const ::runanywhere::v1::RAGQueryOptions& in,
                              rac_rag_query_t* out);

bool rac_search_result_to_proto(const rac_search_result_t* in,
                                ::runanywhere::v1::RAGSearchResult* out);
bool rac_search_result_from_proto(const ::runanywhere::v1::RAGSearchResult& in,
                                  rac_search_result_t* out);

bool rac_rag_result_to_proto(const rac_rag_result_t* in,
                             ::runanywhere::v1::RAGResult* out);
bool rac_rag_result_from_proto(const ::runanywhere::v1::RAGResult& in,
                               rac_rag_result_t* out);

// ===========================================================================
// EMBEDDINGS
// ===========================================================================

bool rac_embeddings_config_to_proto(const rac_embeddings_config_t* in,
                                    ::runanywhere::v1::EmbeddingsConfiguration* out);
bool rac_embeddings_config_from_proto(
    const ::runanywhere::v1::EmbeddingsConfiguration& in,
    rac_embeddings_config_t* out);

bool rac_embeddings_options_to_proto(const rac_embeddings_options_t* in,
                                     ::runanywhere::v1::EmbeddingsOptions* out);
bool rac_embeddings_options_from_proto(
    const ::runanywhere::v1::EmbeddingsOptions& in,
    rac_embeddings_options_t* out);

bool rac_embedding_vector_to_proto(const rac_embedding_vector_t* in,
                                   ::runanywhere::v1::EmbeddingVector* out);
bool rac_embedding_vector_from_proto(const ::runanywhere::v1::EmbeddingVector& in,
                                     rac_embedding_vector_t* out);

bool rac_embeddings_result_to_proto(const rac_embeddings_result_t* in,
                                    ::runanywhere::v1::EmbeddingsResult* out);
bool rac_embeddings_result_from_proto(
    const ::runanywhere::v1::EmbeddingsResult& in,
    rac_embeddings_result_t* out);

// ===========================================================================
// STORAGE
// ===========================================================================

bool rac_device_storage_to_proto(const rac_device_storage_t* in,
                                 ::runanywhere::v1::DeviceStorageInfo* out);
bool rac_device_storage_from_proto(const ::runanywhere::v1::DeviceStorageInfo& in,
                                   rac_device_storage_t* out);

bool rac_app_storage_to_proto(const rac_app_storage_t* in,
                              ::runanywhere::v1::AppStorageInfo* out);
bool rac_app_storage_from_proto(const ::runanywhere::v1::AppStorageInfo& in,
                                rac_app_storage_t* out);

bool rac_model_storage_metrics_to_proto(
    const rac_model_storage_metrics_t* in,
    ::runanywhere::v1::ModelStorageMetrics* out);
bool rac_model_storage_metrics_from_proto(
    const ::runanywhere::v1::ModelStorageMetrics& in,
    rac_model_storage_metrics_t* out);

bool rac_storage_info_to_proto(const rac_storage_info_t* in,
                               ::runanywhere::v1::StorageInfo* out);
bool rac_storage_info_from_proto(const ::runanywhere::v1::StorageInfo& in,
                                 rac_storage_info_t* out);

bool rac_storage_availability_to_proto(
    const rac_storage_availability_t* in,
    ::runanywhere::v1::StorageAvailability* out);
bool rac_storage_availability_from_proto(
    const ::runanywhere::v1::StorageAvailability& in,
    rac_storage_availability_t* out);

// ===========================================================================
// ERRORS
// ===========================================================================

bool rac_error_to_proto(const rac_error_t* in,
                        ::runanywhere::v1::SDKError* out);
bool rac_error_from_proto(const ::runanywhere::v1::SDKError& in,
                          rac_error_t* out);

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

#endif  // RAC_HAVE_PROTOBUF

#endif  // __cplusplus

#endif  // RAC_PROTO_ADAPTERS_H
