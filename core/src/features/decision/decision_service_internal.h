#ifndef RAC_FEATURES_DECISION_DECISION_SERVICE_INTERNAL_H
#define RAC_FEATURES_DECISION_DECISION_SERVICE_INTERNAL_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

namespace rac::decision {

rac_result_t create_service(const char* model_id, const char* config_json,
                            rac_handle_t* out_handle);

}  // namespace rac::decision

#endif /* RAC_FEATURES_DECISION_DECISION_SERVICE_INTERNAL_H */