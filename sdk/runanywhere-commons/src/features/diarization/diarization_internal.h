#ifndef RAC_FEATURES_DIARIZATION_DIARIZATION_INTERNAL_H
#define RAC_FEATURES_DIARIZATION_DIARIZATION_INTERNAL_H

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/diarization/rac_diarization_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diarization.pb.h"
#endif

namespace rac::diarization {

struct ComponentLifetimeEntry {
    rac_handle_t component = nullptr;
    rac_handle_t lifecycle = nullptr;
    size_t active_operations = 0;
    bool accepting_operations = true;
};

struct ComponentOperationFrame {
    rac_handle_t handle = nullptr;
    ComponentOperationFrame* previous = nullptr;
};

using ComponentOperationAdmittedTestHook = void (*)(rac_handle_t handle, void* user_data);

/** Internal lease that keeps an opaque component and its lifecycle alive. */
class ComponentOperationLease {
   public:
    explicit ComponentOperationLease(rac_handle_t handle);
    ~ComponentOperationLease();

    explicit operator bool() const { return entry_ != nullptr; }
    rac_handle_t component() const { return entry_ ? entry_->component : nullptr; }
    rac_handle_t lifecycle() const { return entry_ ? entry_->lifecycle : nullptr; }

    ComponentOperationLease(const ComponentOperationLease&) = delete;
    ComponentOperationLease& operator=(const ComponentOperationLease&) = delete;

   private:
    rac_handle_t handle_ = nullptr;
    std::shared_ptr<ComponentLifetimeEntry> entry_;
    ComponentOperationFrame frame_;
};

bool register_component_lifetime(rac_handle_t component_handle, rac_handle_t lifecycle_handle);
bool current_thread_has_component_operation(rac_handle_t handle);
std::shared_ptr<ComponentLifetimeEntry> close_component_admission(rac_handle_t handle);
void reopen_component_admission(rac_handle_t handle,
                                const std::shared_ptr<ComponentLifetimeEntry>& entry);
void wait_for_component_operations(const std::shared_ptr<ComponentLifetimeEntry>& entry);
rac_handle_t remove_component_lifetime(rac_handle_t handle,
                                       const std::shared_ptr<ComponentLifetimeEntry>& entry);

void set_component_operation_admitted_test_hook(ComponentOperationAdmittedTestHook hook,
                                                void* user_data);

#if defined(RAC_HAVE_PROTOBUF)

rac_result_t options_from_proto(const runanywhere::v1::DiarizationOptions* proto,
                                rac_diarization_options_t* out_options,
                                runanywhere::v1::DiarizationAudioEncoding* out_encoding);

rac_result_t decode_audio(const uint8_t* bytes, size_t size,
                          runanywhere::v1::DiarizationAudioEncoding encoding, int32_t channel_count,
                          bool require_nonempty, std::vector<float>* out_samples);

rac_result_t result_to_proto(const rac_diarization_result_t& result, const char* fallback_model_id,
                             runanywhere::v1::DiarizationResult* out_proto);

#endif

void register_stream_component(rac_handle_t component_handle, rac_handle_t lifecycle_handle);
void unregister_stream_component(rac_handle_t component_handle);
rac_result_t begin_stream_component_teardown(rac_handle_t component_handle);
void end_stream_component_teardown(rac_handle_t component_handle);

}  // namespace rac::diarization

#endif  // RAC_FEATURES_DIARIZATION_DIARIZATION_INTERNAL_H
