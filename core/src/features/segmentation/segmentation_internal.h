#ifndef RAC_FEATURES_SEGMENTATION_SEGMENTATION_INTERNAL_H
#define RAC_FEATURES_SEGMENTATION_SEGMENTATION_INTERNAL_H

#include <cstddef>
#include <memory>

#include "rac/core/rac_types.h"

namespace rac::segmentation {

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

using ComponentOperationAdmittedTestHook = void (*)(rac_handle_t, void*);

class ComponentOperationLease {
   public:
    explicit ComponentOperationLease(rac_handle_t handle);
    ~ComponentOperationLease();

    explicit operator bool() const { return entry_ != nullptr; }
    rac_handle_t component() const { return entry_ ? entry_->component : nullptr; }

    ComponentOperationLease(const ComponentOperationLease&) = delete;
    ComponentOperationLease& operator=(const ComponentOperationLease&) = delete;

   private:
    rac_handle_t handle_ = nullptr;
    std::shared_ptr<ComponentLifetimeEntry> entry_;
    ComponentOperationFrame frame_;
};

void set_component_operation_admitted_test_hook(ComponentOperationAdmittedTestHook hook,
                                                void* user_data);

}  // namespace rac::segmentation

#endif /* RAC_FEATURES_SEGMENTATION_SEGMENTATION_INTERNAL_H */
