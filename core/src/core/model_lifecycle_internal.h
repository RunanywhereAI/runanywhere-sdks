/**
 * @file model_lifecycle_internal.h
 * @brief Internal layout shared between model-lifecycle implementation TUs.
 *
 * NOT part of the public C ABI; only files under
 * `src/core/` may include this header. Public callers go through the
 * `rac_model_lifecycle.h` C entry points or the per-feature lifecycle
 * bridge headers under `src/features/`.
 *
 * SRP split: the original `model_lifecycle.cpp`
 * mixed proto<->C translation, artifact resolution, auto-download
 * orchestration, lifecycle accessor namespaces, and the C ABI entry
 * points in a single 2.2 KLoC TU. This header is the contract through
 * which the new per-responsibility TUs share access to the canonical
 * lifecycle state without re-exporting it publicly.
 */

#ifndef RAC_CORE_MODEL_LIFECYCLE_INTERNAL_H
#define RAC_CORE_MODEL_LIFECYCLE_INTERNAL_H

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

// Pull in the full service ops definitions so the `LoadedModel` struct can
// hold typed pointers and the C ABI entry points dispatch directly. These
// are part of the C ABI surface and already widely included by the
// service layer; the internal header is private to the lifecycle TUs.
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/ocr/rac_ocr_service.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vlm/rac_vlm_service.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "download_service.pb.h"
#include "model_types.pb.h"
#include "sdk_events.pb.h"

#include <google/protobuf/message_lite.h>
#endif

namespace rac::core::model_lifecycle::detail {

#if defined(RAC_HAVE_PROTOBUF)

struct LoadedModel {
    runanywhere::v1::SDKComponent component{runanywhere::v1::SDK_COMPONENT_UNSPECIFIED};
    runanywhere::v1::ComponentLifecycleState state{
        runanywhere::v1::COMPONENT_LIFECYCLE_STATE_NOT_LOADED};
    std::string model_id;
    std::string resolved_path;
    std::string mmproj_path;
    std::vector<runanywhere::v1::ModelFileDescriptor> resolved_artifacts;
    // Actual backend that executed the load, resolved from the winning
    // rac_engine_vtable_t (see framework_for_engine_name()) whenever that
    // mapping is unambiguous. Falls back to the requested/catalog framework
    // only when the engine name has no 1:1 InferenceFramework (e.g. the
    // shared "platform" engine id). NEVER report the requested/catalog pin
    // here when the actual engine is known to differ from it.
    runanywhere::v1::InferenceFramework framework{runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED};
    std::string framework_name;
    // What the caller/catalog originally asked for (ModelLoadRequest.framework,
    // or the first backend_preferences entry, or the model's catalog framework).
    // May legitimately differ from `framework` above when engine pinning fell
    // back to plain priority order — see `fallback_reason`.
    runanywhere::v1::InferenceFramework requested_backend{
        runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED};
    // v4 placement truth, populated from the winning rac_engine_vtable_t's
    // metadata after a successful load. Never fabricated: fields this build
    // cannot determine truthfully are left empty rather than guessed.
    std::string actual_device_id;
    std::string actual_device_name;
    std::string actual_device_kind;  // cpu | gpu | npu | metal | webgpu | unknown
    std::string runtime_version;
    std::string abi_version;
    // Non-empty only when the actually-selected engine differs from what was
    // requested/preferred (pin unavailable -> priority-order fallback, or a
    // later backend_preferences entry was used instead of the first).
    std::string fallback_reason;
    runanywhere::v1::ModelCategory category{runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED};
    runanywhere::v1::ModelInfo model;
    int64_t loaded_at_ms{0};
    int64_t updated_at_ms{0};
    std::string error_message;
    // Human-readable name; populated by the per-handle lifecycle facade
    // (path-loaded entries). Registry-loaded entries leave this empty.
    std::string model_name;
    // Non-null when this entry was loaded through the per-handle
    // `rac_lifecycle_*` facade. Holds the owning `LifecycleManager*` so the
    // facade can scope its load/unload/query to entries it created. Null for
    // registry-loaded entries (`rac_model_lifecycle_load_proto`).
    void* owner_lifecycle{nullptr};
    // The `rac_<mod>_service_t*` wrapper handed back by the facade's create
    // callback. The facade returns this from get/require/acquire_service;
    // registry-loaded entries leave it null (they dispatch via ops+impl).
    rac_handle_t service_handle{nullptr};
    rac_primitive_t primitive{RAC_PRIMITIVE_UNSPECIFIED};
    const rac_llm_service_ops_t* llm_ops{nullptr};
    const rac_stt_service_ops_t* stt_ops{nullptr};
    const rac_tts_service_ops_t* tts_ops{nullptr};
    const rac_vad_service_ops_t* vad_ops{nullptr};
    const rac_embeddings_service_ops_t* embeddings_ops{nullptr};
    const rac_vlm_service_ops_t* vlm_ops{nullptr};
    const rac_diffusion_service_ops_t* diffusion_ops{nullptr};
    const rac_diarization_service_ops_t* diarization_ops{nullptr};
    const rac_segmentation_service_ops_t* segmentation_ops{nullptr};
    const rac_ocr_service_ops_t* ocr_ops{nullptr};
    void* impl{nullptr};
    int active_refs{0};
    std::atomic<bool> cancel_requested{false};
    std::function<void()> destroy;
};

// Canonical global lifecycle state. Declared here so accessor TUs can
// participate without re-exporting anything to the public ABI. Defined in
// `model_lifecycle.cpp` exactly once.
extern std::mutex g_lifecycle_mutex;
extern std::condition_variable g_lifecycle_cv;
extern std::map<runanywhere::v1::SDKComponent, std::shared_ptr<LoadedModel>> g_loaded;

// Destroy a previously-loaded entry, waiting for in-flight references to
// drain before invoking the cached `destroy` lambda. Safe to call with a
// null shared_ptr.
void destroy_loaded_model(const std::shared_ptr<LoadedModel>& model);

// Validation helpers shared across translation, resolution, and ABI TUs.
inline bool valid_bytes(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

inline const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message);

// =============================================================================
// Translation helpers (defined in `model_lifecycle_translation.cpp`)
// =============================================================================

int64_t now_ms();
std::string generate_event_id();

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out);

runanywhere::v1::SDKComponent component_for_category(runanywhere::v1::ModelCategory category);
rac_primitive_t primitive_for_component(runanywhere::v1::SDKComponent component);

// Reverse of engine_name_for_framework() (model_lifecycle.cpp): map a
// registered engine's manifest name (RAC_ENGINE_ID_*) back to the
// InferenceFramework it actually implements, so load results can report the
// ENGINE THAT REALLY RAN instead of echoing the request/catalog pin. Returns
// INFERENCE_FRAMEWORK_UNSPECIFIED for engine ids with no 1:1 framework (e.g.
// "platform", which backs both FOUNDATION_MODELS and SYSTEM_TTS) or for
// unrecognized names — callers should keep the previously-known framework in
// that ambiguous case rather than guessing.
runanywhere::v1::InferenceFramework framework_for_engine_name(const std::string& engine_name);

// Best-effort, honest device-kind classification for a winning
// rac_engine_vtable_t. Returns "npu" for the QHexRT engine (the only engine
// in this tree that ever executes on the Hexagon NPU — a certainty, not a
// guess). Otherwise inspects metadata.runtimes[] (declared L1 runtimes the
// engine can consume) and maps the first entry through a static
// rac_runtime_id_t -> kind table. Returns "unknown" rather than fabricating a
// device when the engine declares no runtimes (true today for llama.cpp,
// MLX, and QHexRT's declarative list) — matches "cpu | gpu | npu | metal |
// webgpu | unknown" from ModelLoadResult.actual_device_kind.
std::string device_kind_for_vtable(const rac_engine_vtable_t* vt);

rac_model_category_t c_category_from_proto(runanywhere::v1::ModelCategory category);
rac_model_format_t c_format_from_proto(runanywhere::v1::ModelFormat format);
rac_inference_framework_t c_framework_from_proto(runanywhere::v1::InferenceFramework framework);
rac_model_file_role_t c_file_role_from_proto(runanywhere::v1::ModelFileRole role);
runanywhere::v1::ModelFileRole proto_file_role_from_resolved(rac_resolved_model_file_role_t role);

void publish_component_event(runanywhere::v1::SDKComponent component,
                             runanywhere::v1::ComponentLifecycleState previous,
                             runanywhere::v1::ComponentLifecycleState current,
                             const std::string& model_id,
                             const runanywhere::v1::ModelLoadResult* load_result,
                             const runanywhere::v1::ModelUnloadResult* unload_result,
                             const char* error_message);

void publish_current_model_event(const runanywhere::v1::CurrentModelResult& result,
                                 runanywhere::v1::SDKComponent component);

std::string vlm_config_json(const std::string& mmproj_path);

// Advisory `config_json` built from the v4 placement knobs on
// ModelLoadRequest (context_length/threads/use_gpu/accelerator_policy).
// Forwarded to the winning engine's create() per the existing ABI contract
// ("plugins that don't understand config_json MUST ignore it" —
// rac_llm_service.h); does NOT itself guarantee the engine honors any key.
// Returns "" when the request sets none of these fields.
std::string load_options_json(const runanywhere::v1::ModelLoadRequest& request);

// Shallow-merge two flat `{"k":v,...}` JSON objects (no nesting, as produced
// by load_options_json()/vlm_config_json()). Returns whichever side is
// non-empty when the other is empty.
std::string merge_json_objects(const std::string& a, const std::string& b);

// =============================================================================
// Resolution helpers (defined in `model_lifecycle_resolve.cpp`)
// =============================================================================

struct ModelArtifactResolution {
    std::string resolved_path;
    std::string mmproj_path;
    std::vector<runanywhere::v1::ModelFileDescriptor> artifacts;
};

ModelArtifactResolution resolve_model_artifacts(const runanywhere::v1::ModelInfo& model);

void add_artifacts_to_result(
    const std::vector<runanywhere::v1::ModelFileDescriptor>& artifacts,
    google::protobuf::RepeatedPtrField<runanywhere::v1::ModelFileDescriptor>* out);

// v4 placement truth attached to a ModelLoadResult. Every field defaults to
// "unknown" (empty string / UNSPECIFIED enum) rather than a guess; callers
// that cannot determine a field truthfully should simply leave it at the
// default instead of echoing the request back as if it were observed fact.
struct LoadPlacement {
    runanywhere::v1::InferenceFramework requested_backend{
        runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED};
    std::string actual_device_id;
    std::string actual_device_name;
    std::string actual_device_kind;
    std::string runtime_version;
    std::string abi_version;
    std::string fallback_reason;
};

runanywhere::v1::ModelLoadResult
make_load_result(bool success, const std::string& model_id, runanywhere::v1::ModelCategory category,
                 runanywhere::v1::InferenceFramework framework, const std::string& resolved_path,
                 const std::vector<runanywhere::v1::ModelFileDescriptor>& artifacts,
                 int64_t loaded_at_ms, const std::string& error,
                 const LoadPlacement& placement = {}, const std::vector<std::string>& warnings = {});

// Build a LoadPlacement snapshot from a resident LoadedModel, for the
// "already loaded" fast-path and create-then-swap "preserved" branches in
// rac_model_lifecycle_load_proto — both report a PREVIOUSLY loaded model's
// truth rather than the current request's.
LoadPlacement placement_from_loaded(const LoadedModel& loaded);

bool matches_current_filter(const LoadedModel& loaded, bool has_category,
                            runanywhere::v1::ModelCategory category, bool has_framework,
                            runanywhere::v1::InferenceFramework framework);

void fill_snapshot(const LoadedModel* loaded, runanywhere::v1::SDKComponent component,
                   runanywhere::v1::ComponentLifecycleSnapshot* out);

runanywhere::v1::InferenceFramework
preferred_framework_for(const runanywhere::v1::ModelLoadRequest& request,
                        const runanywhere::v1::ModelInfo& model);

runanywhere::v1::ModelCategory
preferred_category_for(const runanywhere::v1::ModelLoadRequest& request,
                       const runanywhere::v1::ModelInfo& model);

// =============================================================================
// Auto-download helpers (defined in `model_lifecycle_download.cpp`)
// =============================================================================

bool model_artifact_present(const runanywhere::v1::ModelInfo& model);
bool model_has_download_source(const runanywhere::v1::ModelInfo& model);

rac_result_t download_and_wait_for_model(const std::string& model_id,
                                         const runanywhere::v1::ModelInfo& registered_model,
                                         std::string* out_error, int timeout_seconds = 300);

#endif  // RAC_HAVE_PROTOBUF

[[maybe_unused]] rac_result_t feature_unavailable(rac_proto_buffer_t* out);

}  // namespace rac::core::model_lifecycle::detail

#endif  // RAC_CORE_MODEL_LIFECYCLE_INTERNAL_H
